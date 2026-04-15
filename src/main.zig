const std = @import("std");
const scene_3d = @import("graphics/scene_3d.zig");
const Color = @import("graphics/color.zig");
const fs_utils = @import("fs_utils.zig");

const Scene = scene_3d.Scene;
const Camera = scene_3d.Camera;
const FillMethod = fs_utils.FillMethod;
const Gradient = Color.Gradient;
const print = std.debug.print;
const drawCircle = fs_utils.drawCircle;
const createImgFile = fs_utils.createImgFile;

const IMG_HEIGHT= 48;
const IMG_WIDTH = 64;
// const CIRCLE_CENTER_X = 128;
// const CIRCLE_CENTER_Y = 128;
// const CIRCLE_RADIUS = 64;

const IMG_OUT_PATHS: []const []const u8 = &.{"images", "output.ppm"};
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
    defer file.close(init.io);

    // print("File created succesfully.\n", .{});

    // const bg_color = Color {
    //     .r = 0,
    //     .g = 0,
    //     .b = 0
    // };

    // const fill = FillMethod {
    //     .gradient = Gradient(f32) {
    //         .start_color = .{.r = 110, .g = 225, .b = 225},
    //         .end_color   = .{.r = 240, .g = 200, .b = 20},
    //         .min_t = @floatFromInt(CIRCLE_CENTER_X - CIRCLE_RADIUS),
    //         .max_t = @floatFromInt(CIRCLE_CENTER_X + CIRCLE_RADIUS)
    //     }
    // };

    // try drawCircle(init.io, file, IMG_HEIGHT, IMG_WIDTH, CIRCLE_CENTER_X, CIRCLE_CENTER_Y, CIRCLE_RADIUS, fill, bg_color);
    // print("Circle succesfully drawn on file.\n", .{});

    // const header_size = comptime fs_utils.computePpmP6HeaderSize(255, IMG_WIDTH, IMG_HEIGHT);
    // var buf: [header_size + IMG_WIDTH * IMG_HEIGHT * 3]u8 = undefined;
    // var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    // const writer = &stdout_writer.interface;

    var buf: [1024]u8 = undefined;
    var file_writer = file.writer(init.io, &buf);
    const writer = &file_writer.interface;

    const scene = Scene {
        .camera = Camera.init(
            .{.x = 0.0, .y = 0.0, .z = 20.0},
            .{.x = 0.0, .y = 1.0, .z = 0.0},
            .{.x = 1.0, .y = 0.0, .z = 0.0},
            10.0),
        .sphere = Scene.Sphere {
            .center =  .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .radius = 5.0
        },
        .screen_height = IMG_HEIGHT,
        .screen_width = IMG_WIDTH
    };

    try fs_utils.writePpmP6Header(writer, 255, IMG_WIDTH, IMG_HEIGHT);
    try Scene.drawSphere(scene, writer);
}

test {
    _ = @import("math_utils.zig");
    _ = @import("fs_utils.zig");
    _ = @import("Vec3.zig");

    _ = @import("graphics/color.zig");
    _ = @import("graphics/scene_3d.zig");
}
