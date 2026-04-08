const std = @import("std");
const color = @import("color.zig");

const print = std.debug.print;
const Color = color.Color;
const Gradient = color.Gradient;

const IMG_HEIGHT= 512;
const IMG_WIDTH = 512;
const CIRCLE_CENTER_X = 128;
const CIRCLE_CENTER_Y = 128;
const CIRCLE_RADIUS = 64;

const IMG_OUT_NAME = "output";
const IMG_OUT_EXT = ".ppm";
const IMG_OUT_PATHS = &[_][]const u8{"images", IMG_OUT_NAME ++ IMG_OUT_EXT};

pub fn main(init: std.process.Init) !void {
    try savePpmCircle(init.io, init.gpa, IMG_HEIGHT, IMG_WIDTH, CIRCLE_CENTER_X, CIRCLE_CENTER_Y, CIRCLE_RADIUS);
    print("Output file created successfully.\n", .{});
}

/// Writes on disk an image of a circle in the PPM P6 format
fn savePpmCircle(io: std.Io, allocator: std.mem.Allocator, img_height: u16, img_width: u16, center_x: u16, center_y: u16, radius: u16) !void {
    const int_type = isize;

    const img_half_height = img_height / 2;
    const img_half_width = img_width / 2;
    const int_rad = @as(int_type, radius);
    const rad_2 = int_rad * int_rad;
    const x_c = @as(int_type, center_x);
    const y_c = @as(int_type, center_y);

    const gradient = Gradient(f32) {
        .start_color = .{.r = 110, .g = 225, .b = 225},
        .end_color   = .{.r = 240, .g = 200, .b = 20},
        .min_t = @floatFromInt(x_c - int_rad),
        .max_t = @floatFromInt(x_c + int_rad)
    };
    const bg_color = Color {.r = 0, .g = 0, .b = 0};

    const file = try createPpmFile(io, allocator, IMG_OUT_PATHS);
    defer file.close(io);

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
                try writer.writeInt(u24, bg_color.toPacked(), .big);
            }
            else {
                try writer.writeInt(u24, try gradient.evalPacked(@floatFromInt(x)), .big);
            }
        }
    }

    try writer.flush();
}

fn createPpmFile(io: std.Io, allocator: std.mem.Allocator, paths_to_file: []const []const u8) !std.Io.File {
    const cwd = std.Io.Dir.cwd();

    const path = try std.fs.path.resolve(allocator, paths_to_file);
    defer allocator.free(path);

    return cwd.createFile(io, path, .{ .exclusive = true }) catch |err| switch (err) {
        error.FileNotFound => return try createDirAndFile(io, cwd, path),
        error.PathAlreadyExists => return try createFileWithSuffix(io, cwd, path),
        else => |e| return e
    };
}

fn createDirAndFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !std.Io.File {
    if (std.fs.path.dirname(sub_path)) |dirname| {
        try dir.createDirPath(io, dirname);
        print("Successfully created the \"{s}\" directory.\n", .{dirname});

        return try dir.createFile(io, sub_path, .{ .exclusive = true });
    }

    return error.FileNotFound;
}

fn createFileWithSuffix(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !std.Io.File {
    const dirname = std.fs.path.dirname(sub_path).?;
    var file_dir = try dir.openDir(io, dirname, .{ .iterate = true });
    defer file_dir.close(io);

    var iterator = file_dir.iterate();
    var top_idx: u16 = 0;
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.startsWith(u8, entry.name, IMG_OUT_NAME) and std.mem.endsWith(u8, entry.name, IMG_OUT_EXT)) {
            var idx: @TypeOf(top_idx) = 0;
            const idx_str = entry.name[IMG_OUT_NAME.len .. entry.name.len - IMG_OUT_EXT.len];

            if (idx_str.len != 0) {
                idx = std.fmt.parseInt(@TypeOf(idx), idx_str, 10) catch continue;
            }

            idx += 1;

            if (idx > top_idx) top_idx = idx;
        }
    }

    const max_idx_str = std.fmt.comptimePrint("{d}", .{ std.math.maxInt(@TypeOf(top_idx)) });
    var buf: [IMG_OUT_NAME.len + max_idx_str.len + IMG_OUT_EXT.len]u8 = undefined;
    const filename = try std.fmt.bufPrint(&buf, "{s}{d}{s}", .{ IMG_OUT_NAME, top_idx, IMG_OUT_EXT });

    return try file_dir.createFile(io, filename, .{ .exclusive = true });
}

fn printCircle(io: std.Io, comptime out_height: u16, comptime out_width: u16, radius: u16) !void {
    const out_size_with_nl = out_height * out_width + out_height;
    const half_out_height = @as(isize, out_height / 2);
    const half_out_width = @as(isize, out_width / 2);
    const int_rad = @as(isize, radius);
    const rad_2 = int_rad * int_rad;


    var out_buffer: [out_size_with_nl]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const stdout = &stdout_writer.interface;

    for(0..out_height) |i| {
        const y= @as(isize, @intCast(i)) - half_out_height; // y is in range [-half_out_height, half_out_height)
        const y_2 = y * y;

        for (0..out_width) |j| {
            const x= @as(isize, @intCast(j)) - half_out_width; // x is in range [-half_out_width, half_out_width)
            const x_2 = x * x;


            if (x_2 + y_2 > rad_2) {
                try stdout.writeByte('x');
            }
            else {
                try stdout.writeByte('.');
            }
        }

        try stdout.writeByte('\n');
    }

    try stdout.flush();
}

fn greetUser(io: std.Io) !void {
    var in_buffer: [128]u8 = undefined;
    var out_buffer: [128]u8 = undefined;

    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &out_buffer);
    const stdout = &stdout_writer.interface;

    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    const stdin = &stdin_reader.interface;

    try stdout.writeAll("Insert your name here: ");
    try stdout.flush();

    const input = try stdin.takeDelimiterExclusive('\n');
    const name = std.mem.trimEnd(u8, input, &std.ascii.whitespace);

    try stdout.print("Hi {s}!\n", .{name});
    try stdout.flush();
}
