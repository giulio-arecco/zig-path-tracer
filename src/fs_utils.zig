const std = @import("std");
const color = @import("graphics/color.zig");

const print = std.debug.print;
const Color = color.Color;
const Gradient = color.Gradient;

pub const FillMethod = union(enum) {
    color: Color,
    gradient: Gradient(f32)
};

pub fn computePpmP6HeaderSize(comptime max_size: u16, comptime img_width: usize, comptime img_height: usize) usize {
    return std.fmt.count("P6\n{d} {d}\n{d}\n", .{ img_width, img_height, max_size });
}

/// Writes on the passed in file to create a circle in the PPM P6 image format
pub fn drawCircle(io: std.Io, file: std.Io.File, img_height: u16, img_width: u16, center_x: u16, center_y: u16, radius: u16, fill: FillMethod, bg_color: Color) !void {
    std.debug.assert(radius > 0);
    std.debug.assert(img_height > 0);
    std.debug.assert(img_width > 0);

    const int_type = isize;

    const img_half_height = img_height / 2;
    const img_half_width = img_width / 2;

    const int_rad = @as(int_type, radius);
    const x_c = @as(int_type, center_x);
    const y_c = @as(int_type, center_y);
    const rad_2 = int_rad * int_rad;

    const bg_color_packed = bg_color.toPacked();

    var buf: [1024]u8 = undefined;
    var file_writer = file.writer(io, &buf);
    const writer = &file_writer.interface;

    // Write the ppm file header
    try writer.print("P6\n{d} {d}\n255\n", .{img_width, img_height});

    for(0..img_height) |i| {
        const y= img_half_height - @as(int_type, @intCast(i)); // y is in range (-img_half_height, img_half_height]
        const y_2 = (y - y_c) * (y - y_c);

        for (0..img_width) |j| {
            const x= @as(int_type, @intCast(j)) - img_half_width; // x is in range [-img_half_width, img_half_width)
            const x_2 = (x - x_c) * (x - x_c);


            if (x_2 + y_2 > rad_2) {
                try writer.writeInt(u24, bg_color_packed, .big);
            }
            else {
                switch (fill) {
                    .color => |c| try writer.writeInt(u24, c.toPacked(), .big),
                    .gradient => |g| try writer.writeInt(u24, try g.evalPacked(@floatFromInt(x)), .big)
                }
            }
        }
    }

    try writer.flush();
}

// ==========================================================================================================================
// The "createImgFile" and "createFileWithSuffix" functions receive the sub_path slice as a comptime argument as they aren't
// used in an interactive scenario. This allows us to determine the length of "buf" in the "createFileWithSuffix" function at
// compile time, thereby avoiding the need to allocate it dinamically or oversize it.
// ==========================================================================================================================

pub fn createImgFile(io: std.Io, dir: std.Io.Dir, comptime sub_path: []const u8) !std.Io.File {
    if (sub_path.len == 0) @compileError("sub_path cannot be empty");

    return dir.createFile(io, sub_path, .{ .exclusive = true }) catch |err| switch (err) {
        error.FileNotFound => return try createDirAndFile(io, dir, sub_path),
        error.PathAlreadyExists => return try createFileWithSuffix(io, dir, sub_path),
        else => |e| return e
    };
}

fn createDirAndFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !std.Io.File {
    std.debug.assert(sub_path.len > 0);

    if (std.fs.path.dirname(sub_path)) |dirname| {
        try dir.createDirPath(io, dirname);
        return try dir.createFile(io, sub_path, .{ .exclusive = true });
    }

    return error.BadPathName;
}

fn createFileWithSuffix(io: std.Io, dir: std.Io.Dir, comptime sub_path: []const u8) !std.Io.File {
    if (sub_path.len == 0) @compileError("sub_path cannot be empty");

    const dirname = std.fs.path.dirname(sub_path) orelse ".";
    var file_dir = try dir.openDir(io, dirname, .{ .iterate = true });
    defer file_dir.close(io);

    // The next two slices are computed at compile time to use them later in the definition of buf
    const filename = comptime std.fs.path.stem(sub_path);
    const filext = comptime std.fs.path.extension(sub_path);

    var dir_iter = file_dir.iterate();
    var top_idx: u16 = 0;
    while (try dir_iter.next(io)) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.startsWith(u8, entry.name, filename) and std.mem.endsWith(u8, entry.name, filext)) {
            var idx: @TypeOf(top_idx) = 0;
            const idx_str = entry.name[filename.len .. entry.name.len - filext.len];

            if (idx_str.len != 0) {
                idx = std.fmt.parseInt(@TypeOf(idx), idx_str, 10) catch continue;
            }

            idx += 1;

            if (idx > top_idx) top_idx = idx;
        }
    }

    const max_idx_str = std.fmt.comptimePrint("{d}", .{ std.math.maxInt(@TypeOf(top_idx)) });
    var buf: [filename.len + max_idx_str.len + filext.len]u8 = undefined;
    const filename_with_suffix = try std.fmt.bufPrint(&buf, "{s}{d}{s}", .{ filename, top_idx, filext });

    return try file_dir.createFile(io, filename_with_suffix, .{ .exclusive = true });
}

