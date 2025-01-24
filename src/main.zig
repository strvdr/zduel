const std = @import("std");
const cli = @import("cli.zig");

const Mode = enum { none, help };

pub fn main() !void {
    // stdout & stdin init
    const stdout_file = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var buf: [10]u8 = undefined;

    // Parse command line arguments
    var args = std.process.args();
    _ = args.skip(); // skip program name

    var mode: Mode = .none;

    if (args.next()) |arg| {
        mode = if (std.mem.eql(u8, arg, "--help")) .help else .none;
    }

    try switch (mode) {
        .none => cli.runDefaultMode(),
        .help => cli.runHelpMode(),
    };

    try bw.flush(); // Don't forget to flush!

    _ = try stdin.readUntilDelimiterOrEof(buf[0..], '\n');

    try stdout.print("User entered: {s}\n", .{buf});

    try bw.flush(); // Don't forget to flush!

}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const global = struct {
        fn testOne(input: []const u8) anyerror!void {
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(global.testOne, .{});
}
