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
const cli = @import("cli.zig");
const enginePlay = @import("enginePlay.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create engine manager
    var manager = try enginePlay.EngineManager.init(allocator);
    defer manager.deinit();

    // Scan for available engines at startup
    try manager.scanEngines();

    // Initialize CLI
    var cli_handler = cli.CLI.init(allocator, &manager);

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // skip program name

    // If we have arguments, handle them directly
    if (args.next()) |arg| {
        const cmd = if (std.mem.startsWith(u8, arg, "--"))
            arg[2..] // Strip the -- prefix
        else
            arg;

        try cli_handler.handleCommand(cmd);
        return;
    }

    // No arguments, run in interactive mode
    try cli_handler.runInteractiveMode();
}
