const std = @import("std");
const ztoml = @import("ztoml");
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Config = struct {
    engineOneColor: []const u8,
    engineTwoColor: []const u8,

    pub fn init(engineOneColor: []const u8, engineTwoColor: []const u8) Config {
        return .{
            .engineOneColor = engineOneColor,
            .engineTwoColor = engineTwoColor,
        };
    }
};

pub fn parseCfg() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.debug.print("Memory leak detected!\n", .{});
    }

    var arena = ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    // Read the file
    const file = try std.fs.cwd().openFile("./.config/zduel.toml", .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const toml_content = try arena.allocator().alloc(u8, file_size);
    _ = try file.readAll(toml_content);

    var parser = ztoml.Parser.init(&arena, toml_content);
    const result = try parser.parse();

    // Example: Get and print a specific value
    const path = [_][]const u8{ "Engine Colors", "engineTwo" };
    if (ztoml.getValue(result, &path)) |value| {
        std.debug.print("Value of engineTwo: ", .{});
        ztoml.printValue(value);
        std.debug.print("\n", .{});
    } else {
        std.debug.print("Value not found\n", .{});
    }
}

//pub fn log() !void {
//    var cfg = Config.init(
//}
