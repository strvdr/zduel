//! zduel: A Command Line Chess Tool
//!
//! zduel is a command-line tool for playing and analyzing chess games.
//! It provides a flexible interface for chess engine interaction and game analysis.
//!
//! ## Current Features
//! - Engine management and execution
//!
//! ## Planned Features
//! - Support for multiple chess engines
//! - Engine vs engine matches
//! - Custom engine configuration
//! - Tournament organization between multiple engines
//!
//! ## Usage
//! ```zig
//! ./zduel --help  // Get help
//! ./zduel --engines // Manage engines
//! ./zduel --docs // Open the docs
//! ./zduel --engines // Manage engines
//! ./zduel --match
//! ```
//!
//! ## Project Status
//! zduel is under active development. Features and API may change
//! as the project evolves.

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
