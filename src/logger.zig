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

//! Match logging and analysis recording.
//!
//! Features:
//! - Per-match log files
//! - Engine communication logging
//! - Game result recording
//!
//! ## Usage
//! ```zig
//! var logger = try Logger.init(allocator);
//! try logger.start(whiteName, blackName);
//! try logger.log(engineName, isInput, data);
//! ```

const std = @import("std");
const cli = @import("cli.zig");
const Color = cli.Color;

pub const Logger = struct {
    allocator: std.mem.Allocator,
    file: ?std.fs.File,
    enabled: bool,
    colors: Color,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) !Logger {
        return Logger{
            .allocator = allocator,
            .file = null,
            .enabled = false,
            .colors = Color{},
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Logger) void {
        if (self.file) |file| {
            file.close();
        }
        self.arena.deinit();
    }

    pub fn log(self: *Logger, engineName: []const u8, isInput: bool, data: []const u8) !void {
        if (!self.enabled) return;

        var buffer = try std.ArrayList(u8).initCapacity(self.arena.allocator(), 1024);
        const timestamp = try getTimestamp(self.arena.allocator());
        const direction = if (isInput) ">>>" else "<<<";

        try buffer.writer().print("[{s}] {s} {s}: {s}\n", .{
            timestamp,
            direction,
            engineName,
            data,
        });

        if (self.file) |file| {
            try file.writeAll(buffer.items);
        }
    }

    pub fn start(self: *Logger, whiteName: []const u8, blackName: []const u8) !void {
        const timestamp = try getTimestamp(self.arena.allocator());
        const safe_name = try sanitizeFilename(self.arena.allocator(), whiteName);
        const safe_black = try sanitizeFilename(self.arena.allocator(), blackName);

        try std.fs.cwd().makePath("logs");

        const path = try std.fmt.allocPrint(
            self.arena.allocator(),
            "logs/zduel_{s}_vs_{s}_{s}.log",
            .{ safe_name, safe_black, timestamp },
        );

        self.file = try std.fs.cwd().createFile(path, .{});
        self.enabled = true;

        try self.writeHeader(whiteName, blackName);
    }

    fn writeHeader(self: *Logger, whiteName: []const u8, blackName: []const u8) !void {
        var buffer = try std.ArrayList(u8).initCapacity(self.arena.allocator(), 1024);
        const timestamp = try getTimestamp(self.arena.allocator());

        try buffer.writer().print(
            \\=== zduel Engine Match Log ===
            \\Date: {s}
            \\White: {s}
            \\Black: {s}
            \\
            \\
        , .{
            timestamp,
            whiteName,
            blackName,
        });

        if (self.file) |file| {
            try file.writeAll(buffer.items);
        }
    }
};

fn sanitizeFilename(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, input.len);
    for (input) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => try buffer.append(c),
            else => try buffer.append('_'),
        }
    }
    return buffer.items;
}

fn getTimestamp(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.timestamp();
    const ts = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const epochDay = ts.getEpochDay();
    const yearDay = epochDay.calculateYearDay();
    const monthDay = yearDay.calculateMonthDay();
    const daySeconds = ts.getDaySeconds();

    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}{d:0>2}{d:0>2}_{d:0>2}{d:0>2}{d:0>2}",
        .{
            yearDay.year,
            @intFromEnum(monthDay.month) + 1,
            monthDay.day_index + 1,
            daySeconds.getHoursIntoDay(),
            daySeconds.getMinutesIntoHour(),
            daySeconds.getSecondsIntoMinute(),
        },
    );
}
