const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ACTIVE: u8 = 35;
const DISABLED: u8 = 32;
const ascii_code = std.ascii.control_code;

const Size = struct {
    width: usize,
    height: usize,
    length: usize,
};

const Game = struct {
    allocator: Allocator,
    file: std.fs.File,
    worldTick: f64,
    size: Size,
    worldMatrix: ArrayList(bool) = undefined,
    iterator: usize = 0,

    pub fn init(allocator: Allocator, file: std.fs.File, worldTick: f64, worldSize: @Vector(2, u64)) !Game {
        var game = Game{
            .allocator = allocator,
            .file = file,
            .worldTick = worldTick,
            .size = .{
                .width = worldSize[0],
                .height = worldSize[1],
                .length = worldSize[0] * worldSize[1],
            },
        };
        try game.initWorld();
        return game;
    }

    pub fn initWorld(self: *Game) !void {
        self.worldMatrix = ArrayList(bool).init(self.allocator);
        for (0..self.size.length) |_| {
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
        var chars = ArrayList(u8).init(self.allocator);
        defer chars.deinit();

        for (self.worldMatrix.items, 0..) |item, i| {
            if (item) {
                try chars.append(ACTIVE);
            } else {
                try chars.append(DISABLED);
            }

            if ((i + 1) % self.size.width == 0) {
                try chars.append(ascii_code.cr);
                try chars.append(ascii_code.lf);
            }
        }

        try self.print("{s}", .{chars.items});
    }

    fn calculateNextStep(self: *Game) !void {
        self.worldMatrix.items[self.iterator] = !self.worldMatrix.items[self.iterator];
        if (self.iterator == self.size.length - 1) {
            self.iterator = 0;
        } else {
            self.iterator += 1;
        }
    }

    fn clearConsole(self: *Game) !void {
        try self.print("{c}[0;0H{c}[J", .{ ascii_code.esc, ascii_code.esc });
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

test "memory-leak-test" {
    const allocator = std.testing.allocator;
    const file_name = "test_file.txt";
    const in_file = try std.fs.cwd().createFile(
        file_name,
        .{ .read = true },
    );
    defer in_file.close();
    defer std.fs.cwd().deleteFile(file_name) catch |err| {
        std.debug.panic("Cannot delete file!\n{any}", .{err});
    };

    var game = try Game.init(allocator, in_file, in_worldTick, in_worldSize);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    try game.run(100);
}
