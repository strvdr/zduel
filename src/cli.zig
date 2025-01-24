const std = @import("std");

//stdout/in init
const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

// ANSI color codes
const Color = struct {
    yellow: []const u8 = "\x1b[33m",
    green: []const u8 = "\x1b[32m",
    reset: []const u8 = "\x1b[0m",
    underline: []const u8 = "\x1b[4m",
};

// Command structure for easy addition of new commands
const Command = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    category: []const u8,
};

/// Contains a list of arguments you can provide zduel at runtime or
/// provide via stdin.
/// Template for adding new commands:
/// .{
///    .name = "command_name",
///    .description = "Brief description of what the command does",
///    .usage = "zduel command_name [subcommands]",
///    .category = "Category Name",
/// },
const commands = [_]Command{
    .{
        .name = "docs",
        .description = "Open the zduel docs",
        .usage = "zduel docs",
        .category = "Documentation",
    },
    .{
        .name = "help",
        .description = "You're already here",
        .usage = "zduel help",
        .category = "Documentation",
    },
    .{
        .name = "engines",
        .description = "List and manage chess engines",
        .usage = "zduel engines [list|add|remove]",
        .category = "Engine Management",
    },
};

pub fn runHelpMode() !void {
    const colors = Color{};
    const doc_url = "https://example.com/docs";

    // Print header
    try stdout.print("\n{s}zduel{s} - A CLI Chess Tool\n", .{ colors.yellow, colors.reset });
    try stdout.print("======================\n\n", .{});

    // Print documentation link
    try stdout.print("📚 {s}Documentation{s} ", .{ colors.green, colors.reset });
    try stdout.print("\x1b]8;;{s}\x1b\\{s}{s}{s}\x1b]8;;\x1b\\\n\n", .{ doc_url, colors.green, colors.underline, colors.reset });

    // Print available commands
    try stdout.print("{s}Available Commands:{s}\n", .{ colors.green, colors.reset });
    try stdout.print("------------------\n", .{});

    // Group commands by category
    var current_category: ?[]const u8 = null;
    for (commands) |cmd| {
        // Print category header if it's a new category
        if (current_category == null or !std.mem.eql(u8, current_category.?, cmd.category)) {
            try stdout.print("\n{s}{s}:{s}\n", .{ colors.yellow, cmd.category, colors.reset });
            current_category = cmd.category;
        }

        // Print command details
        try stdout.print("  {s}{s}{s}\n", .{ colors.green, cmd.name, colors.reset });
        try stdout.print("    Description: {s}\n", .{cmd.description});
        try stdout.print("    Usage: {s}\n", .{cmd.usage});
    }

    try stdout.print("\n> ", .{});
    try bw.flush();
}

pub fn runDefaultMode() !void {
    try stdout.print("Welcome to zduel, a CLI chess tool.\n", .{});
    try stdout.print("Type \"help\" to get a list of commands.\n", .{});
    try stdout.print("> ", .{});

    try bw.flush(); //Don't forget to flush (:
}
