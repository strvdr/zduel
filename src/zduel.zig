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

pub const cli = @import("cli.zig");
pub const displayManager = @import("displayManager.zig");
pub const engineMatch = @import("engineMatch.zig");
pub const enginePlay = @import("enginePlay.zig");
pub const logger = @import("logger.zig");
pub const playerMatch = @import("playerMatch.zig");
pub const eloEstimator = @import("eloEstimator.zig");
pub const main = @import("main.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
