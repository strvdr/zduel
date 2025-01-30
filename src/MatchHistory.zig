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
        errdefer allocator.destroy(history);

        // Always store engines in alphabetical order for consistency
        if (std.mem.lessThan(u8, engine1, engine2)) {
            history.* = .{
                .engineOne = try arena.allocator().dupe(u8, engine1),
                .engineTwo = try arena.allocator().dupe(u8, engine2),
                .engineOneStats = MatchStatistics{},
                .engineTwoStats = MatchStatistics{},
                .arena = arena,
            };
        } else {
            history.* = .{
                .engineOne = try arena.allocator().dupe(u8, engine2),
                .engineTwo = try arena.allocator().dupe(u8, engine1),
                .engineOneStats = MatchStatistics{},
                .engineTwoStats = MatchStatistics{},
                .arena = arena,
            };
        }
        return history;
    }

    pub fn deinit(self: *EngineHistory) void {
        self.arena.deinit();
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

    pub fn clearHistories(self: *Self) void {
        var it = self.histories.valueIterator();
        while (it.next()) |history| {
            history.*.deinit();
        }
        self.histories.clearRetainingCapacity();
    }

    fn parseStatistics(self: *Self, value: ztoml.TomlValue) !MatchStatistics {
        _ = self;
        var stats = MatchStatistics{};

        if (value.data == .Table) {
            const table = value.data.Table;

            // For each field, explicitly handle the integer conversion
            if (table.get("blackWins")) |v| {
                if (v.data == .Integer) {
                    stats.blackWins = @intCast(@as(i64, @intCast(v.data.Integer)));
                }
            }
            if (table.get("whiteWins")) |v| {
                if (v.data == .Integer) {
                    stats.whiteWins = @intCast(@as(i64, @intCast(v.data.Integer)));
                }
            }
            if (table.get("blackDraws")) |v| {
                if (v.data == .Integer) {
                    stats.blackDraws = @intCast(@as(i64, @intCast(v.data.Integer)));
                }
            }
            if (table.get("whiteDraws")) |v| {
                if (v.data == .Integer) {
                    stats.whiteDraws = @intCast(@as(i64, @intCast(v.data.Integer)));
                }
            }
        }

        return stats;
    }

    pub fn saveToFile(self: *Self) !void {
        // Create or truncate the history file
        var file = try std.fs.cwd().createFile("history.toml", .{});
        defer file.close();

        var writer = file.writer();

        // Iterate through all matchups
        var it = self.histories.iterator();
        while (it.next()) |entry| {
            const history = entry.value_ptr.*;

            // Write matchup section header
            try writer.print("\n[{s} vs {s}]\n", .{
                history.engineOne,
                history.engineTwo,
            });

            // Write Engine One statistics
            try writer.writeAll("\n[[Engine One]]\n");
            try writer.print("blackWins = {d}\n", .{history.engineOneStats.blackWins});
            try writer.print("whiteWins = {d}\n", .{history.engineOneStats.whiteWins});
            try writer.print("blackDraws = {d}\n", .{history.engineOneStats.blackDraws});
            try writer.print("whiteDraws = {d}\n", .{history.engineOneStats.whiteDraws});

            // Write Engine Two statistics
            try writer.writeAll("\n[[Engine Two]]\n");
            try writer.print("blackWins = {d}\n", .{history.engineTwoStats.blackWins});
            try writer.print("whiteWins = {d}\n", .{history.engineTwoStats.whiteWins});
            try writer.print("blackDraws = {d}\n", .{history.engineTwoStats.blackDraws});
            try writer.print("whiteDraws = {d}\n", .{history.engineTwoStats.whiteDraws});
        }
    }

    // In MatchHistory.zig, replace the loadFromFile function with:

    pub fn loadFromFile(self: *Self) !void {
        // Clear existing histories before loading
        self.clearHistories();

        const file = std.fs.cwd().openFile("history.toml", .{}) catch |err| {
            if (err == error.FileNotFound) {
                var empty_file = try std.fs.cwd().createFile("history.toml", .{});
                empty_file.close();
                return;
            }
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size == 0) return;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        const content = try arena.allocator().alloc(u8, file_size);
        _ = try file.readAll(content);

        var parser = ztoml.Parser.init(&arena, content);
        const result = try parser.parse();

        // Iterate through top-level entries (matchups)
        var it = result.iterator();
        while (it.next()) |entry| {
            const matchup_key = entry.key_ptr.*;

            // Skip if not a matchup entry (should contain "vs")
            if (!std.mem.containsAtLeast(u8, matchup_key, 1, "vs")) continue;

            // Parse engine names from the matchup key
            var parts = std.mem.splitSequence(u8, matchup_key, " vs ");
            const engine1_name = parts.next() orelse continue;
            const engine2_name = parts.next() orelse continue;

            // Create new history entry
            var history = try EngineHistory.init(self.allocator, engine1_name, engine2_name);
            errdefer history.deinit();

            // Access the matchup table
            const matchup_data = entry.value_ptr.*;
            if (matchup_data.data != .Table) continue;
            const matchup_table = matchup_data.data.Table;

            // Parse Engine One stats
            if (matchup_table.get("Engine One")) |engine_one_arr| {
                if (engine_one_arr.data == .Array and engine_one_arr.data.Array.len > 0) {
                    const stats = engine_one_arr.data.Array[0];
                    if (stats.data == .Table) {
                        const stats_table = stats.data.Table;
                        if (stats_table.get("blackWins")) |v| {
                            if (v.data == .Integer) history.engineOneStats.blackWins = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("whiteWins")) |v| {
                            if (v.data == .Integer) history.engineOneStats.whiteWins = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("blackDraws")) |v| {
                            if (v.data == .Integer) history.engineOneStats.blackDraws = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("whiteDraws")) |v| {
                            if (v.data == .Integer) history.engineOneStats.whiteDraws = @intCast(v.data.Integer);
                        }
                    }
                }
            }

            // Parse Engine Two stats
            if (matchup_table.get("Engine Two")) |engine_two_arr| {
                if (engine_two_arr.data == .Array and engine_two_arr.data.Array.len > 0) {
                    const stats = engine_two_arr.data.Array[0];
                    if (stats.data == .Table) {
                        const stats_table = stats.data.Table;
                        if (stats_table.get("blackWins")) |v| {
                            if (v.data == .Integer) history.engineTwoStats.blackWins = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("whiteWins")) |v| {
                            if (v.data == .Integer) history.engineTwoStats.whiteWins = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("blackDraws")) |v| {
                            if (v.data == .Integer) history.engineTwoStats.blackDraws = @intCast(v.data.Integer);
                        }
                        if (stats_table.get("whiteDraws")) |v| {
                            if (v.data == .Integer) history.engineTwoStats.whiteDraws = @intCast(v.data.Integer);
                        }
                    }
                }
            }

            // Store the history entry
            const lookup_key = generateLookupKey(engine1_name, engine2_name);
            try self.histories.put(lookup_key, history);
        }
    }

    pub fn updateMatchResult(
        self: *Self,
        engine1: []const u8,
        engine2: []const u8,
        engine1IsWhite: bool,
        result: HistoryMatchResult,
    ) !void {
        // Get the engines in alphabetical order for consistency
        const first_engine = if (std.mem.lessThan(u8, engine1, engine2)) engine1 else engine2;
        const second_engine = if (std.mem.lessThan(u8, engine1, engine2)) engine2 else engine1;

        // Generate lookup key
        const lookup_key = generateLookupKey(first_engine, second_engine);

        // Try to find existing history
        var history: *EngineHistory = if (self.histories.get(lookup_key)) |existing| existing else blk: {
            const new_history = try EngineHistory.init(self.allocator, first_engine, second_engine);
            try self.histories.put(lookup_key, new_history);
            break :blk new_history;
        };

        // Update statistics based on match result
        const engine1IsEngineOne = std.mem.eql(u8, engine1, history.engineOne);
        switch (result) {
            .win => {
                if (engine1IsEngineOne) {
                    if (engine1IsWhite) {
                        history.engineOneStats.whiteWins += 1;
                    } else {
                        history.engineOneStats.blackWins += 1;
                    }
                } else {
                    if (engine1IsWhite) {
                        history.engineTwoStats.whiteWins += 1;
                    } else {
                        history.engineTwoStats.blackWins += 1;
                    }
                }
            },
            .loss => {
                if (engine1IsEngineOne) {
                    if (engine1IsWhite) {
                        history.engineTwoStats.blackWins += 1;
                    } else {
                        history.engineTwoStats.whiteWins += 1;
                    }
                } else {
                    if (engine1IsWhite) {
                        history.engineOneStats.blackWins += 1;
                    } else {
                        history.engineOneStats.whiteWins += 1;
                    }
                }
            },
            .draw => {
                if (engine1IsEngineOne) {
                    if (engine1IsWhite) {
                        history.engineOneStats.whiteDraws += 1;
                        history.engineTwoStats.blackDraws += 1;
                    } else {
                        history.engineOneStats.blackDraws += 1;
                        history.engineTwoStats.whiteDraws += 1;
                    }
                } else {
                    if (engine1IsWhite) {
                        history.engineTwoStats.whiteDraws += 1;
                        history.engineOneStats.blackDraws += 1;
                    } else {
                        history.engineTwoStats.blackDraws += 1;
                        history.engineOneStats.whiteDraws += 1;
                    }
                }
            },
        }

        // Save updated history to file
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

            // Print matchup header
            try main.stdout.print("{s}{s} vs {s}{s}\n", .{
                c.green,
                history.engineOne,
                history.engineTwo,
                c.reset,
            });

            // Print Engine One stats
            try main.stdout.print("  {s}{s}{s}:\n", .{ c.blue, history.engineOne, c.reset });
            try main.stdout.print("    Total Games: {d}\n", .{history.engineOneStats.totalGames()});
            try main.stdout.print("    As White: {d} wins, {d} draws\n", .{
                history.engineOneStats.whiteWins,
                history.engineOneStats.whiteDraws,
            });
            try main.stdout.print("    As Black: {d} wins, {d} draws\n", .{
                history.engineOneStats.blackWins,
                history.engineOneStats.blackDraws,
            });
            const engineOneWinRate = if (history.engineOneStats.totalGames() > 0)
                @as(f32, @floatFromInt(history.engineOneStats.whiteWins + history.engineOneStats.blackWins)) /
                    @as(f32, @floatFromInt(history.engineOneStats.totalGames())) * 100.0
            else
                0.0;
            try main.stdout.print("    Win Rate: {d:.1}%\n\n", .{engineOneWinRate});

            // Print Engine Two stats
            try main.stdout.print("  {s}{s}{s}:\n", .{ c.red, history.engineTwo, c.reset });
            try main.stdout.print("    Total Games: {d}\n", .{history.engineTwoStats.totalGames()});
            try main.stdout.print("    As White: {d} wins, {d} draws\n", .{
                history.engineTwoStats.whiteWins,
                history.engineTwoStats.whiteDraws,
            });
            try main.stdout.print("    As Black: {d} wins, {d} draws\n", .{
                history.engineTwoStats.blackWins,
                history.engineTwoStats.blackDraws,
            });
            const engineTwoWinRate = if (history.engineTwoStats.totalGames() > 0)
                @as(f32, @floatFromInt(history.engineTwoStats.whiteWins + history.engineTwoStats.blackWins)) /
                    @as(f32, @floatFromInt(history.engineTwoStats.totalGames())) * 100.0
            else
                0.0;
            try main.stdout.print("    Win Rate: {d:.1}%\n\n", .{engineTwoWinRate});
        }

        try main.bw.flush();
    }
};

