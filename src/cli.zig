const std = @import("std");
const builtin = @import("builtin");

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
};

fn printHeader() !void {
    const colors = Color{};
    try stdout.print("\n{s}zduel{s} - A CLI Chess Tool\n", .{ colors.yellow, colors.reset });
    try stdout.print("========================\n\n", .{});
}

// Unified command handler
pub fn handleCommand(allocator: std.mem.Allocator, cmd_name: []const u8) !void {
    const colors = Color{};

    // Look for matching command
    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, cmd_name)) {
            try cmd.handler(allocator);
            return;
        }
    }

    // Command not found
    try stdout.print("{s}Unknown command: {s}{s}\n", .{ colors.red, cmd_name, colors.reset });
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
    for (commands) |cmd| {
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

fn handleEngines(allocator: std.mem.Allocator) !void {
    _ = allocator; // Unused but required for consistent handler signature
    // TODO: Implement engine management
    try stdout.print("Engine management coming soon!\n", .{});
    try bw.flush();
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

            try handleCommand(allocator, trimmed);
        } else break;
    }
}
