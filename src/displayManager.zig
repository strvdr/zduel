const std = @import("std");
const cli = @import("cli.zig");
const Color = cli.Color;

const stdout_file = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub const DisplayManager = struct {
    allocator: std.mem.Allocator,
    colors: Color,
    board: [8][8]?Piece,
    move_list_start_line: usize,
    board_start_line: usize,
    current_move: usize,

    const PieceColor = enum(u1) { white = 0, black = 1 };
    const PieceKind = enum(u3) { pawn = 0, knight = 1, bishop = 2, rook = 3, queen = 4, king = 5 };

    const Piece = struct {
        color: PieceColor,
        kind: PieceKind,

        fn toChar(self: Piece) u8 {
            const chars = "pnbrqk";
            const index = @intFromEnum(self.kind);
            const c = chars[index];
            return if (self.color == .white) std.ascii.toUpper(c) else c;
        }

        fn fromChar(c: u8) ?Piece {
            const color = if (std.ascii.isUpper(c)) PieceColor.white else PieceColor.black;
            const lower_c = std.ascii.toLower(c);

            const kind_int: ?u3 = switch (lower_c) {
                'p' => 0,
                'n' => 1,
                'b' => 2,
                'r' => 3,
                'q' => 4,
                'k' => 5,
                else => null,
            };

            return if (kind_int) |ki|
                Piece{ .color = color, .kind = @enumFromInt(ki) }
            else
                null;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !DisplayManager {
        // Clear screen and hide cursor
        try stdout.print("\x1b[2J\x1b[?25l", .{});
        try bw.flush();

        return DisplayManager{
            .allocator = allocator,
            .colors = Color{},
            .board = undefined,
            .move_list_start_line = 5, // Leave space for header
            .board_start_line = 5,
            .current_move = 0,
        };
    }

    pub fn deinit(self: *DisplayManager) void {
        // Show cursor again
        stdout.print("\x1b[?25h", .{}) catch {};
        bw.flush() catch {};

        // Clear board state
        for (&self.board) |*rank| {
            for (rank) |*square| {
                square.* = null;
            }
        }
    }

    pub fn initializeBoard(self: *DisplayManager) !void {
        // Parse starting position FEN
        try self.loadFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR");
        try self.drawBoard();
        try self.drawMoveList();
        try bw.flush();
    }

    fn loadFen(self: *DisplayManager, fen: []const u8) !void {
        var rank: usize = 0;
        var file: usize = 0;

        for (fen) |c| {
            if (c == '/') {
                rank += 1;
                file = 0;
                continue;
            }

            if (std.ascii.isDigit(c)) {
                file += c - '0';
                continue;
            }

            if (Piece.fromChar(c)) |piece| {
                self.board[rank][file] = piece;
            }
            file += 1;
        }
    }

    pub fn drawBoard(self: *DisplayManager) !void {
        const c = self.colors;

        // Save cursor position for move list
        try stdout.print("\x1b[s", .{});

        // Move cursor to board position (right side)
        try stdout.print("\x1b[{d};40H", .{self.board_start_line});

        // Draw board frame
        try stdout.print("  ┌──────────────────────┐\n", .{});

        var rank: usize = 0;
        while (rank < 8) : (rank += 1) {
            try stdout.print("\x1b[{d};40H", .{self.board_start_line + 1 + rank});
            try stdout.print("{d} │", .{8 - rank});

            var file: usize = 0;
            while (file < 8) : (file += 1) {
                const square_color = if ((rank + file) % 2 == 0)
                    "\x1b[47m" // white background
                else
                    "\x1b[100m"; // gray background

                try stdout.print("{s}", .{square_color});

                if (self.board[rank][file]) |piece| {
                    const piece_color = if (piece.color == .white)
                        c.blue
                    else
                        c.magenta;
                    try stdout.print(" {s}{c}{s} ", .{ piece_color, piece.toChar(), c.reset });
                } else {
                    try stdout.print("   ", .{});
                }
                try stdout.print("\x1b[0m", .{});
            }
            try stdout.print("│\n", .{});
        }

        try stdout.print("\x1b[{d};40H", .{self.board_start_line + 9});
        try stdout.print("  └──────────────────────┘\n", .{});
        try stdout.print("\x1b[{d};40H", .{self.board_start_line + 10});
        try stdout.print("    a  b  c  d  e  f  g  h\n", .{});

        // Restore cursor position
        try stdout.print("\x1b[u", .{});
    }

    fn drawMoveList(self: *DisplayManager) !void {
        // Clear move list area
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            try stdout.print("\x1b[{d};0H\x1b[K", .{self.move_list_start_line + i});
        }
    }

    pub fn updateMove(self: *DisplayManager, move_str: []const u8, player: []const u8, move_number: usize) !void {
        const c = self.colors;

        // Save cursor position
        try stdout.print("\x1b[s", .{});

        // Move to appropriate line in move list
        const line = self.move_list_start_line + @divFloor(move_number - 1, 2);
        try stdout.print("\x1b[{d};0H", .{line});

        if (move_number % 2 == 1) {
            // White's move
            try stdout.print("{d}. {s}{s}{s} {s}", .{
                @divFloor(move_number + 1, 2),
                c.blue,
                move_str,
                c.reset,
                player,
            });
        } else {
            // Black's move - move cursor to middle of line
            try stdout.print("\x1b[{d};20H{s}{s}{s} {s}", .{
                line,
                c.magenta,
                move_str,
                c.reset,
                player,
            });
        }

        // Update board based on move
        try self.applyMove(move_str);
        try self.drawBoard();

        // Restore cursor position
        try stdout.print("\x1b[u", .{});
        try bw.flush();
    }

    fn applyMove(self: *DisplayManager, move_str: []const u8) !void {
        const from_file = move_str[0] - 'a';
        const from_rank = '8' - move_str[1];
        const to_file = move_str[2] - 'a';
        const to_rank = '8' - move_str[3];

        // Move piece
        if (self.board[from_rank][from_file]) |piece| {
            self.board[to_rank][to_file] = piece;
            self.board[from_rank][from_file] = null;

            // Handle promotion
            if (move_str.len > 4 and piece.kind == .pawn) {
                if (Piece.fromChar(move_str[4])) |promoted_piece| {
                    self.board[to_rank][to_file] = Piece{
                        .color = piece.color,
                        .kind = promoted_piece.kind,
                    };
                }
            }
        }
    }
};
