const std = @import("std");
const color = @import("color.zig");

const print = std.debug.print;
const Color = color.Color;
const Gradient = color.Gradient;

pub const FillMethod = union(enum) {
    color: Color,
    gradient: Gradient(f32)
};

pub fn drawCircle(io: std.Io, file: std.Io.File, img_height: u16, img_width: u16, center_x: u16, center_y: u16, radius: u16, fill: FillMethod, bg_color: Color) !void {
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
    return dir.createFile(io, sub_path, .{ .exclusive = true }) catch |err| switch (err) {
        error.FileNotFound => return try createDirAndFile(io, dir, sub_path),
        error.PathAlreadyExists => return try createFileWithSuffix(io, dir, sub_path),
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

fn createFileWithSuffix(io: std.Io, dir: std.Io.Dir, comptime sub_path: []const u8) !std.Io.File {
    const dirname = std.fs.path.dirname(sub_path).?;
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
