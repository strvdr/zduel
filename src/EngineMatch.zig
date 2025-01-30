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

//! Engine match management and gameplay coordination.
//!
//! Handles:
//! - Match initialization
//! - Move execution
//! - Game state tracking
//! - Result determination
//!
//! ## Match Types
//! - Blitz (1s/move)
//! - Rapid (5s/move)
//! - Classical (15s/move)
//! - Tournament (Bo3)
//!
//! ## Usage
//! ```zig
//! var match = try MatchManager.init(engine1, engine2, allocator, preset);
//! const result = try match.playMatch();
//! ```

const std = @import("std");
const main = @import("main.zig");
const EnginePlay = @import("EnginePlay.zig");
const Engine = EnginePlay.Engine;
const EngineManager = EnginePlay.EngineManager;
const CLI = @import("CLI.zig");
const DisplayManager = @import("DisplayManager.zig").DisplayManager;
const Logger = @import("logger.zig").Logger;

const MatchResult = enum {
    win,
    loss,
    draw,
};

pub const UciEngineError = error{
    ProcessStartFailed,
    ProcessTerminated,
    UciInitFailed,
    InvalidExecutable,
};

pub const UciEngine = struct {
    name: []const u8,
    process: std.process.Child,
    stdoutReader: std.fs.File.Reader,
    stdinWriter: std.fs.File.Writer,
    color: []const u8,
    isInitialized: bool = false,

    pub fn init(engine: Engine, arena: *std.heap.ArenaAllocator, color: []const u8) !UciEngine {
        // First check if the file exists and is executable
        const file = std.fs.openFileAbsolute(engine.path, .{}) catch |err| {
            std.debug.print("Failed to open engine file: {s}\nPath: {s}\n", .{
                @errorName(err),
                engine.path,
            });
            return UciEngineError.InvalidExecutable;
        };
        file.close();

        // Create process
        var process = std.process.Child.init(
            &[_][]const u8{engine.path},
            arena.allocator(),
        );

        // Set up pipes
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        // Try to spawn the process
        process.spawn() catch |err| {
            std.debug.print("Failed to spawn engine process: {s}\nPath: {s}\n", .{
                @errorName(err),
                engine.path,
            });
            return UciEngineError.ProcessStartFailed;
        };

        // Wait a short time to ensure process started successfully
        std.time.sleep(100 * std.time.ns_per_ms);

        // Check if process is still running
        const term = process.term orelse {
            // Use the engine name that was already allocated in the arena
            return UciEngine{
                .name = engine.name,
                .process = process,
                .stdoutReader = process.stdout.?.reader(),
                .stdinWriter = process.stdin.?.writer(),
                .color = color,
                .isInitialized = false,
            };
        };

        // If we get here, process terminated immediately
        std.debug.print("Engine process terminated immediately with status: {any}\n", .{term});
        return UciEngineError.ProcessTerminated;
    }
    pub fn deinit(self: *UciEngine) void {
        // First try graceful shutdown with UCI quit command
        if (self.isInitialized) {
            // Send quit command and give engine time to process it
            self.sendCommand(null, "quit") catch {};
            std.time.sleep(100 * std.time.ns_per_ms);

            // Check if process terminated naturally
            if (self.process.term == null) {
                // Process still running, try terminate signal
                _ = self.process.kill() catch {};

                // Give it a brief moment to terminate
                std.time.sleep(50 * std.time.ns_per_ms);

                // If still running, force kill
                if (self.process.term == null) {
                    _ = self.process.kill() catch {};
                }
            }
        } else {
            // If not initialized, just force kill
            _ = self.process.kill() catch {};
        }

        // Clean up pipes in reverse order
        if (self.process.stderr) |stderr| {
            stderr.close();
        }
        if (self.process.stdout) |stdOut| {
            stdOut.close();
        }
        if (self.process.stdin) |stdIn| {
            stdIn.close();
        }

        // Wait with timeout for process to fully terminate
        var timeout: usize = 0;
        while (timeout < 10) : (timeout += 1) {
            if (self.process.wait()) |_| {
                break;
            } else |_| {
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
    }
    pub fn sendCommand(self: *UciEngine, logger: ?*Logger, command: []const u8) !void {
        // Check if process is still running
        if (self.process.term) |term| {
            std.debug.print("Engine process terminated with status: {any}\n", .{term});
            return UciEngineError.ProcessTerminated;
        }

        if (logger) |l| {
            try l.log(self.name, true, command);
        }

        self.stdinWriter.print("{s}\n", .{command}) catch |err| {
            std.debug.print("Failed to send command to engine {s}: {s}\nCommand: {s}\n", .{
                self.name,
                @errorName(err),
                command,
            });
            return err;
        };
    }

    pub fn readResponse(self: *UciEngine, logger: *Logger, buffer: []u8) !?[]const u8 {
        // Check if process is still running
        if (self.process.term) |term| {
            std.debug.print("Engine process terminated with status: {any}\n", .{term});
            return UciEngineError.ProcessTerminated;
        }

        const response = self.stdoutReader.readUntilDelimiterOrEof(buffer, '\n') catch |err| {
            std.debug.print("Error reading from engine {s}: {s}\n", .{
                self.name,
                @errorName(err),
            });
            return err;
        };

        if (response) |line| {
            try logger.log(self.name, false, line);
            return line;
        }

        return null;
    }

    pub fn initialize(self: *UciEngine, logger: *Logger) !void {
        var buffer: [4096]u8 = undefined;

        // Send UCI command and wait for uciok
        try self.sendCommand(logger, "uci");
        var got_uciok = false;
        var timeout: usize = 0;
        while (!got_uciok and timeout < 100) : (timeout += 1) {
            if (try self.readResponse(logger, &buffer)) |response| {
                if (std.mem.eql(u8, response, "uciok")) {
                    got_uciok = true;
                }
            }
            if (!got_uciok) {
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
        if (!got_uciok) return UciEngineError.UciInitFailed;

        // Send isready and wait for readyok
        try self.sendCommand(logger, "isready");
        var got_readyok = false;
        timeout = 0;
        while (!got_readyok and timeout < 100) : (timeout += 1) {
            if (try self.readResponse(logger, &buffer)) |response| {
                if (std.mem.eql(u8, response, "readyok")) {
                    got_readyok = true;
                }
            }
            if (!got_readyok) {
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
        if (!got_readyok) return UciEngineError.UciInitFailed;

        try self.sendCommand(logger, "setoption name Hash value 128");
        try self.sendCommand(logger, "setoption name MultiPV value 1");
        try self.sendCommand(logger, "ucinewgame");

        self.isInitialized = true;
    }
};

pub const MatchPreset = struct {
    name: []const u8,
    description: []const u8,
    moveTimeMS: u32,
    gameCount: u32 = 1,
};

pub const MATCH_PRESETS = [_]MatchPreset{
    .{
        .name = "Blitz",
        .description = "Quick games with 1 second per move",
        .moveTimeMS = 1000,
    },
    .{
        .name = "Rapid",
        .description = "Medium-paced games with 5 seconds per move",
        .moveTimeMS = 5000,
    },
    .{
        .name = "Classical",
        .description = "Slow games with 15 seconds per move for deep analysis",
        .moveTimeMS = 15000,
    },
    .{
        .name = "Tournament",
        .description = "Best of 3 rapid games",
        .moveTimeMS = 5000,
        .gameCount = 3,
    },
};

pub const MatchManager = struct {
    white: UciEngine,
    black: UciEngine,
    arena: std.heap.ArenaAllocator,
    logger: Logger,
    moveTimeMS: u32,
    gameCount: u32,
    colors: CLI.Color,
    moveCount: usize = 0,

    pub fn init(whiteEngine: Engine, blackEngine: Engine, allocator: std.mem.Allocator, preset: MatchPreset) !MatchManager {
        const colors = main.colors;
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var logger = try Logger.init(allocator);
        errdefer logger.deinit();

        // First duplicate the engine names into our arena
        const whiteName = try arena.allocator().dupe(u8, whiteEngine.name);
        const blackName = try arena.allocator().dupe(u8, blackEngine.name);
        const whitePath = try arena.allocator().dupe(u8, whiteEngine.path);
        const blackPath = try arena.allocator().dupe(u8, blackEngine.path);

        // Create engine structs with our arena-allocated strings
        const whiteEngineArena = Engine{ .name = whiteName, .path = whitePath };
        const blackEngineArena = Engine{ .name = blackName, .path = blackPath };

        // Now initialize the UCI engines
        const white = try UciEngine.init(whiteEngineArena, &arena, colors.whitePieces);
        const black = try UciEngine.init(blackEngineArena, &arena, colors.blackPieces);

        var manager = MatchManager{
            .white = white,
            .black = black,
            .arena = arena,
            .logger = logger,
            .moveTimeMS = preset.moveTimeMS,
            .gameCount = preset.gameCount,
            .colors = colors,
            .moveCount = 0,
        };

        try manager.logger.start(manager.white.name, manager.black.name);
        return manager;
    }

    pub fn deinit(self: *MatchManager) void {

        // Send quit command to engines
        self.white.sendCommand(&self.logger, "quit") catch {};
        self.black.sendCommand(&self.logger, "quit") catch {};

        self.white.deinit();
        self.black.deinit();
        self.logger.deinit();
        self.arena.deinit();
    }

    fn getPositionKey(self: *MatchManager, display: *DisplayManager) ![]const u8 {
        var key = std.ArrayList(u8).init(self.arena.allocator());
        errdefer key.deinit();

        // Create a string representation of the current board state
        for (display.board) |rank| {
            for (rank) |square| {
                if (square) |piece| {
                    try key.append(piece.toChar());
                } else {
                    try key.append('-');
                }
            }
        }
        return key.toOwnedSlice();
    }

    pub fn playMatch(self: *MatchManager) !MatchResult {
        var display = try DisplayManager.init(self.arena.allocator());
        defer display.deinit();

        try display.initializeBoard();

        self.moveCount = 0;

        // Initialize both engines if not already done
        if (!self.white.isInitialized) try self.white.initialize(&self.logger);
        if (!self.black.isInitialized) try self.black.initialize(&self.logger);

        var moves = std.ArrayList([]const u8).init(self.arena.allocator());
        defer moves.deinit();

        // Reset position for both engines
        try self.white.sendCommand(&self.logger, "position startpos");
        try self.black.sendCommand(&self.logger, "position startpos");
        try self.white.sendCommand(&self.logger, "isready");
        try self.black.sendCommand(&self.logger, "isready");
        // Wait for readyok from both engines
        var buf: [4096]u8 = undefined;
        var white_ready = false;
        var black_ready = false;

        while (!white_ready or !black_ready) {
            if (!white_ready) {
                if (try self.white.readResponse(&self.logger, &buf)) |response| {
                    if (std.mem.eql(u8, response, "readyok")) white_ready = true;
                }
            }
            if (!black_ready) {
                if (try self.black.readResponse(&self.logger, &buf)) |response| {
                    if (std.mem.eql(u8, response, "readyok")) black_ready = true;
                }
            }
        }
        var currentPlayer = &self.white;
        var isGameOver = false;
        var winner: ?*UciEngine = null;
        var drawReason: ?[]const u8 = null;
        var positions = PositionMap.init(&self.arena);
        defer positions.deinit();

        while (!isGameOver) {
            self.moveCount += 1;
            const posCommand = try std.fmt.allocPrint(self.arena.allocator(), "position startpos moves {s}", .{try formatMovesList(self.arena.allocator(), &moves)});

            const goCommand = try std.fmt.allocPrint(self.arena.allocator(), "go movetime {d}", .{self.moveTimeMS});

            try currentPlayer.sendCommand(&self.logger, posCommand);
            try currentPlayer.sendCommand(&self.logger, goCommand);

            var buffer: [4096]u8 = undefined;
            var move: ?[]const u8 = null;

            while (try currentPlayer.readResponse(&self.logger, &buffer)) |response| {
                if (std.mem.startsWith(u8, response, "bestmove")) {
                    if (isStockfishForfeit(response)) {
                        // Handle Stockfish forfeit/mate
                        isGameOver = true;
                        winner = if (currentPlayer == &self.white) &self.black else &self.white;
                        try main.stdout.print("\n{s}{s} acknowledges defeat!{s}\n", .{
                            currentPlayer.color,
                            currentPlayer.name,
                            main.colors.reset,
                        });
                        break;
                    }
                    move = try self.arena.allocator().dupe(u8, response[9..13]);
                    break;
                }
            }

            // Check for resignation
            if (move) |m| {
                // Check for resignation
                if (std.mem.eql(u8, m, "0000")) {
                    isGameOver = true;
                    winner = if (currentPlayer == &self.white) &self.black else &self.white;
                    try main.stdout.print("\n{s}{s} resigns!{s}\n", .{
                        currentPlayer.color,
                        currentPlayer.name,
                        main.colors.reset,
                    });
                } else {
                    try moves.append(m);
                    try display.updateMove(m, currentPlayer.name, self.moveCount);

                    if (isCheckmate(m)) {
                        winner = currentPlayer;
                        isGameOver = true;
                    } else if (isStalemate(m)) {
                        isGameOver = true;
                        drawReason = "stalemate";
                    }
                }

                // Check for three-fold repetition
                const repetitions = try positions.recordPosition(&display);
                if (repetitions >= 3) {
                    isGameOver = true;
                    drawReason = "threefold repetition";
                }

                currentPlayer = if (currentPlayer == &self.white) &self.black else &self.white;
            } else {
                isGameOver = true;
            }

            if (moves.items.len >= 100) {
                isGameOver = true;
                drawReason = "move limit";
            }
        }
        try main.stdout.print("\x1b[{d};0H\x1b[J", .{display.boardStartLine + 12});
        const c = main.colors;
        try main.stdout.print("\n{s}Game Over!{s} ", .{ c.bold, c.reset });

        var result = MatchResult.draw;

        if (winner) |w| {
            try main.stdout.print("{s}{s}{s} wins by checkmate!\n", .{ w.color, w.name, c.reset });
            result = if (w == &self.white) .win else .loss;
        } else if (drawReason) |reason| {
            try main.stdout.print("{s}Draw by {s}!{s}\n", .{ c.yellow, reason, c.reset });
        } else {
            try main.stdout.print("{s}Draw!{s}\n", .{ c.yellow, c.reset });
        }

        try main.bw.flush();
        return result;
    }
};

fn formatMovesList(allocator: std.mem.Allocator, moves: *const std.ArrayList([]const u8)) ![]const u8 {
    if (moves.items.len == 0) return "";

    var total_length: usize = 0;
    for (moves.items) |move| {
        total_length += move.len + 1;
    }

    var result = try allocator.alloc(u8, total_length);
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

fn isCheckmate(move: []const u8) bool {
    return std.mem.endsWith(u8, move, "#");
}

fn isStalemate(move: []const u8) bool {
    return std.mem.endsWith(u8, move, "=");
}

pub fn DisplayMatchPresets() !void {
    const c = main.colors;
    try main.stdout.print("\n{s}Available Match Types:{s}\n", .{ c.green, c.reset });
    try main.stdout.print("══════════════════════\n", .{});

    for (MATCH_PRESETS, 0..) |preset, i| {
        try main.stdout.print("{s}[{d}]{s} {s}{s}{s}\n", .{
            c.cyan,
            i + 1,
            c.reset,
            c.bold,
            preset.name,
            c.reset,
        });
        try main.stdout.print("   {s}{s}{s}\n", .{
            c.dim,
            preset.description,
            c.reset,
        });
        if (preset.gameCount > 1) {
            try main.stdout.print("   {s}Games:{s} {d}\n", .{
                c.dim,
                c.reset,
                preset.gameCount,
            });
        }
        try main.bw.flush();
    }
}

const PositionMap = struct {
    map: std.StringHashMap(usize),
    arena: *std.heap.ArenaAllocator,

    fn init(arena: *std.heap.ArenaAllocator) PositionMap {
        return .{
            .map = std.StringHashMap(usize).init(arena.allocator()),
            .arena = arena,
        };
    }

    fn recordPosition(self: *PositionMap, board: *DisplayManager) !usize {
        var key = std.ArrayList(u8).init(self.arena.allocator());
        defer key.deinit();

        // Create a string representation of the current board state
        for (board.board) |rank| {
            for (rank) |square| {
                if (square) |piece| {
                    try key.append(piece.toChar());
                } else {
                    try key.append('-');
                }
            }
        }

        // Convert to string
        const positionStr = try self.arena.allocator().dupe(u8, key.items);

        // Get or update count
        const result = try self.map.getOrPut(positionStr);
        if (!result.found_existing) {
            result.value_ptr.* = 0;
        }
        result.value_ptr.* += 1;
        return result.value_ptr.*;
    }

    fn deinit(self: *PositionMap) void {
        var it = self.map.keyIterator();
        while (it.next()) |key| {
            self.arena.allocator().free(key.*);
        }
        self.map.deinit();
    }
};

fn isStockfishForfeit(response: []const u8) bool {
    return std.mem.indexOf(u8, response, "bestmove (none)") != null;
}
