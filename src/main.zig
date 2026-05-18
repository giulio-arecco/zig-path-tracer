const std = @import("std");
const graphics = @import("graphics.zig");
const fs_utils = @import("fs_utils.zig");
const config = @import("config.zig");
const rendering = graphics.scene_3d.rendering;
const raytracing = rendering.raytracing;
const materials = graphics.scene_3d.materials;
const math_utils = @import("math_utils.zig");

const Vec3 = @import("Vec3.zig");
const LinearColor = graphics.LinearColor;
const Scene = graphics.scene_3d.Scene;
const Camera = graphics.scene_3d.Camera;
const Sphere = graphics.scene_3d.geometry.Sphere;
const Quad = graphics.scene_3d.geometry.Quad;
const RenderSettings = rendering.RenderSettings;
const RayTracer = raytracing.RayTracer;
const ParallelRayTracer = raytracing.ParallelRayTracer;
const Material = materials.Material;
const Float = config.Float;

const print = std.debug.print;
const drawCircle = fs_utils.drawCircle;
const createImgFile = fs_utils.createImgFile;
const computePathStrLen = fs_utils.computePathStrLen;

const IMG_WIDTH = 600;
const IMG_HEIGHT= 600;

const IMG_OUT_PATHS: []const []const u8 = &.{"images", "output.ppm"};
const PATH_STR_LENGTH = computePathStrLen(IMG_OUT_PATHS);
const FILE_PATH = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(IMG_OUT_PATHS)});
const PPM_HEADER_LEN = fs_utils.computePpmP6HeaderSize(255, IMG_WIDTH, IMG_HEIGHT);

const TRACK_PROGRESS = true;

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, FILE_PATH);
    defer file.close(init.io);

    var memory_map = blk: {
        try file.setLength(init.io, PPM_HEADER_LEN + IMG_HEIGHT * IMG_WIDTH * 3);
        const stat = try file.stat(init.io);

        break :blk try file.createMemoryMap(init.io, .{.len = stat.size });
    };
    defer memory_map.destroy(init.io);

    // try initAndRenderSpheresScene(init.io, init.arena.allocator(), memory_map.memory);
    // try initAndRenderQuadsScene(init.io, init.arena.allocator(), memory_map.memory);
    // try initAndRenderSimpleLightScene(init.io, init.arena.allocator(), memory_map.memory);
    try initAndRenderCornellBox(init.io, init.arena.allocator(), memory_map.memory);

    try memory_map.write(init.io);
}

