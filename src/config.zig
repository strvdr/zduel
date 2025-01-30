const std = @import("std");
const ztoml = @import("ztoml");
const ArenaAllocator = std.heap.ArenaAllocator;
pub const Config = struct {
    engineOneColor: []const u8,
    engineTwoColor: []const u8,
    arena: ?*std.heap.ArenaAllocator, // Make this optional

    pub fn init() Config {
        return .{
            .engineOneColor = "blue",
            .engineTwoColor = "red",
            .arena = null, // Initialize as null
        };
    }

    pub fn loadFromFile(allocator: std.mem.Allocator) !Config {
        // Create arena allocator
        var arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        // Try to read the config file
        const file = std.fs.cwd().openFile("./.config/zduel.toml", .{}) catch |err| {
            if (err == error.FileNotFound) {
                // If file doesn't exist, return default config but with the arena
                var default_config = Config.init();
                default_config.arena = arena;
                return default_config;
            }
            // For any other error, clean up and return error
            arena.deinit();
            allocator.destroy(arena);
            return err;
        };
        defer file.close();

        // Read file content
        const file_size = try file.getEndPos();
        const tomlContent = try arena.allocator().alloc(u8, file_size);
        _ = try file.readAll(tomlContent);

        // Parse TOML
        var parser = ztoml.Parser.init(arena, tomlContent);
        const result = try parser.parse();

        // Create config with the arena
        var config = Config{
            .engineOneColor = "blue",
            .engineTwoColor = "red",
            .arena = arena,
        };

        // Try to get values from TOML
        if (ztoml.getValue(result, &[_][]const u8{ "Engine Colors", "engineOne" })) |value| {
            config.engineOneColor = value.data.String;
        }
        if (ztoml.getValue(result, &[_][]const u8{ "Engine Colors", "engineTwo" })) |value| {
            config.engineTwoColor = value.data.String;
        }

        return config;
    }

    pub fn deinit(self: *Config) void {
        if (self.arena) |arena| {
            arena.deinit();
            arena.child_allocator.destroy(arena);
            self.arena = null;
        }
    }
};
