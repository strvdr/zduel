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
    board: [8][8]?*Piece, // Change to store pointers to pieces
    moveListStartLine: usize,
    boardStartLine: usize,
    currentMove: usize,

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
                Piece{
                    .color = color,
                    .kind = @enumFromInt(ki),
                }
            else
                null;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !DisplayManager {
        // Clear screen and hide cursor
        try stdout.print("\x1b[2J\x1b[?25l", .{});
        try bw.flush();

        var board: [8][8]?*Piece = undefined;
        for (&board) |*rank| {
            for (rank) |*square| {
                square.* = null;
            }
        }

        return DisplayManager{
            .allocator = allocator,
            .colors = Color{},
            .board = board,
            .moveListStartLine = 5,
            .boardStartLine = 5,
            .currentMove = 0,
        };
    }

    pub fn deinit(self: *DisplayManager) void {
        // Show cursor again
        stdout.print("\x1b[?25h", .{}) catch {};
        bw.flush() catch {};

        // Free all allocated pieces
        for (&self.board) |*rank| {
            for (rank) |*square| {
                if (square.*) |piece| {
                    self.allocator.destroy(piece);
                }
                square.* = null;
            }
        }
    }

    pub fn initializeBoard(self: *DisplayManager) !void {
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
                const newPiece = try self.allocator.create(Piece);
                newPiece.* = piece;
                if (self.board[rank][file]) |oldPiece| {
                    self.allocator.destroy(oldPiece);
                }
                self.board[rank][file] = newPiece;
            }
            file += 1;
        }
    }

    fn applyMove(self: *DisplayManager, moveStr: []const u8) !void {
        const fromFile = moveStr[0] - 'a';
        const fromRank = '8' - moveStr[1];
        const toFile = moveStr[2] - 'a';
        const toRank = '8' - moveStr[3];

        if (self.board[fromRank][fromFile]) |piece| {
            // Handle promotion
            if (moveStr.len > 4 and piece.kind == .pawn) {
                if (Piece.fromChar(moveStr[4])) |promoted| {
                    const newPiece = try self.allocator.create(Piece);
                    newPiece.* = promoted;

                    if (self.board[toRank][toFile]) |oldPiece| {
                        self.allocator.destroy(oldPiece);
                    }

                    self.board[toRank][toFile] = newPiece;
                    self.allocator.destroy(piece);
                    self.board[fromRank][fromFile] = null;
                    return;
                }
            }

            // Regular move
            if (self.board[toRank][toFile]) |oldPiece| {
                self.allocator.destroy(oldPiece);
            }
            self.board[toRank][toFile] = piece;
            self.board[fromRank][fromFile] = null;
        }
    }

    pub fn drawBoard(self: *DisplayManager) !void {
        const c = self.colors;

        // Save cursor position for move list
        try stdout.print("\x1b[s", .{});

        // Move cursor to board position (right side)
        try stdout.print("\x1b[{d};40H", .{self.boardStartLine});

        // Draw board frame
        try stdout.print("  ┌────────────────────────┐\n", .{});

        var rank: usize = 0;
        while (rank < 8) : (rank += 1) {
            try stdout.print("\x1b[{d};40H", .{self.boardStartLine + 1 + rank});
            try stdout.print("{d} │", .{8 - rank});

            var file: usize = 0;
            while (file < 8) : (file += 1) {
                const squareColor = if ((rank + file) % 2 == 0)
                    "\x1b[47m" // white background
                else
                    "\x1b[100m"; // gray background

                try stdout.print("{s}", .{squareColor});

                if (self.board[rank][file]) |piece| {
                    const pieceColor = if (piece.color == .white)
                        c.blue
                    else
                        c.red;
                    try stdout.print("{s}{s} {s}{c} {s}", .{
                        c.reset,
                        squareColor,
                        pieceColor,
                        piece.toChar(),
                        c.reset,
                    });
                } else {
                    try stdout.print("   ", .{});
                }
                try stdout.print("{s}", .{c.reset});
            }
            try stdout.print("│\n", .{});
        }

        try stdout.print("\x1b[{d};40H", .{self.boardStartLine + 9});
        try stdout.print("  └────────────────────────┘\n", .{});
        try stdout.print("\x1b[{d};40H", .{self.boardStartLine + 10});
        try stdout.print("    a  b  c  d  e  f  g  h\n", .{});

        // Restore cursor position
        try stdout.print("\x1b[u", .{});
    }

    fn drawMoveList(self: *DisplayManager) !void {
        // Clear move list area
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            try stdout.print("\x1b[{d};0H\x1b[K", .{self.moveListStartLine + i});
        }
    }

    pub fn updateMove(self: *DisplayManager, moveStr: []const u8, player: []const u8, moveNumber: usize) !void {
        const c = self.colors;

        // Save cursor position
        try stdout.print("\x1b[s", .{});

        // Move to appropriate line in move list
        const line = self.moveListStartLine + @divFloor(moveNumber - 1, 2);
        try stdout.print("\x1b[{d};0H", .{line});

        if (moveNumber % 2 == 1) {
            try stdout.print("{d}. {s}{s}{s} {s}", .{
                @divFloor(moveNumber + 1, 2),
                c.blue,
                moveStr,
                c.reset,
                player,
            });
        } else {
            try stdout.print("\x1b[{d};20H{s}{s}{s} {s}", .{
                line,
                c.magenta,
                moveStr,
                c.reset,
                player,
            });
        }

        // Update board based on move
        try self.applyMove(moveStr);
        try self.drawBoard();

        // Restore cursor position
        try stdout.print("\x1b[u", .{});
        try bw.flush();
    }
};
