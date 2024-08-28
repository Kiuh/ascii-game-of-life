const std = @import("std");
const clap = @import("clap");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const CORNER: u8 = '+';
const WALL: u8 = '|';
const FLOOR: u8 = '-';
const ACTIVE: u8 = '#';
const DISABLED: u8 = ' ';
const ascii_code = std.ascii.control_code;

const Vec2 = struct {
    x: u64,
    y: u64,

    pub fn toVec2i(self: Vec2) Vec2i {
        return .{ .x = @intCast(self.x), .y = @intCast(self.y) };
    }

    pub fn len(self: Vec2) u64 {
        return self.x * self.y;
    }
};

const Vec2i = struct {
    x: i64,
    y: i64,

    pub fn fromUSize(x: usize, y: usize) Vec2i {
        return Vec2i{ .x = @intCast(x), .y = @intCast(y) };
    }

    pub fn cycleFitInVec2(self: Vec2i, bounds: Vec2) Vec2 {
        return .{
            .x = cycleFitInU64(self.x, bounds.x),
            .y = cycleFitInU64(self.y, bounds.y),
        };
    }
};

pub fn cycleFitInU64(target: i64, bound: u64) u64 {
    if (target < 0) {
        return cycleFitInU64(target + @as(i64, @intCast(bound)), bound);
    } else if (target >= bound) {
        return cycleFitInU64(target - @as(i64, @intCast(bound)), bound);
    } else {
        return @as(u64, @intCast(target));
    }
}

