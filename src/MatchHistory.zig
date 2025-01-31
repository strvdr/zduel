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
const ztoml = @import("ztoml");
const Engine = @import("EnginePlay.zig").Engine;
const main = @import("main.zig");
const CLI = @import("CLI.zig");

pub const MatchResult = enum {
    win,
    loss,
    draw,
};

const matchStats = struct {
    wins: u32,
    draws: u32,
    losses: u32,
};

pub const EngineHistory = struct {
    engineOne: []const u8,
    engineTwo: []const u8,
    colors: CLI.Color,
    engineOneSide: bool,
    arena: std.heap.ArenaAllocator,

    pub fn init(
        engineOne: []const u8,
        engineTwo: []const u8,
        engineOneSide: bool,
        allocator: std.mem.Allocator,
    ) !EngineHistory {
        const colors = main.colors;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        _ = colors;
        _ = engineOne;
        _ = engineTwo;
        //white is engine one
        if (engineOneSide == true) {} else {}
    }

    pub fn deinit(self: *EngineHistory) void {
        self.arena.deinit();
    }
};
