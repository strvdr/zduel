//    zduel is a CLI chess tool.
//    Copyright (C) <2025>  <Strydr Silverberg>
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const main = @import("main.zig");
const Engine = @import("EnginePlay.zig").Engine;
const EngineManager = @import("EnginePlay.zig").EngineManager;
const Color = @import("CLI.zig").Color;
const DisplayManager = @import("DisplayManager.zig").DisplayManager;
const Logger = @import("logger.zig").Logger;
const UciEngine = @import("EngineMatch.zig").UciEngine;

pub const PlayerMatchPreset = struct {
    name: []const u8,
    description: []const u8,
    engineTimeMS: u32,
};

pub const PLAYER_MATCH_PRESETS = [_]PlayerMatchPreset{
    .{
        .name = "Casual",
        .description = "Engine uses 1 second per move - good for casual games",
        .engineTimeMS = 1000,
    },
    .{
        .name = "Tournament",
        .description = "Engine uses 5 seconds per move - challenging but fair",
        .engineTimeMS = 5000,
    },
    .{
        .name = "Master",
        .description = "Engine uses 15 seconds per move - prepare to be crushed!",
        .engineTimeMS = 15000,
    },
};

pub const PlayerMatchManager = struct {
    engine: UciEngine,
    arena: std.heap.ArenaAllocator,
    logger: Logger,
    engineTimeMS: u32,
    colors: Color,
    move_count: usize = 0,
    playerIsWhite: bool,

    pub fn init(
        selectedEngine: Engine,
        allocator: std.mem.Allocator,
        preset: PlayerMatchPreset,
        playerIsWhite: bool,
    ) !PlayerMatchManager {
        const colors = main.colors;
        var arena = std.heap.ArenaAllocator.init(allocator);
        var logger = try Logger.init(allocator);
        errdefer logger.deinit();

        // Initialize engine with appropriate color
        const engineColor = if (playerIsWhite) main.colors.whitePieces else main.colors.blackPieces;
        const engine = try UciEngine.init(selectedEngine, &arena, engineColor);

        var manager = PlayerMatchManager{
            .engine = engine,
            .arena = arena,
            .logger = logger,
            .engineTimeMS = preset.engineTimeMS,
            .colors = colors,
            .playerIsWhite = playerIsWhite,
        };

        const playerName = "Player";
        try manager.logger.start(
            if (playerIsWhite) playerName else engine.name,
            if (playerIsWhite) engine.name else playerName,
        );
        return manager;
    }

    pub fn deinit(self: *PlayerMatchManager) void {
        self.engine.sendCommand(&self.logger, "quit") catch {};
        self.engine.deinit();
        self.logger.deinit();
        self.arena.deinit();
    }

    const GameResult = enum {
        playerWin,
        engineWin,
        draw,
    };

    fn isValidMove(move: []const u8) bool {
        if (move.len != 4) return false;

        // Validate first square (e.g., 'e2')
        if (move[0] < 'a' or move[0] > 'h') return false;
        if (move[1] < '1' or move[1] > '8') return false;

        // Validate second square (e.g., 'e4')
        if (move[2] < 'a' or move[2] > 'h') return false;
        if (move[3] < '1' or move[3] > '8') return false;

        return true;
    }

    pub fn playGame(self: *PlayerMatchManager) !GameResult {
        var display = try DisplayManager.init(self.arena.allocator());
        defer display.deinit();

        try display.initializeBoard();
        try self.engine.initialize(&self.logger);

        var moves = std.ArrayList([]const u8).init(self.arena.allocator());
        defer moves.deinit();

        const c = main.colors;
        var isGameOver = false;
        var winner: ?GameResult = null;

        while (!isGameOver) {
            self.move_count += 1;
            const isPlayerTurn = self.playerIsWhite == (self.move_count % 2 == 1);

            if (isPlayerTurn) {
                // Clear the area below the board for messages
                try main.stdout.print("\x1b[{d};0H\x1b[J", .{display.boardStartLine + 12});
                try main.stdout.print("\n{s}Your move{s} (e.g., e2e4 or 0000 to resign): ", .{ c.green, c.reset });
                try main.bw.flush();

                var buf: [10]u8 = undefined;
                const userInput = (try main.stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse return error.InvalidInput;
                const move = std.mem.trim(u8, userInput, &std.ascii.whitespace);

                if (std.mem.eql(u8, move, "0000")) {
                    winner = .engineWin;
                    isGameOver = true;
                    continue;
                }

                if (!isValidMove(move)) {
                    try main.stdout.print("\x1b[{d};0H\x1b[J", .{display.boardStartLine + 12});
                    try main.stdout.print("\n{s}Invalid move format. Use standard notation (e.g., e2e4){s}\n", .{ c.red, c.reset });
                    self.move_count -= 1; // Revert move count since this was invalid
                    continue;
                }

                const playerMove = try self.arena.allocator().dupe(u8, move);
                try moves.append(playerMove);
                try display.updateMove(playerMove, "Player", self.move_count);
            } else {
                const posCommand = try std.fmt.allocPrint(self.arena.allocator(), "position startpos moves {s}", .{try formatMovesList(self.arena.allocator(), &moves)});

                const goCommand = try std.fmt.allocPrint(self.arena.allocator(), "go movetime {d}", .{self.engineTimeMS});

                try self.engine.sendCommand(&self.logger, posCommand);
                try self.engine.sendCommand(&self.logger, goCommand);

                var buffer: [4096]u8 = undefined;
                var engineMove: ?[]const u8 = null;

                while (try self.engine.readResponse(&self.logger, &buffer)) |response| {
                    if (std.mem.startsWith(u8, response, "bestmove")) {
                        engineMove = try self.arena.allocator().dupe(u8, response[9..13]);
                        break;
                    }
                }

                if (engineMove) |m| {
                    try moves.append(m);
                    try display.updateMove(m, self.engine.name, self.move_count);
                }
            }

            if (moves.items.len >= 100) {
                isGameOver = true;
                winner = .draw;
            }
        }

        try main.stdout.print("\x1b[{d};0H\x1b[J", .{display.boardStartLine + 12});
        try main.stdout.print("\n{s}Game Over!{s} ", .{ c.bold, c.reset });

        const result = winner orelse .draw;
        switch (result) {
            .playerWin => try main.stdout.print("{s}Congratulations! You win!{s}\n", .{ c.green, c.reset }),
            .engineWin => try main.stdout.print("{s}The engine wins!{s}\n", .{ c.red, c.reset }),
            .draw => try main.stdout.print("{s}Game drawn!{s}\n", .{ c.yellow, c.reset }),
        }

        try main.bw.flush();
        return result;
    }
};

fn formatMovesList(allocator: std.mem.Allocator, moves: *const std.ArrayList([]const u8)) ![]const u8 {
    if (moves.items.len == 0) return "";

    var totalLength: usize = 0;
    for (moves.items) |move| {
        totalLength += move.len + 1;
    }

    var result = try allocator.alloc(u8, totalLength);
    var pos: usize = 0;

    for (moves.items) |move| {
        @memcpy(result[pos .. pos + move.len], move);
        if (pos + move.len < result.len) {
            result[pos + move.len] = ' ';
        }
        pos += move.len + 1;
    }

    return result[0..pos -| 1];
}