const Matrix = struct {
    list: ArrayList(bool),
    size: Vec2,

    pub fn init(allocator: Allocator, size: Vec2) !Matrix {
        var matrix = Matrix{
            .size = size,
            .list = ArrayList(bool).init(allocator),
        };
        try matrix.fillWithFalse();
        return matrix;
    }

    pub fn deinit(self: *Matrix) void {
        self.list.deinit();
    }

    pub fn fillWithFalse(self: *Matrix) !void {
        for (0..self.size.len()) |_| {
            try self.list.append(false);
        }
    }

    pub fn getValue(self: *Matrix, p: Vec2i) bool {
        const u_p = p.cycleFitInVec2(self.size);
        return self.list.items[u_p.x + u_p.y * self.size.x];
    }

    pub fn setValue(self: *Matrix, p: Vec2i, value: bool) void {
        const u_p = p.cycleFitInVec2(self.size);
        self.list.items[u_p.x + u_p.y * self.size.x] = value;
    }

    pub fn getActiveNeighboursCount(self: *Matrix, p: Vec2i) u8 {
        var counter: u8 = 0;
        for (0..3) |y_i| {
            for (0..3) |x_i| {
                if (x_i == 1 and y_i == 1) {
                    continue;
                }

                const pos = Vec2i{
                    .x = p.x + @as(i64, @intCast(x_i)) - 1,
                    .y = p.y + @as(i64, @intCast(y_i)) - 1,
                };

                if (self.getValue(pos)) {
                    counter += 1;
                }
            }
        }
        return counter;
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
    tps: u64,
    size: Vec2,
    worldMatrix1: Matrix = undefined,
    worldMatrix2: Matrix = undefined,
    activeMatrix: *Matrix = undefined,
    generation: u64 = 0,

    pub fn init(allocator: Allocator, file: std.fs.File, tps: u64, size: Vec2) !Game {
        return Game{
            .allocator = allocator,
            .file = file,
            .tps = tps,
            .size = size,
        };
    }

    pub fn deinit(self: *Game) !void {
        self.worldMatrix1.deinit();
        self.worldMatrix2.deinit();
    }

    fn initMatrices(self: *Game) !void {
        self.worldMatrix1 = try Matrix.init(self.allocator, self.size);
        self.worldMatrix2 = try Matrix.init(self.allocator, self.size);
        self.activeMatrix = &self.worldMatrix1;
    }

    fn setCreationData(self: *Game, creation_data: WorldCreationData) void {
        if (creation_data.isRandom) {
            self.activeMatrix.setRandomBools();
        } else {
            for (creation_data.entries) |value| {
                self.activeMatrix.setValue(value.toVec2i(), true);
            }
        }
    }

    pub fn run(self: *Game, time: u64, creation_data: WorldCreationData) !void {
        try self.initMatrices();
        self.setCreationData(creation_data);

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
        var chars = ArrayList(u8).init(self.allocator);
        defer chars.deinit();

        try self.addClearConsole(&chars);
        try self.addWorld(&chars);
        try self.addAddictionalInfo(&chars);

        try self.print("{s}", .{chars.items});

        const utf16le = "😎 hello! 😎";

        var writer = std.io.getStdOut().writer();
        var it = std.unicode.Utf16LeIterator.init(utf16le);
        while (try it.nextCodepoint()) |codepoint| {
            var buf: [4]u8 = [_]u8{undefined} ** 4;
            const len = try std.unicode.utf8Encode(codepoint, &buf);
            try writer.writeAll(buf[0..len]);
        }

        try self.calculateNextStep();

        const seconds_part = @as(f64, (1 / @as(f64, @floatFromInt(self.tps))));
        const ticks_part = @as(f64, @floatFromInt(std.time.ns_per_s));
        const sleep_time: u64 = @intFromFloat(seconds_part * ticks_part);
        std.time.sleep(sleep_time);
        return sleep_time;
    }

    fn addAddictionalInfo(self: *Game, chars: *ArrayList(u8)) !void {
        try self.appendFormat(chars, "Generation: {} \n", .{self.generation});
        try self.appendFormat(chars, "Tps: {} \n", .{self.tps});
    }

    fn addWorld(self: *Game, chars: *ArrayList(u8)) !void {

        //Top of vignette
        try appendVignetteLine(chars, self.size.x);

        for (0..self.size.y) |y| {
            // Left wall
            try chars.append(WALL);

            // Content
            for (0..self.size.x) |x| {
                const p = Vec2i.fromUSize(x, y);
                const char = if (self.activeMatrix.getValue(p)) ACTIVE else DISABLED;
                try chars.append(char);
            }

            // Right wall
            try chars.append(WALL);

            try appendEndl(chars);
        }

        //Bottom of vignette
        try appendVignetteLine(chars, self.size.x);
    }

    fn appendVignetteLine(chars: *ArrayList(u8), width: u64) !void {
        try chars.append(CORNER);
        try chars.appendNTimes(FLOOR, width);
        try chars.append(CORNER);
        try appendEndl(chars);
    }

    fn appendEndl(chars: *ArrayList(u8)) !void {
        try chars.append(ascii_code.cr);
        try chars.append(ascii_code.lf);
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
                const pos = Vec2i.fromUSize(x, y);

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

    fn addClearConsole(self: *Game, chars: *ArrayList(u8)) !void {
        try self.appendFormat(chars, "{c}[0;0H{c}[J", .{ ascii_code.esc, ascii_code.esc });
    }

    fn appendFormat(self: *Game, chars: *ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
        const buffer = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(buffer);
        try chars.appendSlice(buffer);
    }

    fn print(self: *Game, comptime fmt: []const u8, args: anytype) !void {
        const buffer = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(buffer);
        _ = try self.file.writer().write(buffer);
    }
};

const WorldCreationData = struct {
    isRandom: bool,
    entries: []const Vec2 = &.{},
};

const InitMode = enum { random, flyer };

const flyer_world_data = WorldCreationData{
    .isRandom = false,
    .entries = &.{
        .{ .x = 1, .y = 0 },
        .{ .x = 2, .y = 1 },
        .{ .x = 0, .y = 2 },
        .{ .x = 1, .y = 2 },
        .{ .x = 2, .y = 2 },
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Init clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-t, --tps <INT>        Sets world ticks per second [default = 20].
        \\                       Example: -t 60
        \\-s, --size <STR>       Sets size of the world [default = 80 x 40].
        \\                       Example: -s 100-50
        \\-m, --mode <MODE>      Sets world creation mode random or flyer [default = random].
        \\                       Example: -m flyer
        \\-d, --duration <INT>   Sets game duration in seconds, 0 means infinity [default = 0].
        \\                       Example: -d 10
    );
    const parsers = comptime .{
        .INT = clap.parsers.int(u64, 10),
        .STR = clap.parsers.string,
        .MODE = clap.parsers.enumeration(InitMode),
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(
        clap.Help,
        &params,
        parsers,
        .{
            .diagnostic = &diag,
            .allocator = allocator,
        },
    ) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // Process help argument
    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // Prepare data
    var tps: u64 = 20;
    var size = Vec2{ .x = 80, .y = 40 };
    const file = std.io.getStdOut();
    var creation_data = WorldCreationData{ .isRandom = true };
    var duration: u64 = 0;

    // Process other arguments
    if (res.args.tps) |value| {
        tps = value;
    }

    if (res.args.mode) |value| {
        switch (value) {
            .flyer => {
                creation_data = flyer_world_data;
            },
            else => {},
        }
    }

    if (res.args.size) |str| {
        var it = std.mem.splitAny(u8, str, "-");
        if (it.next()) |val|
            size.x = try std.fmt.parseInt(u64, val, 10);
        if (it.next()) |val|
            size.y = try std.fmt.parseInt(u64, val, 10);
    }

    if (res.args.duration) |val| {
        duration = val;
    }

    // Init game
    var game = try Game.init(allocator, file, tps, size);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    // Run game
    try game.run(duration, creation_data);
}

test "memory-leak-test" {
    const tps = 60;
    const size = Vec2{ .x = 5, .y = 5 };
    const allocator = std.testing.allocator;
    const file_name = "test_file.txt";
    const file = try std.fs.cwd().createFile(
        file_name,
        .{ .read = true },
    );
    defer file.close();
    defer std.fs.cwd().deleteFile(file_name) catch |err| {
        std.debug.panic("Cannot delete file!\n{any}", .{err});
    };

    var game = try Game.init(allocator, file, tps, size);
    defer game.deinit() catch |err| {
        std.debug.panic("Panic while deinit game!\n{any}", .{err});
    };

    try game.run(1, flyer_world_data);
}
