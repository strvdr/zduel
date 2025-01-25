const std = @import("std");
const builtin = @import("builtin");
const enginePlay = @import("enginePlay.zig");
const engineMatch = @import("engineMatch.zig");

// stdout/stdin init
const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

// ANSI color codes
const Color = struct {
    yellow: []const u8 = "\x1b[33m",
    green: []const u8 = "\x1b[32m",
    red: []const u8 = "\x1b[31m",
    reset: []const u8 = "\x1b[0m",
    underline: []const u8 = "\x1b[4m",
};

// Command structure with handler function
const Command = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    category: []const u8,
    handler: *const fn (allocator: std.mem.Allocator) anyerror!void,
};

pub const CLI = struct {
    allocator: std.mem.Allocator,
    engine_manager: *enginePlay.EngineManager,

    pub fn init(allocator: std.mem.Allocator, engine_manager: *enginePlay.EngineManager) CLI {
        return .{
            .allocator = allocator,
            .engine_manager = engine_manager,
        };
    }

    // List of available commands with their handlers
    const commands = [_]Command{
        .{
            .name = "docs",
            .description = "Open the zduel docs in your default browser",
            .usage = "zduel docs",
            .category = "Documentation",
            .handler = openDocs,
        },
        .{
            .name = "help",
            .description = "Display help information",
            .usage = "zduel help",
            .category = "Documentation",
            .handler = showHelp,
        },
        .{
            .name = "engines",
            .description = "List and manage chess engines",
            .usage = "zduel engines [list|add|remove]",
            .category = "Engine Management",
            .handler = handleEngines,
        },
        .{
            .name = "match",
            .description = "Start a match between two chess engines",
            .usage = "zduel match",
            .category = "Game Play",
            .handler = handleMatch,
        },
    };

    pub fn handleCommand(self: *CLI, cmd_name: []const u8) !void {
        const colors = Color{};

        // Look for matching command
        for (commands) |cmd| {
            if (std.mem.eql(u8, cmd.name, cmd_name)) {
                try cmd.handler(self.allocator);
                return;
            }
        }

        // Command not found
        try stdout.print("{s}Unknown command: {s}{s}\n", .{ colors.red, cmd_name, colors.reset });
        try bw.flush();
    }

    pub fn runInteractiveMode(self: *CLI) !void {
        const colors = Color{};
        var buf: [1024]u8 = undefined;

        try printHeader();
        try stdout.print("Type \"{s}help{s}\" to get started, or \"{s}quit{s}\" to exit.\n", .{ colors.green, colors.reset, colors.green, colors.reset });

        while (true) {
            try stdout.print("> ", .{});
            try bw.flush();

            if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
                const trimmed = std.mem.trim(u8, user_input, &std.ascii.whitespace);
                if (trimmed.len == 0) continue;

                if (std.mem.eql(u8, trimmed, "quit")) break;

                try self.handleCommand(trimmed);
            } else break;
        }
    }
};

// Keep existing helper functions...
fn printHeader() !void {
    const colors = Color{};
    try stdout.print("\n{s}zduel{s} - A CLI Chess Tool\n", .{ colors.yellow, colors.reset });
    try stdout.print("========================\n\n", .{});
}

// Handler functions...
fn handleEngines(allocator: std.mem.Allocator) !void {
    try enginePlay.handleEngines(allocator);
    try bw.flush();
}

// Handler functions for each command
// Note: All handlers must accept allocator parameter for consistency, even if unused
fn showHelp(allocator: std.mem.Allocator) !void {
    _ = allocator; // Unused but required for consistent handler signature
    const colors = Color{};
    const doc_url = "https://example.com/docs";

    try printHeader();

    // Print documentation link
    try stdout.print("📚 {s}Documentation{s} ", .{ colors.green, colors.reset });
    try stdout.print("\x1b]8;;{s}\x1b\\{s}{s}{s}\x1b]8;;\x1b\\\n\n", .{ doc_url, colors.green, colors.underline, colors.reset });

    // Print available commands
    try stdout.print("{s}Available Commands:{s}\n", .{ colors.green, colors.reset });
    try stdout.print("------------------\n", .{});

    // Group commands by category
    var current_category: ?[]const u8 = null;
    for (CLI.commands) |cmd| {
        if (current_category == null or !std.mem.eql(u8, current_category.?, cmd.category)) {
            try stdout.print("\n{s}{s}:{s}\n", .{ colors.yellow, cmd.category, colors.reset });
            current_category = cmd.category;
        }

        try stdout.print("  {s}{s}{s}\n", .{ colors.green, cmd.name, colors.reset });
        try stdout.print("    Description: {s}\n", .{cmd.description});
        try stdout.print("    Usage: {s}\n", .{cmd.usage});
    }

    try bw.flush();
}

fn openDocs(allocator: std.mem.Allocator) !void {
    const docUrl = "https://zduel-docs.vercel.app/";
    const command = switch (builtin.target.os.tag) {
        .windows => "start",
        .macos => "open",
        .linux => "xdg-open",
        else => return error.UnsupportedOS,
    };

    var process = std.process.Child.init(
        &[_][]const u8{ command, docUrl },
        allocator,
    );

    try process.spawn();
    _ = try process.wait();
}

// Interactive mode
pub fn runInteractiveMode(allocator: std.mem.Allocator) !void {
    const colors = Color{};
    var buf: [1024]u8 = undefined;

    try printHeader();
    try stdout.print("Type \"{s}help{s}\" to get started, or \"{s}quit{s}\" to exit.\n", .{ colors.green, colors.reset, colors.green, colors.reset });

    while (true) {
        try stdout.print("> ", .{});
        try bw.flush();

        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
            const trimmed = std.mem.trim(u8, user_input, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            if (std.mem.eql(u8, trimmed, "quit")) break;

            try CLI.handleCommand(allocator, trimmed);
        } else break;
    }
}

fn handleMatch(allocator: std.mem.Allocator) !void {
    var manager = try enginePlay.EngineManager.init(allocator);
    defer manager.deinit();
    try manager.scanEngines();

    if (manager.engines.items.len < 2) {
        try stdout.print("Need at least 2 engines for a match\n", .{});
        return;
    }

    try manager.listEngines();

    // Select engines
    try stdout.print("\nSelect WHITE engine (1-{d}): ", .{manager.engines.items.len});
    try bw.flush();
    const white_idx = (try getUserInput()) - 1;

    try stdout.print("Select BLACK engine (1-{d}): ", .{manager.engines.items.len});
    try bw.flush();
    const black_idx = (try getUserInput()) - 1;

    if (white_idx >= manager.engines.items.len or black_idx >= manager.engines.items.len) {
        try stdout.print("Invalid engine selection\n", .{});
        return;
    }

    var match = try engineMatch.MatchManager.init(manager.engines.items[white_idx], manager.engines.items[black_idx], allocator);
    defer match.deinit();

    try match.playMatch();
}

fn getUserInput() !usize {
    var buf: [100]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |user_input| {
        return try std.fmt.parseInt(usize, std.mem.trim(u8, user_input, &std.ascii.whitespace), 10);
    }
    return error.InvalidInput;
}
