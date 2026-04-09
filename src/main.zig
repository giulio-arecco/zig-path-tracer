const std = @import("std");
const color = @import("color.zig");
const imgExporter = @import("imgExporter.zig");

const print = std.debug.print;
const drawCircle = imgExporter.drawCircle;
const createImgFile = imgExporter.createImgFile;
const FillMethod = imgExporter.FillMethod;
const Color = color.Color;
const Gradient = color.Gradient;

const IMG_HEIGHT= 512;
const IMG_WIDTH = 512;
const CIRCLE_CENTER_X = 128;
const CIRCLE_CENTER_Y = 128;
const CIRCLE_RADIUS = 64;

const IMG_OUT_PATHS = &[_][]const u8{"images", "output.ppm"};
const PATH_STR_LENGTH = computePathStrLen(IMG_OUT_PATHS);
const FILE_PATH = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(IMG_OUT_PATHS)});

fn computePathStrLen(comptime path_components: []const []const u8) usize {
    comptime var len: usize = 0;

    // Compute the total number of bytes that make up the path
    for (path_components) |component| {
        len += component.len;
    }

    len += path_components.len - 1; // Add the separator bytes
    return len;
}

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, FILE_PATH);
    print("File created succesfully.\n", .{});

    const bg_color = Color {
        .r = 0,
        .g = 0,
        .b = 0
    };

    const fill = FillMethod {
        .gradient = Gradient(f32) {
            .start_color = .{.r = 110, .g = 225, .b = 225},
            .end_color   = .{.r = 240, .g = 200, .b = 20},
            .min_t = @floatFromInt(CIRCLE_CENTER_X - CIRCLE_RADIUS),
            .max_t = @floatFromInt(CIRCLE_CENTER_X + CIRCLE_RADIUS)
        }
    };

    try drawCircle(init.io, file, IMG_HEIGHT, IMG_WIDTH, CIRCLE_CENTER_X, CIRCLE_CENTER_Y, CIRCLE_RADIUS, fill, bg_color);
    print("Circle succesfully drawn on file.\n", .{});
}