fn formatMatchupKey(allocator: std.mem.Allocator, engine1: []const u8, engine2: []const u8) ![]const u8 {
    // Always use alphabetical order for the TOML header
    if (std.mem.lessThan(u8, engine1, engine2)) {
        return try std.fmt.allocPrint(allocator, "[{s} vs {s}]", .{ engine1, engine2 });
    } else {
        return try std.fmt.allocPrint(allocator, "[{s} vs {s}]", .{ engine2, engine1 });
    }
}

fn generateLookupKey(engine1: []const u8, engine2: []const u8) []const u8 {
    if (std.mem.lessThan(u8, engine1, engine2)) {
        return engine1;
    } else {
        return engine2;
    }
}

fn parseEngineStats(table: std.StringHashMap(ztoml.TomlValue), engine_key: []const u8) !MatchStatistics {
    var stats = MatchStatistics{};

    if (table.get(engine_key)) |engineArr| {
        if (engineArr.data == .Array and engineArr.data.Array.len > 0) {
            const engineStats = engineArr.data.Array[0];
            if (engineStats.data == .Table) {
                const statsTable = engineStats.data.Table;

                if (statsTable.get("blackWins")) |val| {
                    if (val.data == .Integer) stats.blackWins = @intCast(val.data.Integer);
                }
                if (statsTable.get("whiteWins")) |val| {
                    if (val.data == .Integer) stats.whiteWins = @intCast(val.data.Integer);
                }
                if (statsTable.get("blackDraws")) |val| {
                    if (val.data == .Integer) stats.blackDraws = @intCast(val.data.Integer);
                }
                if (statsTable.get("whiteDraws")) |val| {
                    if (val.data == .Integer) stats.whiteDraws = @intCast(val.data.Integer);
                }
            }
        }
    }

    return stats;
}

fn parseStatsFromTable(table: std.StringHashMap(ztoml.TomlValue)) !MatchStatistics {
    var stats = MatchStatistics{};

    if (table.get("blackWins")) |val| {
        if (val.data == .Integer) stats.blackWins = @intCast(val.data.Integer);
    }
    if (table.get("whiteWins")) |val| {
        if (val.data == .Integer) stats.whiteWins = @intCast(val.data.Integer);
    }
    if (table.get("blackDraws")) |val| {
        if (val.data == .Integer) stats.blackDraws = @intCast(val.data.Integer);
    }
    if (table.get("whiteDraws")) |val| {
        if (val.data == .Integer) stats.whiteDraws = @intCast(val.data.Integer);
    }

    return stats;
}
