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

//! Chess engine management and execution.
//!
//! Provides:
//! - Engine discovery
//! - Process management
//! - UCI protocol handling
//!
//! ## Usage
//! ```zig
//! var manager = try EngineManager.init(allocator);
//! try manager.scanEngines();
//! try manager.listEngines();
//! ```
const std = @import("std");
const main = @import("main.zig");
const builtin = @import("builtin");
const CLI = @import("CLI.zig");

pub const Engine = struct {
    name: []const u8,
    path: []const u8,
};

pub const EngineManager = struct {
    allocator: std.mem.Allocator,
    engines: std.ArrayList(Engine),
    colors: CLI.Color,

    pub fn init(allocator: std.mem.Allocator) !EngineManager {
        return EngineManager{
            .allocator = allocator,
            .engines = std.ArrayList(Engine).init(allocator),
            .colors = main.colors,
        };
    }

    pub fn deinit(self: *EngineManager) void {
        for (self.engines.items) |engine| {
            self.allocator.free(engine.name);
            self.allocator.free(engine.path);
        }
        self.engines.deinit();
    }

    // List all available engines
    pub fn listEngines(self: *EngineManager) !void {
        const c = main.colors;
        if (self.engines.items.len == 0) {
            try main.stdout.print("\n{s}No engines found. Use 'engines add' to add chess engines.{s}\n", .{ c.yellow, c.reset });
            return;
        }

        try main.stdout.print("\n{s}{s}Available Chess Engines{s}\n", .{ c.bold, c.blue, c.reset });
        try main.stdout.print("{s}════════════════════════{s}\n\n", .{ c.dim, c.reset });

        for (self.engines.items, 0..) |engine, i| {
            try main.stdout.print("{s}[{d}]{s} {s}{s}{s}\n", .{ c.cyan, i + 1, c.reset, c.bold, engine.name, c.reset });
            try main.stdout.print("   {s}Path:{s} {s}{s}{s}\n", .{ c.dim, c.reset, c.green, engine.path, c.reset });
        }
        try main.stdout.print("\n", .{});
    }

    // Scan directory and load available engines
    pub fn scanEngines(self: *EngineManager) !void {
        const c = main.colors;
        var cwd = std.fs.cwd();

        try main.stdout.print("\n{s}Scanning for chess engines...{s}\n", .{ c.blue, c.reset });

        var dir = try cwd.openDir(
            "engines",
            .{
                .access_sub_paths = true,
                .iterate = true,
            },
        );
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        var found_count: usize = 0;
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            const current_dir = try std.process.getCwdAlloc(self.allocator);
            defer self.allocator.free(current_dir);

            const engine_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, "engines", entry.basename });

            const engine = Engine{
                .name = try self.allocator.dupe(u8, entry.basename),
                .path = engine_path,
            };

            try self.engines.append(engine);
            found_count += 1;
            try main.stdout.print("{s}Found:{s} {s}{s}{s}\n", .{ c.green, c.reset, c.bold, entry.basename, c.reset });
        }

        if (found_count == 0) {
            try main.stdout.print("{s}No engines found in the engines directory.{s}\n", .{ c.yellow, c.reset });
        } else {
            try main.stdout.print("\n{s}Found {d} engine{s}{s}\n", .{ c.green, found_count, if (found_count == 1) "" else "s", c.reset });
        }
    }

    // Run a specific engine by index
    pub fn runEngine(self: *EngineManager, index: usize) !void {
        const c = main.colors;
        if (index >= self.engines.items.len) {
            return error.InvalidEngineIndex;
        }

        const engine = self.engines.items[index];
        try main.stdout.print("\n{s}Launching engine:{s} {s}{s}{s}\n", .{ c.blue, c.reset, c.bold, engine.name, c.reset });

        var child = std.process.Child.init(
            &[_][]const u8{engine.path},
            self.allocator,
        );

        defer {
            _ = child.kill() catch {};
            _ = child.wait() catch {};
        }

        try main.stdout.print("{s}Starting process...{s}\n", .{ c.dim, c.reset });
        try child.spawn();

        const term = try child.wait();
        if (term.Exited == 0) {
            try main.stdout.print("\r{s}✓ Engine completed successfully{s}   \n", .{ c.green, c.reset });
        } else {
            try main.stdout.print("\r{s}✗ Engine exited with status: {d}{s}   \n", .{ c.red, term.Exited, c.reset });
        }
    }
};

// Function to get user input as number
fn getUserInput(reader: anytype, buffer: []u8) !usize {
    if (try reader.readUntilDelimiterOrEof(buffer, '\n')) |userInput| {
        const trimmed = std.mem.trim(u8, userInput, &std.ascii.whitespace);
        return try std.fmt.parseInt(usize, trimmed, 10);
    } else {
        return error.InvalidInput;
    }
}

// Main engine management function
pub fn handleEngines(allocator: std.mem.Allocator) !void {
    var manager = try EngineManager.init(allocator);
    defer manager.deinit();
    const c = main.colors;

    try manager.scanEngines();

    const stdin = std.io.getStdIn().reader();
    var buffer: [100]u8 = undefined;

    while (true) {
        try manager.listEngines();
        if (manager.engines.items.len == 0) break;

        try main.stdout.print("{s}Select an engine (1-{d}) or 0 to exit:{s} ", .{ c.blue, manager.engines.items.len, c.reset });

        const choice = getUserInput(stdin, &buffer) catch |err| {
            try main.stdout.print("\n{s}Invalid input: {any}{s}\n", .{ c.red, err, c.reset });
            continue;
        };

        if (choice == 0) break;

        if (choice > manager.engines.items.len) {
            try main.stdout.print("\n{s}Please select a number between 1 and {d}{s}\n", .{ c.yellow, manager.engines.items.len, c.reset });
            continue;
        }

        manager.runEngine(choice - 1) catch |err| {
            try main.stdout.print("\n{s}Error running engine: {any}{s}\n", .{ c.red, err, c.reset });
        };
    }
}
