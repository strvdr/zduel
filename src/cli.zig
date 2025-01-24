const std = @import("std");

//stdout/in init
const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

// for colored terminal output
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const red = "\x1b[31m";
const reset = "\x1b[0m";
const underline = "\x1b[4m";

pub fn runHelpMode() !void {
    try stdout.print("Welcome to {s}zduel{s}, a CLI chess tool.\n", .{ yellow, reset });
    try stdout.print("This is the {s}help{s} menu.\n", .{ green, reset });
    try stdout.print("I would highly recommend starting with our docs:\n", .{});

    // Link to documentation (Using the ANSI escape sequence for a clickable link)
    const docUrl = "https://example.com/docs";
    try stdout.print("\x1b]8;;{s}\x1b\\{s}{s}help{s}\x1b]8;;\x1b\\\n", .{ docUrl, green, underline, reset });

    try stdout.print("Commands: \n", .{});
    try stdout.print("engines\n", .{});

    try stdout.print("> ", .{});

    try bw.flush(); // Don't forget to flush
}

pub fn runDefaultMode() !void {
    try stdout.print("Welcome to zduel, a CLI chess tool.\n", .{});
    try stdout.print("Type \"help\" to get a list of commands.\n", .{});
    try stdout.print("> ", .{});

    try bw.flush(); //Don't forget to flush (:
}
