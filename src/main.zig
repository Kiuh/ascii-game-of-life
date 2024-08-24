const std = @import("std");

const log = std.debug.print;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ACTIVE: u8 = 35;
const DISABLED: u8 = 32;
const ascii_code = std.ascii.control_code;

const Vec2 = struct {
    x: u64,
    y: u64,

    pub fn fromUSize(x: usize, y: usize) Vec2 {
        return Vec2{ .x = x, .y = y };
    }

    pub fn len(self: Vec2) u64 {
        return self.x * self.y;
    }
};

const Matrix = struct {
    list: ArrayList(bool),
    size: Vec2,

    pub fn init(allocator: Allocator, size: Vec2) !Matrix {
        var matrix = Matrix{ .size = size, .list = ArrayList(bool).init(allocator) };
        try matrix.fillList();
        return matrix;
    }

    pub fn deinit(self: *Matrix) void {
        self.list.deinit();
    }

    pub fn getValue(self: *Matrix, p: Vec2) bool {
        return self.list.items[p.x + p.y * self.size.x];
    }

    pub fn setValue(self: *Matrix, p: Vec2, value: bool) void {
        self.list.items[p.x + p.y * self.size.x] = value;
    }

    pub fn getActiveNeighboursCount(self: *Matrix, p: Vec2) u8 {
        //log("----$$$\n", .{});
        var counter: u8 = 0;
        for (0..3) |y_i| {
            for (0..3) |x_i| {
                if ((p.x == 0 and x_i == 0) or (p.y == 0 and y_i == 0) or (x_i == 1 and y_i == 1)) {
                    //log("skip {} {}\n", .{ x_i, y_i });
                    continue;
                }

                const pos = Vec2{
                    .x = p.x + x_i - 1,
                    .y = p.y + y_i - 1,
                };

                if (self.isValid(pos) and self.getValue(pos)) {
                    counter += 1;
                }

                //log("{} {}\n", .{ pos, self.isValid(pos) and self.getValue(pos) });
            }
            //log("--ENDL\n", .{});
        }
        //log("----$$$\n", .{});
        return counter;
    }

    fn isValid(self: *Matrix, p: Vec2) bool {
        return p.x < self.size.x and p.y < self.size.y;
    }

    fn fillList(self: *Matrix) !void {
        for (0..self.size.len()) |_| {
            try self.list.append(true);
        }
    }

    fn setRandomBools(self: *Matrix) void {
        const rand = std.crypto.random;

        for (0..self.size.len()) |i| {
            self.list.items[i] = rand.boolean();
        }
    }
};

const Game = struct {
    allocator: Allocator,
    file: std.fs.File,
    worldTick: f64,
    size: Vec2,
    worldMatrix1: Matrix = undefined,
    worldMatrix2: Matrix = undefined,
    activeMatrix: *Matrix = undefined,

    pub fn init(allocator: Allocator, file: std.fs.File, worldTick: f64, size: Vec2) !Game {
        var game = Game{
            .allocator = allocator,
            .file = file,
            .worldTick = worldTick,
            .size = size,
        };

        try game.initMatrices();
        game.setRandomWorld();
        return game;
    }

    fn initMatrices(self: *Game) !void {
        self.worldMatrix1 = try Matrix.init(self.allocator, self.size);
        self.worldMatrix2 = try Matrix.init(self.allocator, self.size);
        self.activeMatrix = &self.worldMatrix1;
    }

    fn setRandomWorld(self: *Game) void {
        self.worldMatrix1.setRandomBools();
    }

    pub fn deinit(self: *Game) !void {
        self.worldMatrix1.deinit();
        self.worldMatrix2.deinit();
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

        for (0..self.size.y) |y| {
            for (0..self.size.x) |x| {
                const p = Vec2.fromUSize(x, y);
                if (self.activeMatrix.getValue(p)) {
                    try chars.append(ACTIVE);
                } else {
                    try chars.append(DISABLED);
                }
            }
            try chars.append(ascii_code.cr);
            try chars.append(ascii_code.lf);
        }
        try self.print("{s}", .{chars.items});
    }

    fn calculateNextStep(self: *Game) !void {
        var source: *Matrix = &self.worldMatrix1;
        var result: *Matrix = &self.worldMatrix2;
        if (self.activeMatrix == result) {
            const temp = source;
            source = result;
            result = temp;
        }
        applyRules(source, result);
        self.activeMatrix = result;
    }

    fn applyRules(source: *Matrix, result: *Matrix) void {
        for (0..source.size.y) |y| {
            for (0..source.size.x) |x| {
                const p = Vec2.fromUSize(x, y);
                const is_alive = source.getValue(p);
                const alive_neighbours = source.getActiveNeighboursCount(p);
                //log("{} - {}\n", .{ p, alive_neighbours });
                var outcome: bool = undefined;
                if (!is_alive and alive_neighbours >= 3) {
                    outcome = true;
                } else if (is_alive and (alive_neighbours == 2 or alive_neighbours == 3)) {
                    outcome = true;
                } else {
                    outcome = false;
                }
                result.setValue(p, outcome);
            }
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

const in_worldTick: f64 = 1.6;
const in_worldSize = Vec2{ .x = 40, .y = 20 };

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
