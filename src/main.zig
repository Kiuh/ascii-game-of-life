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

    pub fn setValueRaw(self: *Matrix, i: usize, value: bool) void {
        self.list.items[i] = value;
    }

    pub fn getActiveNeighboursCount(self: *Matrix, p: Vec2) u8 {
        var counter: u8 = 0;
        for (0..3) |y_i| {
            for (0..3) |x_i| {
                if ((p.x == 0 and x_i == 0) or (p.y == 0 and y_i == 0) or (x_i == 1 and y_i == 1)) {
                    continue;
                }

                const pos = Vec2{
                    .x = p.x + x_i - 1,
                    .y = p.y + y_i - 1,
                };

                if (self.isValid(pos) and self.getValue(pos)) {
                    counter += 1;
                }
            }
        }
        return counter;
    }

    fn isValid(self: *Matrix, p: Vec2) bool {
        return p.x < self.size.x and p.y < self.size.y;
    }

    fn fillList(self: *Matrix) !void {
        for (0..self.size.len()) |_| {
            try self.list.append(false);
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
    fps: f64,
    initWorldData: WorldData,
    worldMatrix1: Matrix = undefined,
    worldMatrix2: Matrix = undefined,
    activeMatrix: *Matrix = undefined,
    generation: u64 = 0,

    pub fn init(allocator: Allocator, file: std.fs.File, fps: f64, data: WorldData) !Game {
        var game = Game{
            .allocator = allocator,
            .file = file,
            .fps = fps,
            .initWorldData = data,
        };

        try game.initMatrices();
        game.setRandomWorld();
        //game.setInitData();
        return game;
    }

    fn initMatrices(self: *Game) !void {
        self.worldMatrix1 = try Matrix.init(self.allocator, self.initWorldData.size);
        self.worldMatrix2 = try Matrix.init(self.allocator, self.initWorldData.size);
        self.activeMatrix = &self.worldMatrix1;
    }

    fn setInitData(self: *Game) void {
        for (self.initWorldData.entries) |value| {
            self.activeMatrix.setValue(value, true);
        }
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
        try self.printGenerationNumber();
        try self.calculateNextStep();
        const sleep_time: u64 = @intFromFloat(@as(f64, (1 / self.fps)) * @as(f64, @floatFromInt(std.time.ns_per_s)));
        std.time.sleep(sleep_time);
        return sleep_time;
    }

    fn printGenerationNumber(self: *Game) !void {
        try self.print("Generation: {}\n", .{self.generation});
    }

    fn printWorld(self: *Game) !void {
        var chars = ArrayList(u8).init(self.allocator);
        defer chars.deinit();

        for (0..self.initWorldData.size.y) |y| {
            for (0..self.initWorldData.size.x) |x| {
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
        self.generation += 1;
    }

    fn applyRules(source: *Matrix, result: *Matrix) void {
        for (0..source.size.y) |y| {
            for (0..source.size.x) |x| {
                const pos = Vec2.fromUSize(x, y);

                const is_alive = source.getValue(pos);
                const alive_neighbours = source.getActiveNeighboursCount(pos);
                var outcome: bool = false;

                if (is_alive and (alive_neighbours == 2 or alive_neighbours == 3)) {
                    outcome = true;
                } else if (alive_neighbours == 3) {
                    outcome = true;
                }

                result.setValue(pos, outcome);
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

const WorldData = struct {
    size: Vec2,
    entries: []const Vec2,
};

const in_fps: f64 = 2;
const in_initWorldData = WorldData{ .size = .{ .x = 80, .y = 40 }, .entries = &.{
    .{ .x = 1, .y = 0 },
    .{ .x = 2, .y = 1 },
    .{ .x = 0, .y = 2 },
    .{ .x = 1, .y = 2 },
    .{ .x = 2, .y = 2 },
} };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const in_file = std.io.getStdOut();

    var game = try Game.init(allocator, in_file, in_fps, in_initWorldData);
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

    var game = try Game.init(allocator, in_file, in_fps, in_initWorldData);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    try game.run(100);
}
