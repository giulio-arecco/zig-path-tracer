const std = @import("std");
const graphics = @import("graphics.zig");
const fs_utils = @import("fs_utils.zig");
const config = @import("config.zig");
const rendering = graphics.scene_3d.rendering;
const raytracing = rendering.raytracing;
const materials = graphics.scene_3d.materials;

const Scene = graphics.scene_3d.Scene;
const Camera = graphics.scene_3d.Camera;
const RenderSettings = rendering.RenderSettings;
const RayTracer = raytracing.RayTracer;
const ParallelRayTracer = raytracing.ParallelRayTracer;
const Material = materials.Material;
const Float = config.Float;

const print = std.debug.print;
const drawCircle = fs_utils.drawCircle;
const createImgFile = fs_utils.createImgFile;
const computePathStrLen = fs_utils.computePathStrLen;

const IMG_HEIGHT= 1024;
const IMG_WIDTH = 1024;

const IMG_OUT_PATHS: []const []const u8 = &.{"images", "output.ppm"};
const PATH_STR_LENGTH = computePathStrLen(IMG_OUT_PATHS);
const FILE_PATH = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(IMG_OUT_PATHS)});
const PPM_HEADER_LEN = fs_utils.computePpmP6HeaderSize(255, IMG_WIDTH, IMG_HEIGHT);

const TRACK_PROGRESS = true;

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, FILE_PATH);
    defer file.close(init.io);

    const root_node: ?std.Progress.Node = if (TRACK_PROGRESS) std.Progress.start(init.io, .{}) else null;
    defer if (root_node) |n| n.end();

    var memory_map = blk: {
        try file.setLength(init.io, PPM_HEADER_LEN + IMG_HEIGHT * IMG_WIDTH * 3);
        const stat = try file.stat(init.io);

        break :blk try file.createMemoryMap(init.io, .{.len = stat.size });
    };
    defer memory_map.destroy(init.io);

    const render_settings = RenderSettings {
            .image_width = IMG_WIDTH,
            .image_height = IMG_HEIGHT,
            .ray_tmin = 0.001, // Avoid 0.0 to prevent shadow acne
            .ray_tmax = std.math.inf(Float),
            .max_ray_bounces = 10,
            .samples_per_pixel = 50,
            .pixel_samples_scale = 0.02, // 1/samples_per_pixel
    };

    const mat_center = Material { .lambertian = .{ .albedo = .init(0.1, 0.2, 0.5) } };
    const mat_ground = Material { .lambertian = .{ .albedo = .init(0.8, 0.8, 0.0) } };
    const mat_metal_1 = Material { .metal = .{ .albedo = .init(0.8, 0.8, 0.8), .fuzz = 0.0 } };
    const mat_metal_2 = Material { .metal = .{ .albedo = .init(0.8, 0.6, 0.2), .fuzz = 0.25 } };
    const mat_metal_3 = Material { .metal = .{ .albedo = .init(0.0, 0.4, 0.65), .fuzz = 0.5} };
    const mat_metal_4 = Material { .metal = .{ .albedo = .init(0.35, 0.0, 0.65), .fuzz = 0.75 } };
    const mat_glass_outer = Material { .dielectic = .{ .refractive_index = 1.5 } }; // outer glass sphere
    const mat_glass_inner = Material { .dielectic = .{ .refractive_index = 1.0 / 1.5 } }; // inner air sphere

    const scene = Scene {
        .camera = Camera.init(
            .{.x = 0.0, .y = 4.0, .z = 20.0},
            .{.x = 0.0, .y = 1.0, .z = 0.0},
            .{.x = 1.0, .y = 0.0, .z = 0.0},
            10.0,
            90.0,
            render_settings
        ),
        .hittables = &.{
            .{
                .sphere = .{ // center
                    .center =  .{ .x = 0.0, .y = 10.0, .z = 0.0 },
                    .radius = 5.0,
                    .material = mat_center
                }
            },
            .{
                .sphere = .{ // ground
                    .center =  .{ .x = 0.0, .y = -1003.0, .z = 0.0 },
                    .radius = 1000.0,
                    .material = mat_ground
                }
            },
            .{
                .sphere = .{ // metal1
                    .center =  .{ .x = -14.0, .y = 0.0, .z = 0.0 },
                    .radius = 3.0,
                    .material = mat_metal_1
                }
            },
            .{
                .sphere = .{ // metal2
                    .center =  .{ .x = -7.0, .y = 0.0, .z = 0.0 },
                    .radius = 3.0,
                    .material = mat_metal_2
                }
            },
            .{
                .sphere = .{ // metal3
                    .center =  .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                    .radius = 3.0,
                    .material = mat_metal_3
                }
            },
            .{
                .sphere = .{ // metal4
                    .center =  .{ .x = 7.0, .y = 0.0, .z = 0.0 },
                    .radius = 3.0,
                    .material = mat_metal_4
                }
            },
            .{
                .sphere = .{ // outer glass
                    .center =  .{ .x = 14.0, .y = 0.0, .z = 0.0 },
                    .radius = 3.0,
                    .material = mat_glass_outer
                }
            },
            .{
                .sphere = .{ // inner glass
                    .center =  .{ .x = 14.0, .y = 0.0, .z = 0.0 },
                    .radius = 2.0,
                    .material = mat_glass_inner
                }
            },
        }
    };

    // const serial_raytracer = RayTracer {
    //     .settings = render_settings,
    //     .progress_root_node = root_node
    // };

    var threaded = std.Io.Threaded.init(init.gpa, .{});
    defer threaded.deinit();
    const parallel_raytracer = ParallelRayTracer {
        .settings = render_settings,
        .io = threaded.io(),
        .progress_root_node = root_node
    };

    var buf_writer = std.Io.Writer.fixed(memory_map.memory[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    var time_start: std.Io.Timestamp = undefined;
    var time_end: std.Io.Timestamp = undefined;

    time_start = std.Io.Clock.awake.now(init.io);
    // serial_raytracer.render(scene, memory_map.memory[PPM_HEADER_LEN..]);
    time_end = std.Io.Clock.awake.now(init.io);

    const serial_duration = time_start.durationTo(time_end).toNanoseconds();

    time_start = std.Io.Clock.awake.now(init.io);
    try parallel_raytracer.render(scene, memory_map.memory[PPM_HEADER_LEN..]);
    time_end = std.Io.Clock.awake.now(init.io);

    const parallel_duration = time_start.durationTo(time_end).toNanoseconds();

    print(
        \\
        \\ ====== EXECUTION TIME COMPARISON ======
        \\ Serial Execution: {} ms.
        \\ Parallel Execution: {} ms.
        \\ Speedup: {d:.2}.
        \\ =======================================
        \\
    , .{ @divTrunc(serial_duration, std.time.ns_per_ms), @divTrunc(parallel_duration, std.time.ns_per_ms), @as(f128, @floatFromInt(serial_duration)) / @as(f128, @floatFromInt(parallel_duration))});

    try memory_map.write(init.io);
}

test {
    _ = @import("math_utils.zig");
    _ = @import("fs_utils.zig");
    _ = @import("graphics.zig");
    _ = @import("Vec3.zig");
}