fn initAndRenderSpheresScene(io: std.Io, gpa: std.mem.Allocator, out_buf: []u8) !void {
    const root_node: ?std.Progress.Node = if (TRACK_PROGRESS) std.Progress.start(io, .{ .root_name = "Spheres Scene" }) else null;
    defer if (root_node) |n| n.end();

    const render_settings = RenderSettings {
        .image_width = IMG_WIDTH,
        .image_height = IMG_HEIGHT,
        .ray_t_range = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
        .max_ray_bounces = 50,
        .samples_per_pixel = 500,
        .pixel_samples_scale = 0.002, // 1/samples_per_pixel
    };

    const camera = Camera.initLookAt(
        .{ .x = 13.0, .y = 2.0, .z = 3.0},
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        20.0,
        10.0,
        0.6,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, .init(0.7, 0.8, 1.0), gpa, 256);
    defer scene.deinit();

    const big_radius: Float = 1.0;
    const small_radius: Float = 0.2;

    const ground_material = Material { .lambertian = .{ .albedo = .init(0.5, 0.5, 0.5) } };
    const center_ground = Vec3 { .x = 0.0, .y = -1000.0, .z = 0.0 };
    try scene.add(.{ .sphere = .init(center_ground, 1000, ground_material) });

    const material_1 = Material { .dielectic = .{ .refractive_index = 1.5 }};
    const center_1 = Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 };
    try scene.add(.{ .sphere = .init(center_1, 1.0, material_1) });

    const material_1_inside = Material { .dielectic = .{ .refractive_index = 1.0 / 1.5 }};
    try scene.add(.{ .sphere = .init(center_1, 0.5, material_1_inside) });

    const material_2 = Material { .lambertian = .{ .albedo = .init(0.4, 0.2, 0.1) } };
    const center_2 = Vec3 { .x = -4.0, .y = 1.0, .z = 0.0 };
    try scene.add(.{ .sphere = .init(center_2, 1.0, material_2) });

    const material_3 = Material { .metal = .{ .albedo = .init(0.7, 0.6, 0.5), .fuzz = 0.0 }};
    const center_3 = Vec3 { .x = 4.0, .y = 1.0, .z = 0.0 };
    try scene.add(.{ .sphere = .init(center_3, 1.0, material_3) });

    var prng: std.Random.DefaultPrng = .init(121);
    const rand = prng.random();
    const safe_jitter_area: Float = 1.0 - (2.0 * small_radius);
    const min_dist = big_radius + small_radius + 0.1;
    const min_dist_sq = min_dist * min_dist;
    for(0..22) |a| {
        for (0..22) |b| {
            var attempt: usize = 0;
            var position_found = false;
            var center: Vec3 = undefined;

            while (attempt < 20) : (attempt += 1) {
                const cell_x = @as(Float, @floatFromInt(@as(isize, @intCast(a)) - 11));
                const cell_z = @as(Float, @floatFromInt(@as(isize, @intCast(b)) - 11));

                const x_offset = cell_x + small_radius + (safe_jitter_area * rand.float(Float));
                const z_offset = cell_z + small_radius + (safe_jitter_area * rand.float(Float));
                center = Vec3 { .x = x_offset, .y = small_radius, .z = z_offset };

                const dist_1_sq = Vec3.squaredDistance(center, center_1);
                const dist_2_sq = Vec3.squaredDistance(center, center_2);
                const dist_3_sq = Vec3.squaredDistance(center, center_3);

                if (dist_1_sq > min_dist_sq and dist_2_sq > min_dist_sq and dist_3_sq > min_dist_sq) {
                    position_found = true;
                    break;
                }
            }

            if (position_found) {
                const choose_mat = rand.float(Float);

                if (choose_mat < 0.7) {
                    // lambertian
                    const albedo = LinearColor.random(rand).mul(LinearColor.random(rand));
                    const lambertian = Material { .lambertian = .{ .albedo = albedo } };
                    try scene.add(.{ .sphere = .init(center, small_radius, lambertian) });
                }
                else if (choose_mat < 0.85) {
                    // metal
                    const albedo = LinearColor.randomInRange(rand, 0.5, 1.0);
                    const fuzz = math_utils.rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0 }, .{ .min = 0.0, .max = 0.5});
                    const metal = Material { .metal = .{ .albedo = albedo, .fuzz = fuzz }};
                    try scene.add(.{ .sphere = .init(center, small_radius, metal) });
                }
                else {
                    // glass
                    const dielectric = Material { .dielectic = .{ .refractive_index = 1.5 }};
                    try scene.add(.{ .sphere = .init(center, small_radius, dielectric) });
                }
            }
        }
    }

    // const serial_raytracer = RayTracer {
    //     .settings = render_settings,
    //     .progress_root_node = root_node
    // };

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const parallel_raytracer = ParallelRayTracer {
        .settings = render_settings,
        .io = threaded.io(),
        .progress_root_node = root_node
    };

    var buf_writer = std.Io.Writer.fixed(out_buf[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    var time_start: std.Io.Timestamp = undefined;
    var time_end: std.Io.Timestamp = undefined;

    time_start = std.Io.Clock.awake.now(io);
    // serial_raytracer.render(scene, memory_map.memory[PPM_HEADER_LEN..]);
    time_end = std.Io.Clock.awake.now(io);
    const serial_duration = time_start.durationTo(time_end).toNanoseconds();

    time_start = std.Io.Clock.awake.now(io);
    try parallel_raytracer.render(&scene, out_buf[PPM_HEADER_LEN..]);
    time_end = std.Io.Clock.awake.now(io);
    const parallel_duration = time_start.durationTo(time_end).toNanoseconds();

    try scene.buildBvh(4);

    time_start = std.Io.Clock.awake.now(io);
    try parallel_raytracer.render(&scene, out_buf[PPM_HEADER_LEN..]);
    time_end = std.Io.Clock.awake.now(io);

    const parallel_bvh_duration = time_start.durationTo(time_end).toNanoseconds();

    print(
        \\
        \\ ====== EXECUTION TIME COMPARISON ======
        \\ Serial Execution: {} ms.
        \\ Parallel Execution: {} ms.
        \\ Parallel with BVH Execution: {} ms.
        \\ Serial/Parallel Speedup: {d:.2}.
        \\ Parallel/Parallel with BVH Speedup: {d:.2}.
        \\ =======================================
        \\
    , .{
        @divTrunc(serial_duration, std.time.ns_per_ms),
        @divTrunc(parallel_duration, std.time.ns_per_ms),
        @divTrunc(parallel_bvh_duration, std.time.ns_per_ms),
        @as(f128, @floatFromInt(serial_duration)) / @as(f128, @floatFromInt(parallel_duration)),
        @as(f128, @floatFromInt(parallel_duration)) / @as(f128, @floatFromInt(parallel_bvh_duration))
    });
}

fn initAndRenderQuadsScene(io: std.Io, gpa: std.mem.Allocator, out_buf: []u8) !void {
    const root_node: ?std.Progress.Node = if (TRACK_PROGRESS) std.Progress.start(io, .{ .root_name = "Quads scene" }) else null;
    defer if (root_node) |n| n.end();

    const render_settings = RenderSettings {
        .image_width = IMG_WIDTH,
        .image_height = IMG_HEIGHT,
        .ray_t_range = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
        .max_ray_bounces = 50,
        .samples_per_pixel = 100,
        .pixel_samples_scale = 0.01, // 1/samples_per_pixel
    };

    const camera = Camera.initLookAt(
        .{ .x = 0.0, .y = 0.0, .z = 9.0},
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        80.0,
        10.0,
        0.0,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, .init(0.7, 0.8, 1.0), gpa, 256);
    defer scene.deinit();

    // Materials
    const left_red     = Material { .lambertian = .{ .albedo = LinearColor.init(1.0, 0.2, 0.2) } };
    const back_green   = Material { .lambertian = .{ .albedo = LinearColor.init(0.2, 1.0, 0.2) } };
    const right_blue   = Material { .lambertian = .{ .albedo = LinearColor.init(0.2, 0.2, 1.0) } };
    const upper_orange = Material { .lambertian = .{ .albedo = LinearColor.init(1.0, 0.5, 0.0) } };
    const lower_teal   = Material { .lambertian = .{ .albedo = LinearColor.init(0.2, 0.8, 0.8) } };

    // Quads
    try scene.add(.{ .quad = Quad.init(
        .{ .x = -3.0, .y = -2.0, .z = 5.0 },
        .{ .x = 0.0, .y = 0.0, .z = -4.0 },
        .{ .x = 0.0, .y = 4.0, .z = 0.0 },
        left_red
    )});
    try scene.add(.{ .quad = Quad.init(
        .{ .x = -2.0, .y = -2.0, .z = 0.0 },
        .{ .x = 4.0, .y = 0.0, .z = -0.0 },
        .{ .x = 0.0, .y = 4.0, .z = 0.0 },
        back_green
    )});
    try scene.add(.{ .quad = Quad.init(
        .{ .x = 3.0, .y = -2.0, .z = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 4.0 },
        .{ .x = 0.0, .y = 4.0, .z = 0.0 },
        right_blue
    )});
    try scene.add(.{ .quad = Quad.init(
        .{ .x = -2.0, .y = 3.0, .z = 1.0 },
        .{ .x = 4.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 0.0, .z = 4.0 },
        upper_orange
    )});
    try scene.add(.{ .quad = Quad.init(
        .{ .x = -2.0, .y = -3.0, .z = 5.0 },
        .{ .x = 4.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 0.0, .z = -4.0 },
        lower_teal
    )});

    try scene.buildBvh(1);

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const parallel_raytracer = ParallelRayTracer {
        .settings = render_settings,
        .io = threaded.io(),
        .progress_root_node = root_node
    };

    var buf_writer = std.Io.Writer.fixed(out_buf[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    try parallel_raytracer.render(&scene, out_buf[PPM_HEADER_LEN..]);
    print("Render completed successfully.\n", .{});
}

fn initAndRenderSimpleLightScene(io: std.Io, gpa: std.mem.Allocator, out_buf: []u8) !void {
    const root_node: ?std.Progress.Node = if (TRACK_PROGRESS) std.Progress.start(io, .{ .root_name = "Simple light scene" }) else null;
    defer if (root_node) |n| n.end();

    const render_settings = RenderSettings {
        .image_width = IMG_WIDTH,
        .image_height = IMG_HEIGHT,
        .ray_t_range = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
        .max_ray_bounces = 50,
        .samples_per_pixel = 100,
        .pixel_samples_scale = 0.01, // 1/samples_per_pixel
    };

    const camera = Camera.initLookAt(
        .{ .x = 26.0, .y = 3.0, .z = 6.0},
        .{ .x = 0.0, .y = 2.0, .z = 0.0 },
        20.0,
        10.0,
        0.0,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, LinearColor.black, gpa, 256);
    defer scene.deinit();

    // Materials
    const sphere_mat = Material { .lambertian = .{ .albedo = .init(0.7, 0.7, 0.7) } };
    const ground_mat = Material { .lambertian = .{ .albedo = .init(0.6, 0.6, 0.6) } };
    const light_mat  = Material { .diffuse_light = .{ .color = .init(4.0, 4.0, 4.0) } };

    // Primitives
    try scene.add(.{ .sphere = .init(.{ .x = 0.0, .y = -1000.0, .z = 0.0 }, 1000.0, ground_mat) });
    try scene.add(.{ .sphere = .init(.{ .x = 0.0, .y = 2.0, .z = 0.0 }, 2.0, sphere_mat) });
    try scene.add(.{ .quad = .init(.{ .x = 3.0, .y = 1.0, .z = -2.0 }, .{ .x = 2.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 2.0, .z = 0.0 }, light_mat) });

    try scene.buildBvh(1);

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const parallel_raytracer = ParallelRayTracer {
        .settings = render_settings,
        .io = threaded.io(),
        .progress_root_node = root_node
    };

    var buf_writer = std.Io.Writer.fixed(out_buf[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    try parallel_raytracer.render(&scene, out_buf[PPM_HEADER_LEN..]);
    print("Render completed successfully.\n", .{});
}

fn initAndRenderCornellBox(io: std.Io, gpa: std.mem.Allocator, out_buf: []u8) !void {
    const root_node: ?std.Progress.Node = if (TRACK_PROGRESS) std.Progress.start(io, .{ .root_name = "Cornell box scene" }) else null;
    defer if (root_node) |n| n.end();

    const render_settings = RenderSettings {
        .image_width = IMG_WIDTH,
        .image_height = IMG_HEIGHT,
        .ray_t_range = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
        .max_ray_bounces = 50,
        .samples_per_pixel = 200,
        .pixel_samples_scale = 0.005, // 1/samples_per_pixel
    };

    const camera = Camera.initLookAt(
        .{ .x = 278.0, .y = 278.0, .z = -800.0},
        .{ .x = 278.0, .y = 278.0, .z = 0.0 },
        40.0,
        10.0,
        0.0,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, LinearColor.black, gpa, 256);
    defer scene.deinit();

    // Materials
    const red = Material { .lambertian = .{ .albedo = .init(0.65, 0.05, 0.05) } };
    const white = Material { .lambertian = .{ .albedo = .init(0.73, 0.73, 0.73) } };
    const green = Material { .lambertian = .{ .albedo = .init(0.12, 0.45, 0.15) } };
    const light = Material { .diffuse_light = .{ .color = .init(15.0, 15.0, 15.0) } };

    // Primitives
    try scene.add(.{ .quad = .init(.{ .x = 555.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 555.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = 555.0 }, red) });
    try scene.add(.{ .quad = .init(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 555.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = 555.0 }, green) });
    try scene.add(.{ .quad = .init(.{ .x = 343.0, .y = 554.0, .z = 332.0 }, .{ .x = -130.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = -105.0 }, light) });
    try scene.add(.{ .quad = .init(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, .{ .x = 555.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = 555.0 }, white) });
    try scene.add(.{ .quad = .init(.{ .x = 555.0, .y = 555.0, .z = 555.0 }, .{ .x = -555.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 0.0, .z = -555.0 }, white) });
    try scene.add(.{ .quad = .init(.{ .x = 0.0, .y = 0.0, .z = 555.0 }, .{ .x = 555.0, .y = 0.0, .z = 0.0 }, .{ .x = 0.0, .y = 555.0, .z = 0.0 }, white) });

    try scene.buildBvh(1);

    var threaded = std.Io.Threaded.init(gpa, .{});
    defer threaded.deinit();
    const parallel_raytracer = ParallelRayTracer {
        .settings = render_settings,
        .io = threaded.io(),
        .progress_root_node = root_node
    };

    var buf_writer = std.Io.Writer.fixed(out_buf[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    try parallel_raytracer.render(&scene, out_buf[PPM_HEADER_LEN..]);
    print("Render completed successfully.\n", .{});
}

test {
    _ = @import("math_utils.zig");
    _ = @import("fs_utils.zig");
    _ = @import("graphics.zig");
    _ = @import("Vec3.zig");
}
