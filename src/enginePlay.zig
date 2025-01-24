const std = @import("std");
const builtin = @import("builtin");

// ANSI color codes
const Color = struct {
    yellow: []const u8 = "\x1b[33m",
    green: []const u8 = "\x1b[32m",
    red: []const u8 = "\x1b[31m",
    blue: []const u8 = "\x1b[34m",
    magenta: []const u8 = "\x1b[35m",
    cyan: []const u8 = "\x1b[36m",
    bold: []const u8 = "\x1b[1m",
    reset: []const u8 = "\x1b[0m",
    dim: []const u8 = "\x1b[2m",
};

pub const Engine = struct {
    name: []const u8,
    path: []const u8,
};

pub const EngineManager = struct {
    allocator: std.mem.Allocator,
    engines: std.ArrayList(Engine),
    colors: Color,

    pub fn init(allocator: std.mem.Allocator) !EngineManager {
        return EngineManager{
            .allocator = allocator,
            .engines = std.ArrayList(Engine).init(allocator),
            .colors = Color{},
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
        const c = self.colors;
        if (self.engines.items.len == 0) {
            try std.io.getStdOut().writer().print("\n{s}No engines found. Use 'engines add' to add chess engines.{s}\n", .{ c.yellow, c.reset });
            return;
        }

        try std.io.getStdOut().writer().print("\n{s}{s}Available Chess Engines{s}\n", .{ c.bold, c.blue, c.reset });
        try std.io.getStdOut().writer().print("{s}════════════════════════{s}\n\n", .{ c.dim, c.reset });

        for (self.engines.items, 0..) |engine, i| {
            try std.io.getStdOut().writer().print("{s}[{d}]{s} {s}{s}{s}\n", .{ c.cyan, i + 1, c.reset, c.bold, engine.name, c.reset });
            try std.io.getStdOut().writer().print("   {s}Path:{s} {s}{s}{s}\n", .{ c.dim, c.reset, c.green, engine.path, c.reset });
        }
        try std.io.getStdOut().writer().print("\n", .{});
    }

    // Scan directory and load available engines
    pub fn scanEngines(self: *EngineManager) !void {
        const c = self.colors;
        var cwd = std.fs.cwd();

        try std.io.getStdOut().writer().print("\n{s}Scanning for chess engines...{s}\n", .{ c.blue, c.reset });

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
            try std.io.getStdOut().writer().print("  {s}Found:{s} {s}{s}{s}\n", .{ c.green, c.reset, c.bold, entry.basename, c.reset });
        }

        if (found_count == 0) {
            try std.io.getStdOut().writer().print("  {s}No engines found in the engines directory{s}\n", .{ c.yellow, c.reset });
        } else {
            try std.io.getStdOut().writer().print("\n{s}Found {d} engine{s}{s}\n", .{ c.green, found_count, if (found_count == 1) "" else "s", c.reset });
        }
    }

    // Run a specific engine by index
    pub fn runEngine(self: *EngineManager, index: usize) !void {
        const c = self.colors;
        if (index >= self.engines.items.len) {
            return error.InvalidEngineIndex;
        }

        const engine = self.engines.items[index];
        try std.io.getStdOut().writer().print("\n{s}Launching engine:{s} {s}{s}{s}\n", .{ c.blue, c.reset, c.bold, engine.name, c.reset });

        var child = std.process.Child.init(
            &[_][]const u8{engine.path},
            self.allocator,
        );

        try std.io.getStdOut().writer().print("{s}Starting process...{s}", .{ c.dim, c.reset });
        try child.spawn();

        const term = try child.wait();
        if (term.Exited == 0) {
            try std.io.getStdOut().writer().print("\r{s}✓ Engine completed successfully{s}   \n", .{ c.green, c.reset });
        } else {
            try std.io.getStdOut().writer().print("\r{s}✗ Engine exited with status: {d}{s}   \n", .{ c.red, term.Exited, c.reset });
        }
    }
};

// Function to get user input as number
fn getUserInput(reader: anytype, buffer: []u8) !usize {
    if (try reader.readUntilDelimiterOrEof(buffer, '\n')) |user_input| {
        const trimmed = std.mem.trim(u8, user_input, &std.ascii.whitespace);
        return try std.fmt.parseInt(usize, trimmed, 10);
    } else {
        return error.InvalidInput;
    }
}

// Main engine management function
pub fn handleEngines(allocator: std.mem.Allocator) !void {
    var manager = try EngineManager.init(allocator);
    defer manager.deinit();
    const c = manager.colors;

    try manager.scanEngines();

    const stdin = std.io.getStdIn().reader();
    var buffer: [100]u8 = undefined;

    while (true) {
        try manager.listEngines();
        if (manager.engines.items.len == 0) break;

        try std.io.getStdOut().writer().print("{s}Select an engine (1-{d}) or 0 to exit:{s} ", .{ c.blue, manager.engines.items.len, c.reset });

        const choice = getUserInput(stdin, &buffer) catch |err| {
            try std.io.getStdOut().writer().print("\n{s}Invalid input: {any}{s}\n", .{ c.red, err, c.reset });
            continue;
        };

        if (choice == 0) break;

        if (choice > manager.engines.items.len) {
            try std.io.getStdOut().writer().print("\n{s}Please select a number between 1 and {d}{s}\n", .{ c.yellow, manager.engines.items.len, c.reset });
            continue;
        }

        manager.runEngine(choice - 1) catch |err| {
            try std.io.getStdOut().writer().print("\n{s}Error running engine: {any}{s}\n", .{ c.red, err, c.reset });
        };
    }
}
