const std = @import("std");

const Allocator = std.mem.Allocator;

const ACTIVE: u8 = 35;
const DISABLED: u8 = 32;

const Game = struct {
    allocator: Allocator,
    file: std.fs.File,
    worldTick: f64,
    worldWidth: u64,
    worldHeight: u64,
    worldCount: usize = undefined,
    worldMatrix: std.ArrayList(bool) = undefined,
    iterator: usize = 0,

    pub fn init(allocator: Allocator, file: std.fs.File, worldTick: f64, worldSize: @Vector(2, u64)) !Game {
        var game = Game{ .allocator = allocator, .file = file, .worldTick = worldTick, .worldWidth = worldSize[0], .worldHeight = worldSize[1] };
        try game.initWorld();
        return game;
    }

    pub fn initWorld(self: *Game) !void {
        self.worldCount = self.worldHeight * self.worldWidth;
        self.worldMatrix = std.ArrayList(bool).init(self.allocator);
        for (0..self.worldCount) |_| {
            try self.worldMatrix.append(true);
        }
    }

    pub fn deinit(self: *Game) !void {
        self.worldMatrix.deinit();
    }

    pub fn run(self: *Game, time: u64) !void {
        if (time == 0) {
            while (true) {
                _ = try self.proceedTick();
            }
        }

        var timer: u64 = 0;
        while (timer <= time) {
            const delay = try self.proceedTick();
            timer += delay;
        }
    }

    fn proceedTick(self: *Game) !u64 {
        try self.clearConsole();
        try self.printWorld();
        try self.calculateNextStep();
        const sleep_time: u64 = @intFromFloat(self.worldTick * @as(f64, @floatFromInt(std.time.ns_per_s)));
        std.time.sleep(sleep_time);
        return sleep_time;
    }

    fn printWorld(self: *Game) !void {
        var chars: std.ArrayList(u8) = std.ArrayList(u8).init(self.allocator);
        defer chars.deinit();

        for (self.worldMatrix.items, 0..) |item, i| {
            if (item) {
                try chars.append(ACTIVE);
            } else {
                try chars.append(DISABLED);
            }

            if ((i + 1) % self.worldWidth == 0) {
                try chars.append(std.ascii.control_code.cr);
                try chars.append(std.ascii.control_code.lf);
            }
        }

        try self.print("{s}", .{chars.items});
    }

    fn calculateNextStep(self: *Game) !void {
        self.worldMatrix.items[self.iterator] = !self.worldMatrix.items[self.iterator];
        if (self.iterator == self.worldCount - 1) {
            self.iterator = 0;
        } else {
            self.iterator += 1;
        }
    }

    fn clearConsole(self: *Game) !void {
        try self.print("{c}[0;0H{c}[J", .{ std.ascii.control_code.esc, std.ascii.control_code.esc });
    }

    fn print(self: *Game, comptime fmt: []const u8, args: anytype) !void {
        const buffer = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(buffer);
        _ = try self.file.writer().write(buffer);
    }
};

const in_worldTick: f64 = 0.01;
const in_worldSize: @Vector(2, u64) = .{ 20, 10 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const in_file = std.io.getStdOut();

    var game = try Game.init(allocator, in_file, in_worldTick, in_worldSize);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    try game.run(0);
}

test "Memory leak test" {
    const allocator = std.testing.allocator;
    const in_file = std.io.getStdOut();

    var game = try Game.init(allocator, in_file, in_worldTick, in_worldSize);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    try game.run(100);
}
