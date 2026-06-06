//! Platform-agnostic file system wrappers ensuring predictable I/O execution, isolated from OS specifics.

const std = @import("std");
const type_utils = @import("type_utils.zig");

const Color = @import("graphics/Color.zig");
const Gradient = Color.Gradient;

const print = std.debug.print;
const assertAnytypeHasDecls = type_utils.assertAnytypeHasDecls;


fn computePathStrLen(comptime path_components: []const []const u8) usize {
    comptime var len: usize = 0;

    // Compute the total number of bytes that make up the path
    inline for (path_components) |component| {
        len += component.len;
    }

    len += path_components.len - 1; // Add the separator bytes
    return len;
}

/// Evaluates the total byte length a given format configuration will demand when flushed to the header section of a PPM P6 output block .
pub fn computePpmP6HeaderSize(max_size: u16, img_width: usize, img_height: usize) usize {
    return std.fmt.count("P6\n{d} {d}\n{d}\n", .{ img_width, img_height, max_size });
}

/// Writes standard PPM P6 header bytes.
pub fn writePpmP6Header(writer: anytype, max_size: u16, img_width: usize, img_height: usize) !void {
    assertAnytypeHasDecls(writer, &.{ "print", "flush" });

    try writer.print("P6\n{d} {d}\n{d}\n", .{img_width, img_height, max_size});
    try writer.flush();
}

// The "createImgFile" and "createFileWithSuffix" functions receive `sub_path` as a comptime slice to enable static bounds
// tracking on formatted strings, resolving internal buffers capacities at compile-time and circumventing a dynamic heap allocator pipeline entirely.

/// Creates an image file on disk.
/// Checks for naming collisions and auto-appends numerical increments to prevent overwriting existing files.
/// Returns a file handle in exclusive write ownership mode to the caller.
pub fn createImgFile(io: std.Io, dir: std.Io.Dir, comptime sub_path: []const u8) !std.Io.File {
    if (sub_path.len == 0) @compileError("sub_path cannot be empty");

    return dir.createFile(io, sub_path, .{ .exclusive = true, .read = true }) catch |err| switch (err) {
        error.FileNotFound => return try createDirAndFile(io, dir, sub_path),
        error.PathAlreadyExists => return try createFileWithSuffix(io, dir, sub_path),
        else => |e| return e
    };
}

/// Resolves sequential directory hierarchies on demand before placing the leaf file.
/// Assumes the caller has exhaustively stripped invalid path tokens on their end.
fn createDirAndFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !std.Io.File {
    std.debug.assert(sub_path.len > 0);

    if (std.fs.path.dirname(sub_path)) |dirname| {
        try dir.createDirPath(io, dirname);
        return try dir.createFile(io, sub_path, .{ .exclusive = true, .read = true });
    }

    return error.BadPathName;
}

/// Determines the maximum integer suffix currently on disk for the leaf file name and creates a file using the next available suffix.
/// Allocates bounding buffer capacities strictly using comptime variables.
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

    return try file_dir.createFile(io, filename_with_suffix, .{ .exclusive = true, .read = true });
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

test "Write PPM P6 header" {
    const io = std.testing.io;
    var tmpDir = std.testing.tmpDir(.{});
    defer tmpDir.cleanup();
    const dir = tmpDir.dir;

    const sub_path = "output_header.ppm";

    const file = try dir.createFile(io, sub_path, .{ .read = true });
    defer file.close(io);

    var write_buf: [32]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);

    var read_buf: [32]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);
    var reader = &file_reader.interface;

    try writePpmP6Header(&file_writer.interface, 255, 800, 600);

    const stat = try file.stat(io);
    const ex_1 = "P6\n800 600\n255\n";
    try std.testing.expectEqual(ex_1.len, stat.size);

    try file_reader.seekTo(0);
    var data = try reader.take(ex_1.len);
    try std.testing.expectEqualStrings(ex_1, data);

    try file_writer.seekTo(0);
    try writePpmP6Header(&file_writer.interface, 0, 0, 0);

    try file_reader.seekTo(0);
    const ex_2 = "P6\n0 0\n0\n";
    data = try reader.take(ex_2.len);
    try std.testing.expectEqualStrings(ex_2, data);

    try file_writer.seekTo(0);
    try writePpmP6Header(&file_writer.interface, std.math.maxInt(u16), 123456, 987654);

    try file_reader.seekTo(0);
    const ex_3 = "P6\n123456 987654\n65535\n";
    data = try reader.take(ex_3.len);
    try std.testing.expectEqualStrings(ex_3, data);
}

test "computePathStrLen" {
    try std.testing.expectEqual(3, computePathStrLen(&.{"foo"}));
    try std.testing.expectEqual(7, computePathStrLen(&.{"foo", "bar"}));
    try std.testing.expectEqual(5, computePathStrLen(&.{"a", "b", "c"}));
    try std.testing.expectEqual(12, computePathStrLen(&.{"usr", "bin", "bash"}));
}
