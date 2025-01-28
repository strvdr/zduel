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

//! zduel: UCI Chess Engine Match Manager
//!
//! Command-line tool for managing and running matches between UCI-compatible chess engines.
//!
//! ## Features
//! - Engine vs engine matches with multiple time controls
//! - Real-time board visualization
//! - Match logging and analysis
//! - Cross-platform support
//!
//! ## Match Types
//! - Blitz (1s per move)
//! - Rapid (5s per move)
//! - Classical (15s per move)
//! - Tournament (Best of 3 rapid games)
//!
//! ## Commands
//! ```zig
//! zduel          // Interactive mode
//! zduel help     // Show commands
//! zduel docs     // Open documentation
//! zduel engines  // Manage engines
//! zduel match    // Start engine match
//! ```
//!
//! ## Engine Setup
//! Place UCI-compatible engines in the `engines` directory.
//! Use the `engines` command to manage them.
//!
//! ## Project Status
//! In active development. See documentation at
//! https://zduel.strydr.net for latest updates.

const std = @import("std");
const CLI = @import("CLI.zig");
const cfg = @import("config.zig");
const EnginePlay = @import("EnginePlay.zig");

const stdout_file = std.io.getStdOut().writer();
pub var bw = std.io.bufferedWriter(stdout_file);
pub const stdout = bw.writer();
pub const stdin = std.io.getStdIn().reader();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try CLI.printHeader();
    // Create engine manager
    var manager = try EnginePlay.EngineManager.init(allocator);
    defer manager.deinit();

    // Initialize CLI
    var cliHandler = CLI.CLI.init(allocator, &manager);

    var colors = CLI.Color{};
    // Load and apply config
    const config = try cfg.Config.loadFromFile(allocator);
    colors.updateColors(config);

    // Scan for available engines at startup
    manager.scanEngines() catch {
        std.debug.print("No engines directory found. From the project root, please \"mkdir engines\".", .{});
    };

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // skip program name

    // If we have arguments, handle them directly
    if (args.next()) |arg| {
        const cmd = if (std.mem.startsWith(u8, arg, "--"))
            arg[2..] // Strip the -- prefix
        else
            arg;

        try cliHandler.handleCommand(cmd);
        return;
    }

    // No arguments, run in interactive mode
    try cliHandler.runInteractiveMode();
}
