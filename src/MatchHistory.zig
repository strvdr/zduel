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
const ztoml = @import("ztoml");
const Engine = @import("EnginePlay.zig").Engine;
const main = @import("main.zig");
const CLI = @import("CLI.zig");

pub const HistoryMatchResult = enum {
    win,
    loss,
    draw,
};

pub const MatchStatistics = struct {
    blackWins: u32 = 0,
    whiteWins: u32 = 0,
    blackDraws: u32 = 0,
    whiteDraws: u32 = 0,

    pub fn totalGames(self: MatchStatistics) u32 {
        return self.blackWins + self.whiteWins + self.blackDraws + self.whiteDraws;
    }

    pub fn winRate(self: MatchStatistics) f32 {
        const total = self.totalGames();
        if (total == 0) return 0;
        return @as(f32, @floatFromInt(self.blackWins + self.whiteWins)) / @as(f32, @floatFromInt(total));
    }
};

pub const EngineHistory = struct {
    engineOne: []const u8,
    engineTwo: []const u8,
    engineOneStats: MatchStatistics,
    engineTwoStats: MatchStatistics,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator, engine1: []const u8, engine2: []const u8) !*EngineHistory {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const history = try arena.allocator().create(EngineHistory);
        history.* = .{
            .engineOne = try arena.allocator().dupe(u8, engine1),
            .engineTwo = try arena.allocator().dupe(u8, engine2),
            .engineOneStats = MatchStatistics{},
            .engineTwoStats = MatchStatistics{},
            .arena = arena,
        };

        return history;
    }

    pub fn deinit(self: *EngineHistory) void {
        self.arena.deinit();
    }

    pub fn formatMatchup(self: *EngineHistory) ![]const u8 {
        return try std.fmt.allocPrint(
            self.arena.allocator(),
            "[{s} vs {s}]",
            .{ self.engineOne, self.engineTwo },
        );
    }
};

