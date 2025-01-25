const std = @import("std");
const enginePlay = @import("enginePlay.zig");
const Engine = enginePlay.Engine;
const EngineManager = enginePlay.EngineManager;
const Color = @import("cli.zig").Color;
const DisplayManager = @import("displayManager.zig").DisplayManager;
const Logger = @import("logger.zig").Logger;

const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub const UciEngine = struct {
    name: []const u8,
    process: std.process.Child,
    stdoutReader: std.fs.File.Reader,
    stdinWriter: std.fs.File.Writer,
    color: []const u8,

    pub fn init(engine: Engine, arena: *std.heap.ArenaAllocator, color: []const u8) !UciEngine {
        var process = std.process.Child.init(
            &[_][]const u8{engine.path},
            arena.allocator(),
        );
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;

        try process.spawn();

        return UciEngine{
            .name = try arena.allocator().dupe(u8, engine.name),
            .process = process,
            .stdoutReader = process.stdout.?.reader(),
            .stdinWriter = process.stdin.?.writer(),
            .color = color,
        };
    }

    pub fn deinit(self: *UciEngine) void {
        _ = self.process.kill() catch {};
    }

    pub fn sendCommand(self: *UciEngine, logger: *Logger, command: []const u8) !void {
        try logger.log(self.name, true, command);
        try self.stdinWriter.print("{s}\n", .{command});
    }

    pub fn readResponse(self: *UciEngine, logger: *Logger, buffer: []u8) !?[]const u8 {
        if (try self.stdoutReader.readUntilDelimiterOrEof(buffer, '\n')) |response| {
            try logger.log(self.name, false, response);
            return response;
        }
        return null;
    }

    pub fn initialize(self: *UciEngine, logger: *Logger) !void {
        var buffer: [4096]u8 = undefined;

        try self.sendCommand(logger, "uci");
        while (try self.readResponse(logger, &buffer)) |response| {
            if (std.mem.eql(u8, response, "uciok")) break;
        }

        try self.sendCommand(logger, "isready");
        while (try self.readResponse(logger, &buffer)) |response| {
            if (std.mem.eql(u8, response, "readyok")) break;
        }

        try self.sendCommand(logger, "setoption name Hash value 128");
        try self.sendCommand(logger, "setoption name MultiPV value 1");
        try self.sendCommand(logger, "ucinewgame");
    }
};

const MatchPreset = struct {
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
    colors: Color,
    move_count: usize = 0,

    pub fn init(whiteEngine: Engine, blackEngine: Engine, allocator: std.mem.Allocator, preset: MatchPreset) !MatchManager {
        const colors = Color{};
        var arena = std.heap.ArenaAllocator.init(allocator);
        var logger = try Logger.init(allocator);
        errdefer logger.deinit();

        const white = try UciEngine.init(whiteEngine, &arena, colors.blue);
        const black = try UciEngine.init(blackEngine, &arena, colors.magenta);

        var manager = MatchManager{
            .white = white,
            .black = black,
            .arena = arena,
            .logger = logger,
            .moveTimeMS = preset.moveTimeMS,
            .gameCount = preset.gameCount,
            .colors = colors,
        };

        try manager.logger.start(manager.white.name, manager.black.name);
        return manager;
    }

    pub fn deinit(self: *MatchManager) void {
        self.white.deinit();
        self.black.deinit();
        self.logger.deinit();
        self.arena.deinit();
    }

    const MatchResult = enum {
        whiteWin,
        blackWin,
        draw,
    };
    pub fn playMatch(self: *MatchManager) !MatchResult {
        var display = try DisplayManager.init(self.arena.allocator());
        defer display.deinit();

        try display.initializeBoard();
        try self.white.initialize(&self.logger);
        try self.black.initialize(&self.logger);

        var moves = std.ArrayList([]const u8).init(self.arena.allocator());
        defer moves.deinit();

        var currentPlayer = &self.white;
        var isGameOver = false;
        var winner: ?*UciEngine = null;
        var drawReason: ?[]const u8 = null;
        var repetitionCount = std.StringHashMap(usize).init(self.arena.allocator());
        defer repetitionCount.deinit();

        while (!isGameOver) {
            self.move_count += 1;
            const position_cmd = try std.fmt.allocPrint(self.arena.allocator(), "position startpos moves {s}", .{try formatMovesList(self.arena.allocator(), &moves)});

            const go_cmd = try std.fmt.allocPrint(self.arena.allocator(), "go movetime {d}", .{self.moveTimeMS});

            try currentPlayer.sendCommand(&self.logger, position_cmd);
            try currentPlayer.sendCommand(&self.logger, go_cmd);

            var buffer: [4096]u8 = undefined;
            var move: ?[]const u8 = null;

            while (try currentPlayer.readResponse(&self.logger, &buffer)) |response| {
                if (std.mem.startsWith(u8, response, "bestmove")) {
                    move = try self.arena.allocator().dupe(u8, response[9..13]);
                    break;
                }
            }

            if (move) |m| {
                try moves.append(m);
                try display.updateMove(m, currentPlayer.name, self.move_count);

                if (isCheckmate(m)) {
                    winner = currentPlayer;
                    isGameOver = true;
                } else if (isStalemate(m)) {
                    isGameOver = true;
                    drawReason = "stalemate";
                }

                const position = try formatMovesList(self.arena.allocator(), &moves);
                const count = (repetitionCount.get(position) orelse 0) + 1;
                try repetitionCount.put(position, count);

                if (count >= 3) {
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

        try stdout.print("\x1b[{d};0H\x1b[J", .{display.boardStartLine + 12});
        const c = self.colors;
        try stdout.print("\n{s}Game Over!{s} ", .{ c.bold, c.reset });

        var result = MatchResult.draw;

        if (winner) |w| {
            try stdout.print("{s}{s}{s} wins by checkmate!\n", .{ w.color, w.name, c.reset });
            result = if (w == &self.white) .whiteWin else .blackWin;
        } else if (drawReason) |reason| {
            try stdout.print("{s}Draw by {s}!{s}\n", .{ c.yellow, reason, c.reset });
        } else {
            try stdout.print("{s}Draw!{s}\n", .{ c.yellow, c.reset });
        }

        try bw.flush();
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
