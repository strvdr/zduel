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

//! Command-line interface for zduel.
//!
//! Handles user interaction, command parsing, and routing to appropriate
//! functionality. Provides both interactive mode and direct command execution.
//!
//! ## Commands
//! - docs: Open documentation
//! - help: Show usage
//! - engines: Manage engines
//! - match: Start engine match
//!
//! ## Usage
//! ```zig
//! var cli = CLI.init(allocator, engineManager);
//! try cli.runInteractiveMode(); // For interactive CLI
//! try cli.handleCommand("help"); // For direct commands
//! ```

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
pub const Color = struct {
    yellow: []const u8 = "\x1b[33m",
    green: []const u8 = "\x1b[32m",
    red: []const u8 = "\x1b[31m",
    blue: []const u8 = "\x1b[34m",
    magenta: []const u8 = "\x1b[35m",
    cyan: []const u8 = "\x1b[36m",
    bold: []const u8 = "\x1b[1m",
    reset: []const u8 = "\x1b[0m",
    dim: []const u8 = "\x1b[2m",
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
    engineManager: *enginePlay.EngineManager,

    pub fn init(allocator: std.mem.Allocator, engineManager: *enginePlay.EngineManager) CLI {
        return .{
            .allocator = allocator,
            .engineManager = engineManager,
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

            if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |userInput| {
                const trimmed = std.mem.trim(u8, userInput, &std.ascii.whitespace);
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
    const docUrl = "https://zduel.strydr.net";

    try printHeader();

    // Print documentation link
    try stdout.print("📚 {s}Documentation{s} ", .{ colors.green, colors.reset });
    try stdout.print("\x1b]8;;{s}\x1b\\{s}{s}{s}\x1b]8;;\x1b\\\n\n", .{ docUrl, colors.green, colors.underline, colors.reset });

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

        if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |userInput| {
            const trimmed = std.mem.trim(u8, userInput, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;

            if (std.mem.eql(u8, trimmed, "quit")) break;

            try CLI.handleCommand(allocator, trimmed);
        } else break;
    }
}

fn handleMatch(allocator: std.mem.Allocator) !void {
    const colors = Color{};
    var manager = try enginePlay.EngineManager.init(allocator);
    defer manager.deinit();
    try manager.scanEngines();

    if (manager.engines.items.len < 2) {
        try stdout.print("{s}Need at least 2 engines for a match{s}\n", .{ colors.red, colors.reset });
        return;
    }

    try manager.listEngines();

    // Select engines
    try stdout.print("\nSelect {s}WHITE{s} engine (1-{d}): ", .{ colors.blue, colors.reset, manager.engines.items.len });
    try bw.flush();
    const whiteIndex = (try getUserInput()) - 1;

    try stdout.print("Select {s}BLACK{s} engine (1-{d}): ", .{ colors.magenta, colors.reset, manager.engines.items.len });
    try bw.flush();
    const blackIndex = (try getUserInput()) - 1;

    if (whiteIndex >= manager.engines.items.len or blackIndex >= manager.engines.items.len) {
        try stdout.print("{s}Invalid engine selection{s}\n", .{ colors.red, colors.reset });
        return;
    }

    // Display match presets
    try stdout.print("\n{s}Available Match Types:{s}\n", .{ colors.green, colors.reset });
    try stdout.print("══════════════════════\n", .{});

    for (engineMatch.MATCH_PRESETS, 0..) |preset, i| {
        try stdout.print("{s}[{d}]{s} {s}{s}{s}\n", .{
            colors.cyan,
            i + 1,
            colors.reset,
            colors.bold,
            preset.name,
            colors.reset,
        });
        try stdout.print("   {s}{s}{s}\n", .{
            colors.dim,
            preset.description,
            colors.reset,
        });
        if (preset.gameCount > 1) {
            try stdout.print("   {s}Games:{s} {d}\n", .{
                colors.dim,
                colors.reset,
                preset.gameCount,
            });
        }
    }

    try stdout.print("\nSelect match type (1-{d}): ", .{engineMatch.MATCH_PRESETS.len});
    try bw.flush();
    const preset_idx = (try getUserInput()) - 1;

    if (preset_idx >= engineMatch.MATCH_PRESETS.len) {
        try stdout.print("{s}Invalid match type selection{s}\n", .{ colors.red, colors.reset });
        return;
    }

    const preset = engineMatch.MATCH_PRESETS[preset_idx];
    try stdout.print("\n{s}Starting {s}{s} match...{s}\n", .{
        colors.bold,
        colors.green,
        preset.name,
        colors.reset,
    });

    try bw.flush();

    var match = try engineMatch.MatchManager.init(
        manager.engines.items[whiteIndex],
        manager.engines.items[blackIndex],
        allocator,
        preset,
    );
    defer match.deinit();

    var whiteWins: u32 = 0;
    var blackWins: u32 = 0;
    var draws: u32 = 0;

    var gameNumber: u32 = 1;
    while (gameNumber <= preset.gameCount) : (gameNumber += 1) {
        if (preset.gameCount > 1) {
            try stdout.print("\n{s}Game {d} of {d}{s}\n", .{
                colors.bold,
                gameNumber,
                preset.gameCount,
                colors.reset,
            });
        }

        const result = try match.playMatch();
        switch (result) {
            .whiteWin => whiteWins += 1,
            .blackWin => blackWins += 1,
            .draw => draws += 1,
        }
    }

    if (preset.gameCount > 1) {
        try stdout.print("\n{s}Match Results:{s}\n", .{ colors.bold, colors.reset });
        try stdout.print("═════════════\n", .{});
        try stdout.print("{s}{s}:{s} {d} wins\n", .{
            colors.blue,
            match.white.name,
            colors.reset,
            whiteWins,
        });
        try stdout.print("{s}{s}:{s} {d} wins\n", .{
            colors.red,
            match.black.name,
            colors.reset,
            blackWins,
        });
        try stdout.print("Draws: {d}\n", .{draws});

        const matchWinner = if (whiteWins > blackWins)
            match.white
        else if (blackWins > whiteWins)
            match.black
        else
            null;

        if (matchWinner) |winner| {
            try stdout.print("\n{s}{s}{s} wins the match!\n", .{
                winner.color,
                winner.name,
                colors.reset,
            });
        } else {
            try stdout.print("\n{s}Match drawn!{s}\n", .{ colors.yellow, colors.reset });
        }
    }
}

fn getUserInput() !usize {
    var buf: [100]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |userInput| {
        return try std.fmt.parseInt(usize, std.mem.trim(u8, userInput, &std.ascii.whitespace), 10);
    }
    return error.InvalidInput;
}
