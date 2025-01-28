const std = @import("std");
const ztoml = @import("ztoml");
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Config = struct {
    engineOneColor: []const u8,
    engineTwoColor: []const u8,
    arena: *ArenaAllocator, // Keep the arena alive

    pub fn init() Config {
        return .{
            .engineOneColor = "blue",
            .engineTwoColor = "red",
            .arena = undefined,
        };
    }

    pub fn loadFromFile(allocator: std.mem.Allocator) !Config {
        // Create an arena and store it in the config
        var arena = try allocator.create(ArenaAllocator);
        arena.* = ArenaAllocator.init(allocator);

        // Try to read the config file
        const file = std.fs.cwd().openFile("./.config/zduel.toml", .{}) catch |err| {
            allocator.destroy(arena);
            if (err == error.FileNotFound) {
                return Config.init();
            }
            return err;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const tomlContent = try arena.allocator().alloc(u8, file_size);
        _ = try file.readAll(tomlContent);

        var parser = ztoml.Parser.init(arena, tomlContent);
        const result = try parser.parse();

        // Create config with the arena
        var config = Config{
            .engineOneColor = "blue",
            .engineTwoColor = "red",
            .arena = arena,
        };

        if (ztoml.getValue(result, &[_][]const u8{ "Engine Colors", "engineOne" })) |value| {
            config.engineOneColor = value.data.String;
        }
        if (ztoml.getValue(result, &[_][]const u8{ "Engine Colors", "engineTwo" })) |value| {
            config.engineTwoColor = value.data.String;
        }

        return config;
    }

    pub fn deinit(self: *Config) void {
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }
};
