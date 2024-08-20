const std = @import("std");

const Allocator = std.mem.Allocator;

const Game = struct {
    allocator: Allocator,
    counter: u64,

    pub fn init(allocator: Allocator) !Game {
        return Game{ .allocator = allocator, .counter = 0 };
    }

    pub fn printFrame(self: *Game) !void {
        std.debug.print("Something {any}", .{self.counter});
        self.counter += 1;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var game = try Game.init(arena.allocator());

    while (true) {
        try game.printFrame();
        std.debug.print("“\x1B[2J\x1B[H", .{});
    }
}