pub const HistoryManager = struct {
    allocator: std.mem.Allocator,
    histories: std.StringHashMap(*EngineHistory),
    colors: CLI.Color,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .histories = std.StringHashMap(*EngineHistory).init(allocator),
            .colors = CLI.Color{},
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.histories.valueIterator();
        while (it.next()) |history| {
            history.*.deinit();
        }
        self.histories.deinit();
    }

    pub fn loadFromFile(self: *Self) !void {
        const file = std.fs.cwd().openFile("history.toml", .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Create empty file if it doesn't exist
                var empty_file = try std.fs.cwd().createFile("history.toml", .{});
                empty_file.close();
                return;
            }
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        var parser_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer parser_arena.deinit();

        var parser = ztoml.Parser.init(&parser_arena, content);
        const result = parser.parse() catch |err| {
            std.debug.print("Warning: Could not parse history file: {s}\n", .{@errorName(err)});
            return;
        };

        // Iterate through the top-level entries (matchups)
        var it = result.iterator();
        while (it.next()) |entry| {
            const matchup = entry.key_ptr.*;
            // Skip the special section headers
            if (std.mem.eql(u8, matchup, "Engine One") or
                std.mem.eql(u8, matchup, "Engine Two"))
            {
                continue;
            }

            // Use a temporary arena for parsing matchup
            var temp_arena = std.heap.ArenaAllocator.init(self.allocator);
            defer temp_arena.deinit();

            const engineNames = self.parseMatchup(matchup, &temp_arena) catch |err| {
                std.debug.print("Warning: Invalid matchup format '{s}': {s}\n", .{ matchup, @errorName(err) });
                continue;
            };

            // Create history with main allocator
            var history = try EngineHistory.init(self.allocator, engineNames[0], engineNames[1]);
            errdefer history.deinit();

            // Get the nested tables for this matchup
            if (entry.value_ptr.*.data == .Table) {
                const matchupTable = entry.value_ptr.*.data.Table;

                // Parse Engine One stats
                if (matchupTable.get("Engine One")) |engineOneValue| {
                    if (engineOneValue.data == .Array) {
                        const array = engineOneValue.data.Array;
                        if (array.len > 0) {
                            history.engineOneStats = try self.parseStatistics(array[0]);
                        }
                    }
                }

                // Parse Engine Two stats
                if (matchupTable.get("Engine Two")) |engineTwoValue| {
                    if (engineTwoValue.data == .Array) {
                        const array = engineTwoValue.data.Array;
                        if (array.len > 0) {
                            history.engineTwoStats = try self.parseStatistics(array[0]);
                        }
                    }
                }
            }

            // Format matchup key and store in hashmap
            const formatted_key = try history.formatMatchup();
            try self.histories.put(formatted_key, history);
        }
    }

    fn parseStatistics(self: *Self, value: ztoml.TomlValue) !MatchStatistics {
        _ = self;
        var stats = MatchStatistics{};

        if (value.data == .Table) {
            const table = value.data.Table;

            if (table.get("blackWins")) |v| {
                if (v.data == .Integer) {
                    stats.blackWins = @intCast(v.data.Integer);
                }
            }
            if (table.get("whiteWins")) |v| {
                if (v.data == .Integer) {
                    stats.whiteWins = @intCast(v.data.Integer);
                }
            }
            if (table.get("blackDraws")) |v| {
                if (v.data == .Integer) {
                    stats.blackDraws = @intCast(v.data.Integer);
                }
            }
            if (table.get("whiteDraws")) |v| {
                if (v.data == .Integer) {
                    stats.whiteDraws = @intCast(v.data.Integer);
                }
            }
        }

        return stats;
    }

    fn parseMatchup(self: *Self, matchup: []const u8, arena: *std.heap.ArenaAllocator) !struct { []const u8, []const u8 } {
        _ = self;
        // Remove the square brackets if they exist
        const stripped = if (matchup[0] == '[' and matchup[matchup.len - 1] == ']')
            matchup[1 .. matchup.len - 1]
        else
            matchup;

        // Split on " vs " and handle potential errors
        var it = std.mem.splitSequence(u8, stripped, " vs ");

        // Get first engine name
        const engine1 = it.next() orelse return error.InvalidMatchup;
        if (engine1.len == 0) return error.InvalidMatchup;

        // Get second engine name
        const engine2 = it.next() orelse return error.InvalidMatchup;
        if (engine2.len == 0) return error.InvalidMatchup;

        // Check if there's any remaining content (which would be invalid)
        if (it.next() != null) return error.InvalidMatchup;

        // Use the provided arena for allocations
        const trimmed1 = try arena.allocator().dupe(u8, std.mem.trim(u8, engine1, &std.ascii.whitespace));
        const trimmed2 = try arena.allocator().dupe(u8, std.mem.trim(u8, engine2, &std.ascii.whitespace));

        return .{ trimmed1, trimmed2 };
    }

    pub fn saveToFile(self: *Self) !void {
        var file = try std.fs.cwd().createFile("history.toml", .{});
        defer file.close();

        var writer = file.writer();

        var it = self.histories.iterator();
        while (it.next()) |entry| {
            const history = entry.value_ptr.*;

            // Write matchup header
            try writer.print("{s}\n", .{entry.key_ptr.*});

            // Write Engine One statistics
            try writer.writeAll("[[Engine One]]\n");
            try writer.print("blackWins = {d}\n", .{history.engineOneStats.blackWins});
            try writer.print("whiteWins = {d}\n", .{history.engineOneStats.whiteWins});
            try writer.print("blackDraws = {d}\n", .{history.engineOneStats.blackDraws});
            try writer.print("whiteDraws = {d}\n\n", .{history.engineOneStats.whiteDraws});

            // Write Engine Two statistics
            try writer.writeAll("[[Engine Two]]\n");
            try writer.print("blackWins = {d}\n", .{history.engineTwoStats.blackWins});
            try writer.print("whiteWins = {d}\n", .{history.engineTwoStats.whiteWins});
            try writer.print("blackDraws = {d}\n", .{history.engineTwoStats.blackDraws});
            try writer.print("whiteDraws = {d}\n\n", .{history.engineTwoStats.whiteDraws});
        }
    }

    pub fn updateMatchResult(
        self: *Self,
        engine1: []const u8,
        engine2: []const u8,
        engine1IsWhite: bool,
        result: HistoryMatchResult, // Use the enum type here
    ) !void {
        const key = try std.fmt.allocPrint(
            self.allocator,
            "[{s} vs {s}]",
            .{ engine1, engine2 },
        );
        defer self.allocator.free(key);

        var history = if (self.histories.get(key)) |h| h else blk: {
            const h = try EngineHistory.init(self.allocator, engine1, engine2);
            try self.histories.put(try h.formatMatchup(), h);
            break :blk h;
        };

        // Update statistics based on result and colors
        switch (result) {
            .win => if (engine1IsWhite) {
                history.engineOneStats.whiteWins += 1;
            } else {
                history.engineOneStats.blackWins += 1;
            },
            .loss => if (engine1IsWhite) {
                history.engineTwoStats.blackWins += 1;
            } else {
                history.engineTwoStats.whiteWins += 1;
            },
            .draw => if (engine1IsWhite) {
                history.engineOneStats.whiteDraws += 1;
                history.engineTwoStats.blackDraws += 1;
            } else {
                history.engineOneStats.blackDraws += 1;
                history.engineTwoStats.whiteDraws += 1;
            },
        }

        try self.saveToFile();
    }

    pub fn displayStatistics(self: *Self) !void {
        const c = self.colors;
        if (self.histories.count() == 0) {
            try main.stdout.print("\n{s}No match history available.{s}\n", .{ c.yellow, c.reset });
            return;
        }

        try main.stdout.print("\n{s}Match History{s}\n", .{ c.bold, c.reset });
        try main.stdout.print("═════════════\n\n", .{});

        var it = self.histories.iterator();
        while (it.next()) |entry| {
            const history = entry.value_ptr.*;

            try main.stdout.print("{s}{s}{s}\n", .{ c.green, entry.key_ptr.*, c.reset });

            // Engine One stats
            try main.stdout.print("  {s}{s}{s}:\n", .{ c.blue, history.engineOne, c.reset });
            try main.stdout.print("    Wins as White: {d}\n", .{history.engineOneStats.whiteWins});
            try main.stdout.print("    Wins as Black: {d}\n", .{history.engineOneStats.blackWins});
            try main.stdout.print("    Draws as White: {d}\n", .{history.engineOneStats.whiteDraws});
            try main.stdout.print("    Draws as Black: {d}\n", .{history.engineOneStats.blackDraws});
            try main.stdout.print("    Win Rate: {d:.1}%\n", .{history.engineOneStats.winRate() * 100});

            // Engine Two stats
            try main.stdout.print("\n  {s}{s}{s}:\n", .{ c.red, history.engineTwo, c.reset });
            try main.stdout.print("    Wins as White: {d}\n", .{history.engineTwoStats.whiteWins});
            try main.stdout.print("    Wins as Black: {d}\n", .{history.engineTwoStats.blackWins});
            try main.stdout.print("    Draws as White: {d}\n", .{history.engineTwoStats.whiteDraws});
            try main.stdout.print("    Draws as Black: {d}\n", .{history.engineTwoStats.blackDraws});
            try main.stdout.print("    Win Rate: {d:.1}%\n", .{history.engineTwoStats.winRate() * 100});
            try main.stdout.print("\n", .{});
        }

        try main.bw.flush();
    }
};
