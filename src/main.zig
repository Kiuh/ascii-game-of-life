const std = @import("std");

const Allocator = std.mem.Allocator;
const Vec2 = @Vector(2, u64);
const ESC: u8 = 27;

const Game = struct {
    allocator: Allocator,
    file: std.fs.File,
    worldTick: u64,
    worldSize: Vec2,

    pub fn init(allocator: Allocator, file: std.fs.File, worldTick: u64, worldSize: Vec2) !Game {
        var game = Game{ .allocator = allocator, .file = file, .worldTick = worldTick, .worldSize = worldSize };
        try game.prepare();
        return game;
    }

    pub fn deinit(self: *Game) void {
        _ = self; // autofix
    }

    pub fn prepare(self: *Game) !void {
        _ = self; // autofix
    }

    pub fn run(self: *Game) !void {
        while (true) {
            try self.clearConsole();
            try self.printWorld();
            try self.calculateNextStep();
            std.time.sleep(self.worldTick * std.time.ns_per_s);
        }
    }

    fn printWorld(self: *Game) !void {
        try self.print("World live\n", .{});
    }

    fn calculateNextStep(self: *Game) !void {
        _ = self; // autofix
    }

    fn clearConsole(self: *Game) !void {
        try self.print("{c}[0;0H{c}[J", .{ ESC, ESC });
    }

    fn print(self: *Game, comptime fmt: []const u8, args: anytype) !void {
        const buffer = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(buffer);
        _ = try self.file.writer().write(buffer);
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const file = std.io.getStdOut();
    const worldTick = 1;
    const worldSize: Vec2 = .{ 50, 50 };

    var game = try Game.init(allocator, file, worldTick, worldSize);
    defer game.deinit();

    try game.run();
}
