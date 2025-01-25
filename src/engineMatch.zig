const std = @import("std");
const enginePlay = @import("enginePlay.zig");
const Engine = enginePlay.Engine;
const EngineManager = enginePlay.EngineManager;
const Color = @import("cli.zig").Color;
const DisplayManager = @import("displayManager.zig").DisplayManager;

const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

const UciEngine = struct {
    name: []const u8,
    process: std.process.Child,
    stdout_reader: std.fs.File.Reader,
    stdin_writer: std.fs.File.Writer,
    color: []const u8,

    pub fn init(engine: Engine, allocator: std.mem.Allocator, color: []const u8) !UciEngine {
        var process = std.process.Child.init(
            &[_][]const u8{engine.path},
            allocator,
        );
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;

        try process.spawn();

        return UciEngine{
            .name = engine.name,
            .process = process,
            .stdout_reader = process.stdout.?.reader(),
            .stdin_writer = process.stdin.?.writer(),
            .color = color,
        };
    }

    pub fn deinit(self: *UciEngine) void {
        _ = self.process.kill() catch {};
    }

    pub fn sendCommand(self: *UciEngine, command: []const u8) !void {
        try self.stdin_writer.print("{s}\n", .{command});
    }

    pub fn readResponse(self: *UciEngine, buffer: []u8) !?[]const u8 {
        return try self.stdout_reader.readUntilDelimiterOrEof(buffer, '\n');
    }

    pub fn initialize(self: *UciEngine) !void {
        var buffer: [4096]u8 = undefined;

        try self.sendCommand("uci");
        while (try self.readResponse(&buffer)) |response| {
            if (std.mem.eql(u8, response, "uciok")) break;
        }

        try self.sendCommand("isready");
        while (try self.readResponse(&buffer)) |response| {
            if (std.mem.eql(u8, response, "readyok")) break;
        }

        try self.sendCommand("setoption name Hash value 128");
        try self.sendCommand("setoption name MultiPV value 1");
        try self.sendCommand("ucinewgame");
    }
};

const PositionHistory = struct {
    moves_string: []const u8,
    count: usize = 1,
};

const MatchPreset = struct {
    name: []const u8,
    description: []const u8,
    move_time_ms: u32,
    game_count: u32 = 1,
};

pub const MATCH_PRESETS = [_]MatchPreset{
    .{
        .name = "Blitz",
        .description = "Quick games with 1 second per move",
        .move_time_ms = 1000,
    },
    .{
        .name = "Rapid",
        .description = "Medium-paced games with 5 seconds per move",
        .move_time_ms = 5000,
    },
    .{
        .name = "Classical",
        .description = "Slow games with 15 seconds per move for deep analysis",
        .move_time_ms = 15000,
    },
    .{
        .name = "Tournament",
        .description = "Best of 3 rapid games",
        .move_time_ms = 5000,
        .game_count = 3,
    },
};

pub const MatchManager = struct {
    white: UciEngine,
    black: UciEngine,
    allocator: std.mem.Allocator,
    move_time_ms: u32,
    game_count: u32,
    colors: Color,
    move_count: usize = 0,
    position_history: std.StringHashMap(PositionHistory),

    pub fn init(white_engine: Engine, black_engine: Engine, allocator: std.mem.Allocator, preset: MatchPreset) !MatchManager {
        const colors = Color{};
        return MatchManager{
            .white = try UciEngine.init(white_engine, allocator, colors.blue),
            .black = try UciEngine.init(black_engine, allocator, colors.magenta),
            .allocator = allocator,
            .move_time_ms = preset.move_time_ms,
            .game_count = preset.game_count,
            .colors = colors,
            .position_history = std.StringHashMap(PositionHistory).init(allocator),
        };
    }

    pub fn deinit(self: *MatchManager) void {
        var it = self.position_history.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.moves_string);
        }
        self.position_history.deinit();
        self.white.deinit();
        self.black.deinit();
    }
    const MatchResult = enum {
        white_win,
        black_win,
        draw,
    };

    pub fn playMatch(self: *MatchManager) !MatchResult {
        var display = try DisplayManager.init(self.allocator);
        defer display.deinit();

        try display.initializeBoard();

        try self.white.initialize();
        try self.black.initialize();

        const current_position = "startpos";
        var moves = std.ArrayList([]const u8).init(self.allocator);
        defer moves.deinit();

        var current_player = &self.white;
        var is_game_over = false;
        var winner: ?*UciEngine = null;
        var draw_reason: ?[]const u8 = null;

        while (!is_game_over) {
            self.move_count += 1;
            const moves_str = try formatMovesList(self.allocator, &moves);
            defer self.allocator.free(moves_str);

            // Check for threefold repetition
            const moves_key = try self.allocator.dupe(u8, moves_str);
            defer self.allocator.free(moves_key);

            if (self.position_history.getPtr(moves_key)) |pos_history| {
                pos_history.count += 1;
                if (pos_history.count >= 3) {
                    is_game_over = true;
                    draw_reason = "threefold repetition";
                    break;
                }
            } else {
                try self.position_history.put(try self.allocator.dupe(u8, moves_key), .{ .moves_string = try self.allocator.dupe(u8, moves_str) });
            }

            const position_cmd = try std.fmt.allocPrint(self.allocator, "position {s} moves {s}", .{ current_position, moves_str });
            defer self.allocator.free(position_cmd);

            try current_player.sendCommand(position_cmd);
            try current_player.sendCommand(try std.fmt.allocPrint(self.allocator, "go movetime {d}", .{self.move_time_ms}));

            var move: ?[]const u8 = null;
            var buffer: [4096]u8 = undefined;

            while (try current_player.readResponse(&buffer)) |response| {
                if (std.mem.startsWith(u8, response, "bestmove")) {
                    move = try self.allocator.dupe(u8, response[9..13]);
                    break;
                }
            }

            if (move) |m| {
                try moves.append(m);
                try display.updateMove(m, current_player.name, self.move_count);

                if (isCheckmate(m)) {
                    winner = current_player;
                    is_game_over = true;
                } else if (isStalemate(m)) {
                    is_game_over = true;
                    draw_reason = "stalemate";
                }

                current_player = if (current_player == &self.white) &self.black else &self.white;
            } else {
                is_game_over = true;
            }

            if (moves.items.len >= 100) {
                is_game_over = true;
                draw_reason = "move limit";
            }
        }

        // Move cursor to bottom of display before showing game over message
        try stdout.print("\x1b[{d};0H\n", .{display.board_start_line + 12});

        const c = self.colors;
        try stdout.print("\n{s}Game Over!{s} ", .{ c.bold, c.reset });

        var result = MatchResult.draw;

        if (winner) |w| {
            try stdout.print("{s}{s}{s} wins by checkmate!\n", .{ w.color, w.name, c.reset });
            result = if (w == &self.white) .white_win else .black_win;
        } else if (draw_reason) |reason| {
            try stdout.print("{s}Draw by {s}!{s}\n", .{ c.yellow, reason, c.reset });
        } else {
            try stdout.print("{s}Draw!{s}\n", .{ c.yellow, c.reset });
        }

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

    return result;
}

fn isCheckmate(move: []const u8) bool {
    return std.mem.endsWith(u8, move, "#");
}

fn isStalemate(move: []const u8) bool {
    return std.mem.endsWith(u8, move, "=");
}
