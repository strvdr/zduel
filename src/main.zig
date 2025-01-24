//! zduel: A Command Line Chess Tool
//!
//! zduel is a command-line tool for playing and analyzing chess games.
//! It provides a flexible interface for chess engine interaction and game analysis.
//!
//! ## Current Features
//! - None
//!
//! ## Planned Features
//! - Support for multiple chess engines
//! - Engine vs engine matches
//! - Custom engine configuration
//! - Tournament organization between multiple engines
//!
//! ## Usage
//! ```zig
//! zduel --help  // Get help
//! ```
//!
//! ## Project Status
//! zduel is under active development. Features and API may change
//! as the project evolves.
const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // skip program name

    // If we have arguments, handle them directly
    if (args.next()) |arg| {
        const cmd = if (std.mem.startsWith(u8, arg, "--"))
            arg[2..] // Strip the -- prefix
        else
            arg;

        try cli.handleCommand(allocator, cmd);
        return;
    }

    // No arguments, run in interactive mode
    try cli.runInteractiveMode(allocator);
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const global = struct {
        fn testOne(input: []const u8) anyerror!void {
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(global.testOne, .{});
}
