const std = @import("std");
const ztoml = @import("ztoml");

const MatchHistory = struct {
    engineOne: []const u8,
    engineTwo: []const u8,
    engineOneWins: u32,
    engineTwoWins: u32,
    matchDraws: u32,

    pub fn init(engineOne: []const u8, engineTwo: []const u8, engineOneWins: u32, engineTwoWins: u32, matchDraws: u32) MatchHistory {
        return .{
            .engineOne = engineOne,
            .engineTwo = engineTwo,
            .engineOneWins = engineOneWins,
            .engineTwoWins = engineTwoWins,
            .matchDraws = matchDraws,
        };
    }
};

pub fn log() !void {}