test "Compute PPM P6 header size" {
    try std.testing.expectEqual(9, computePpmP6HeaderSize(1, 1, 1));
    try std.testing.expectEqual(10, computePpmP6HeaderSize(1, 1, 10));
    try std.testing.expectEqual(11, computePpmP6HeaderSize(1, 10, 10));
    try std.testing.expectEqual(14, computePpmP6HeaderSize(1, 100, 1000));
    try std.testing.expectEqual(10, computePpmP6HeaderSize(10, 1, 1));
    try std.testing.expectEqual(11, computePpmP6HeaderSize(10, 1, 10));
    try std.testing.expectEqual(12, computePpmP6HeaderSize(10, 10, 10));
    try std.testing.expectEqual(15, computePpmP6HeaderSize(10, 100, 1000));
    try std.testing.expectEqual(11, computePpmP6HeaderSize(100, 1, 1));
    try std.testing.expectEqual(12, computePpmP6HeaderSize(100, 1, 10));
    try std.testing.expectEqual(13, computePpmP6HeaderSize(100, 10, 10));
    try std.testing.expectEqual(16, computePpmP6HeaderSize(100, 100, 1000));
    try std.testing.expectEqual(12, computePpmP6HeaderSize(1000, 1, 1));
    try std.testing.expectEqual(13, computePpmP6HeaderSize(1000, 1, 10));
    try std.testing.expectEqual(14, computePpmP6HeaderSize(1000, 10, 10));
    try std.testing.expectEqual(17, computePpmP6HeaderSize(1000, 100, 1000));
}

test "Create dir and file" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const s = std.fs.path.sep_str;

    const p1 = "test1.tst";
    try std.testing.expectError(error.BadPathName, createDirAndFile(io, dir, p1));

    const p2 = "." ++ s ++ "test2.tst";
    const f2 = try createDirAndFile(io, dir, p2);
    f2.close(io);

    try dir.access(io, p2, .{});

    const p3 = "testDir1" ++ s ++ "test3.tst";
    const f3 = try createDirAndFile(io, dir, p3);
    f3.close(io);

    try dir.access(io, p3, .{});

    const p4 = "testDir1" ++ s ++ ".." ++ s ++ "test4.tst";
    const f4 = try createDirAndFile(io, dir, p4);
    f4.close(io);

    try dir.access(io, p4, .{});

    const p5 = "testDir1" ++ s ++ "." ++ s ++ ".." ++ s ++ "test5.tst";
    const f5 = try createDirAndFile(io, dir, p5);
    f5.close(io);

    try dir.access(io, p5, .{});

    const p6 = "testDir1" ++ s ++ "testDir2" ++ s ++ "test6.tst";
    const f6 = try createDirAndFile(io, dir, p6);
    f6.close(io);

    try dir.access(io, p6, .{});
}

test "Create file with suffix" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const filename = "output.ppm";

    const first = try createFileWithSuffix(io, dir, filename);
    first.close(io);

    const firstStat = try dir.statFile(io, "output0.ppm", .{});
    try std.testing.expectEqual(0, firstStat.size);

    const second = try createFileWithSuffix(io, dir, filename);
    second.close(io);

    const secondStat = try dir.statFile(io, "output1.ppm", .{});
    try std.testing.expectEqual(0, secondStat.size);

    const third = try createFileWithSuffix(io, dir, filename);
    third.close(io);

    const thirdStat = try dir.statFile(io, "output2.ppm", .{});
    try std.testing.expectEqual(0, thirdStat.size);
}


test "Create image file - No error to handle" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const sub_path = "output.ppm";

    const file = try createImgFile(io, dir, sub_path);
    file.close(io);

    const stat = try dir.statFile(io, sub_path, .{});
    try std.testing.expectEqual(0, stat.size);
}

test "Create image file - Handle FileNotFound" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const sub_path = "testing" ++ std.fs.path.sep_str ++ "output.ppm";

    const file = try createImgFile(io, dir, sub_path);
    file.close(io);

    try dir.access(io, "testing", .{});
    const stat = try dir.statFile(io, sub_path, .{});
    try std.testing.expectEqual(0, stat.size);
}

test "Create image file - Handle PathAlreadyExists" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{ .iterate = true });
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const filename = "output.ppm";

    const first = try std.Io.Dir.createFile(dir, io, filename, .{});
    first.close(io);

    const second = try createImgFile(io, dir, filename);
    second.close(io);

    const secondStat = try dir.statFile(io, "output1.ppm", .{});
    try std.testing.expectEqual(0, secondStat.size);
}

test "Draw circle on file" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{});
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const sub_path = "output.ppm";

    const file = try dir.createFile(io, sub_path, .{ .read = true});
    defer file.close(io);

    const img_height = 3;
    const img_width = 3;
    const fill = FillMethod { .color = Color {.r = 255, .g = 255, .b = 255 } };
    const bg = Color {.r = 0, .g = 0, .b = 0 };

    try drawCircle(io, file, img_height, img_width, 0, 0, 1, fill, bg);

    const stat = try file.stat(io);
    const header_length = 11;
    try std.testing.expectEqual(header_length + img_height * img_width * 3, stat.size);

    const bufsize = img_height * img_width * 3;
    var buf: [bufsize]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    try file_reader.seekTo(header_length);
    const reader = &file_reader.interface;

    const rgb_data = try reader.take(bufsize);

    try std.testing.expectEqual(0, reader.bufferedLen());
    try std.testing.expectEqualSlices(u8, &.{
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        }, rgb_data);
}
