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

const std = @import("std");
const engineMatch = @import("engineMatch.zig");
const enginePlay = @import("enginePlay.zig");
const Engine = enginePlay.Engine;
const EngineManager = enginePlay.EngineManager;
const MatchManager = engineMatch.MatchManager;
const Logger = @import("logger.zig").Logger;

const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub const EloCalibrationSettings = struct {
    gamesPerLevel: u32 = 4,
    moveTimeMS: u32 = 1000,
    testLevels: []const u32 = &[_]u32{ 0, 5, 10, 15, 20 },
    levelElos: []const u32 = &[_]u32{ 1350, 1850, 2350, 2850, 3350 },
};

pub const CalibratedEngine = struct {
    engine: Engine,
    estimatedElo: u32,
    confidence: u32,

    pub fn format(self: CalibratedEngine, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}: {d} ±{d} Elo", .{ self.engine.name, self.estimatedElo, self.confidence });
    }
};

pub const CalibrationError = error{
    StockfishNotFound,
    StockfishInitFailed,
    InvalidSkillLevel,
    InvalidExecutable,
    ProcessStartFailed,
    ProcessTerminated,
    UciInitFailed,
};

pub const EloEstimator = struct {
    allocator: std.mem.Allocator,
    settings: EloCalibrationSettings,
    engineManager: *EngineManager,

    pub fn init(allocator: std.mem.Allocator, settings: EloCalibrationSettings, engineManager: *EngineManager) EloEstimator {
        return .{
            .allocator = allocator,
            .settings = settings,
            .engineManager = engineManager,
        };
    }

    fn findStockfish(self: *EloEstimator) !Engine {
        for (self.engineManager.engines.items) |engine| {
            var nameBuf: [256]u8 = undefined;
            const lowerName = std.ascii.lowerString(&nameBuf, engine.name);
            if (std.mem.indexOf(u8, lowerName, "stockfish")) |_| {
                return engine;
            }
        }
        return CalibrationError.StockfishNotFound;
    }

    pub fn estimateElo(self: *EloEstimator, engine: Engine) !CalibratedEngine {
        const stockfish = try self.findStockfish();
        var totalScore: f64 = 0;
        var matchCount: u32 = 0;

        std.debug.print("Starting calibration matches...\n", .{});

        for (self.settings.testLevels, self.settings.levelElos) |level, levelElo| {
            std.debug.print("\nTesting against Stockfish level {d} (Elo ~{d})...\n", .{ level, levelElo });

            const preset = engineMatch.MatchPreset{
                .name = "Calibration",
                .description = "Calibration match",
                .moveTimeMS = self.settings.moveTimeMS,
                .gameCount = 1,
            };

            var match = try MatchManager.init(engine, stockfish, self.allocator, preset);
            defer match.deinit();

            try match.white.initialize(&match.logger);
            try match.black.initialize(&match.logger);

            const skill_cmd = try std.fmt.allocPrint(
                self.allocator,
                "setoption name Skill Level value {d}",
                .{level},
            );

            try match.black.sendCommand(&match.logger, skill_cmd);
            try match.black.sendCommand(&match.logger, "isready");

            var buffer: [4096]u8 = undefined;
            while (try match.black.readResponse(&match.logger, &buffer)) |response| {
                if (std.mem.eql(u8, response, "readyok")) break;
            }

            var wins: u32 = 0;
            var draws: u32 = 0;
            var gamesPlayed: u32 = 0;

            while (gamesPlayed < self.settings.gamesPerLevel) : (gamesPlayed += 1) {
                std.debug.print("  Playing game {d}/{d}...\n", .{ gamesPlayed + 1, self.settings.gamesPerLevel });

                // Reset both engines for the new game
                try match.white.sendCommand(&match.logger, "ucinewgame");
                try match.black.sendCommand(&match.logger, "ucinewgame");
                try match.white.sendCommand(&match.logger, "isready");
                try match.black.sendCommand(&match.logger, "isready");

                // Wait for both engines to be ready
                var whiteReady = false;
                var blackReady = false;
                while (!whiteReady or !blackReady) {
                    if (!whiteReady) {
                        if (try match.white.readResponse(&match.logger, &buffer)) |response| {
                            if (std.mem.eql(u8, response, "readyok")) whiteReady = true;
                        }
                    }
                    if (!blackReady) {
                        if (try match.black.readResponse(&match.logger, &buffer)) |response| {
                            if (std.mem.eql(u8, response, "readyok")) blackReady = true;
                        }
                    }
                }

                const result = try match.playMatch();
                switch (result) {
                    .whiteWin => wins += 1,
                    .draw => draws += 1,
                    .blackWin => {},
                }

                // Add a small delay and clear line for next game message
                std.time.sleep(100 * std.time.ns_per_ms);
                try stdout.print("\x1b[1A\x1b[K", .{}); // Move up one line and clear it
            }
            const score = (@as(f64, @floatFromInt(wins)) + @as(f64, @floatFromInt(draws)) * 0.5) /
                @as(f64, @floatFromInt(self.settings.gamesPerLevel));

            totalScore += score * @as(f64, @floatFromInt(levelElo));
            matchCount += 1;

            std.debug.print("  Score vs level {d}: {d} wins, {d} draws ({d:.1}%)\n", .{ level, wins, draws, score * 100 });
        }

        const estimatedElo = @as(u32, @intFromFloat(totalScore / @as(f64, @floatFromInt(matchCount))));
        const confidence = @as(u32, @intFromFloat(200.0 / @sqrt(@as(f64, @floatFromInt(matchCount * self.settings.gamesPerLevel)))));

        return CalibratedEngine{
            .engine = engine,
            .estimatedElo = estimatedElo,
            .confidence = confidence,
        };
    }
};
