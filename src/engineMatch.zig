const std = @import("std");
const enginePlay = @import("enginePlay.zig");
const Engine = enginePlay.Engine;
const EngineManager = enginePlay.EngineManager;
const Color = enginePlay.Color;

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

pub const MatchManager = struct {
    white: UciEngine,
    black: UciEngine,
    allocator: std.mem.Allocator,
    move_time_ms: u32 = 1000,
    colors: Color,
    move_count: usize = 0,

    pub fn init(white_engine: Engine, black_engine: Engine, allocator: std.mem.Allocator) !MatchManager {
        const colors = Color{};
        return MatchManager{
            .white = try UciEngine.init(white_engine, allocator, colors.blue),
            .black = try UciEngine.init(black_engine, allocator, colors.magenta),
            .allocator = allocator,
            .colors = colors,
        };
    }

    pub fn deinit(self: *MatchManager) void {
        self.white.deinit();
        self.black.deinit();
    }

    pub fn playMatch(self: *MatchManager) !void {
        const stdout = std.io.getStdOut().writer();
        var buffer: [4096]u8 = undefined;

        try stdout.print("\n{s}Starting match:{s} {s}{s}{s} vs {s}{s}{s}\n\n", .{
            self.colors.bold,
            self.colors.reset,
            self.white.color,
            self.white.name,
            self.colors.reset,
            self.black.color,
            self.black.name,
            self.colors.reset,
        });

        try self.white.initialize();
        try self.black.initialize();

        const current_position = "startpos";
        var moves = std.ArrayList([]const u8).init(self.allocator);
        defer moves.deinit();

        var current_player = &self.white;
        var is_game_over = false;
        var winner: ?*UciEngine = null;

        while (!is_game_over) {
            self.move_count += 1;
            const moves_str = try formatMovesList(self.allocator, &moves);
            defer self.allocator.free(moves_str);

            const position_cmd = try std.fmt.allocPrint(
                self.allocator,
                "position {s} moves {s}",
                .{
                    current_position,
                    moves_str,
                },
            );
            defer self.allocator.free(position_cmd);

            try current_player.sendCommand(position_cmd);

            try current_player.sendCommand(try std.fmt.allocPrint(
                self.allocator,
                "go movetime {d}",
                .{self.move_time_ms},
            ));

            var move: ?[]const u8 = null;
            while (try current_player.readResponse(&buffer)) |response| {
                if (std.mem.startsWith(u8, response, "bestmove")) {
                    move = try self.allocator.dupe(u8, response[9..13]);
                    break;
                }
            }

            if (move) |m| {
                try moves.append(m);
                try stdout.print("Move {d}: {s}{s}{s} plays {s}{s}{s}\n", .{
                    self.move_count,
                    current_player.color,
                    current_player.name,
                    self.colors.reset,
                    self.colors.green,
                    m,
                    self.colors.reset,
                });

                if (isCheckmate(m)) {
                    winner = current_player;
                    is_game_over = true;
                } else if (isStalemate(m)) {
                    is_game_over = true;
                }

                current_player = if (current_player == &self.white) &self.black else &self.white;
            } else {
                is_game_over = true;
            }

            if (moves.items.len >= 100) {
                is_game_over = true;
                try stdout.print("\n{s}Game drawn by move limit{s}\n", .{ self.colors.yellow, self.colors.reset });
            }
        }

        try stdout.print("\n{s}Game Over!{s} ", .{ self.colors.bold, self.colors.reset });
        if (winner) |w| {
            try stdout.print("{s}{s}{s} wins!\n", .{ w.color, w.name, self.colors.reset });
        } else {
            try stdout.print("{s}Draw!{s}\n", .{ self.colors.yellow, self.colors.reset });
        }
    }
};

fn formatMovesList(allocator: std.mem.Allocator, moves: *const std.ArrayList([]const u8)) ![]const u8 {
    if (moves.items.len == 0) return "";

    // Calculate total length needed
    var total_length: usize = 0;
    for (moves.items) |move| {
        total_length += move.len + 1; // +1 for space
    }

    // Allocate exact size needed
    var result = try allocator.alloc(u8, total_length);
    var pos: usize = 0;

    // Copy moves with spaces
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
