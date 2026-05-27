const std = @import("std");
const builtin = @import("builtin");
const graphics = @import("graphics.zig");
const fs_utils = @import("fs_utils.zig");
const type_utils = @import("type_utils.zig");
const config = @import("global_config.zig");
const rendering = graphics.scene_3d.rendering;
const raytracing = rendering.raytracing;
const materials = graphics.scene_3d.materials;
const math_utils = @import("math_utils.zig");

const Vec3 = @import("Vec3.zig");
const LinearColor = graphics.LinearColor;
const Scene = graphics.scene_3d.Scene;
const Camera = graphics.scene_3d.Camera;
const Hittable = graphics.scene_3d.geometry.Hittable;
const RenderSettings = rendering.RenderSettings;
const SerialPathTracer = raytracing.SerialPathTracer;
const ParallelPathTracer = raytracing.ParallelPathTracer;
const Material = materials.Material;
const Float = config.Float;

const print = std.debug.print;
const createImgFile = fs_utils.createImgFile;
const assertAnytypeHasDecls = type_utils.assertAnytypeHasDecls;

const HELP_FMT_STR: []const u8 =
            \\ Whenever an argument expects a value, it can be provided either with the syntax --<argument>=<value> or --<argument> <value>.
            \\ Available arguments:
            \\ --renderer
            \\     Choose the rendering algorithm.
            \\     Defaults to Parallel if your system supports multi-threading, Serial otherwise.
            \\     Available values:
            \\         - Serial
            \\         - Parallel
            \\
            \\ --scene
            \\     Choose the scene to render.
            \\     Defaults to CornellBox.
            \\     Available values:
            \\         - ProceduralSpheres
            \\         - CornellBox
            \\         - Quads
            \\
            \\ --img-height
            \\     Choose the output image height.
            \\     Defaults to 600.
            \\     Available values:
            \\         - Any integer between 0 and {}.
            \\
            \\ --img-width
            \\     Choose the output image width.
            \\     Defaults to 600.
            \\     Available values:
            \\         - Any integer between 0 and {}.
            \\
            \\ --max-bounces
            \\     Choose the maximum number of traced ray bounces before stopping the recursion.
            \\     Defaults to 50.
            \\     Available values:
            \\         - Any integer between 0 and {}.
            \\
            \\ --samples
            \\     Choose how many times a pixel is sampled (i.e. how many rays are sent through a single pixel).
            \\     Defaults to 200.
            \\     Available values:
            \\         - Any integer between 0 and {}.
            \\
            \\ --track-progress
            \\     Log the rendering progress (rendered image rows / total image rows).
            \\     Defaults to false.
            \\     This argument acts as a toggle, so it does not require any value.
            \\
            \\ --time-report
            \\     Log the rendering time once it completes.
            \\     Defaults to false.
            \\     This argument acts as a toggle, so it does not require any value.
            \\
;

const IMG_WIDTH = 600;
const IMG_HEIGHT= 600;

const IMG_OUT_PATHS: []const []const u8 = &.{"renders", "output.ppm"};
const FILE_PATH = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(IMG_OUT_PATHS)});
const PPM_HEADER_LEN = fs_utils.computePpmP6HeaderSize(255, IMG_WIDTH, IMG_HEIGHT);

const SceneId = enum { ProceduralSpheres, CornellBox, Quads };
const RendererType = enum { Serial, Parallel };

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.DebugAllocator(.{}) {};
    // defer if (gpa.deinit() == .leak) {
    //     @panic("Memory leak detected!");
    // };
    const allocator = init.arena.allocator();

    var render_settings = RenderSettings {
        .image_width = IMG_WIDTH,
        .image_height = IMG_HEIGHT,
        .ray_t_range = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
        .max_ray_bounces = 50,
        .samples_per_pixel = 200, // 2000,
        .pixel_samples_scale = 0.005, // 0.0005, // 1/samples_per_pixel
    };
    var track_progress = false;
    var time_report = false;
    var scene_id: SceneId = .CornellBox;
    var renderer_type: RendererType = if (builtin.single_threaded) .Serial else .Parallel;

    var args_it = try init.minimal.args.iterateAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.skip(); // Skip the executable name

    while(args_it.next()) |arg| {
        var split_it = std.mem.splitScalar(u8, arg, '=');
        const arg_name = split_it.first();
        const arg_val = split_it.next();

        if (std.mem.eql(u8, arg_name, "--renderer")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgument;
            };

            if (std.meta.stringToEnum(RendererType, val_str)) |r| {
                if (r == .Parallel and builtin.single_threaded) {
                    print("Error: your system is single-threaded, therefore it can't run the '{s}' algorithm.\n", .{val_str});
                    return error.ConcurrencyNotAvailable;
                }
                renderer_type = r;
            } else {
                print("Error: unknown renderer '{s}'. The available options are:\n", .{val_str});
                const fields = @typeInfo(RendererType).@"enum".fields;
                inline for (fields) |field| {
                    print("- {s}\n", .{field.name});
                }

                return error.InvalidArgumentValue;
            }
        }
        else if (std.mem.eql(u8, arg_name, "--scene")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgument;
            };

            if (std.meta.stringToEnum(SceneId, val_str)) |id| {
                scene_id = id;
            } else {
                print("Error: unknown scene '{s}'. The available options are:\n", .{val_str});
                const fields = @typeInfo(SceneId).@"enum".fields;
                inline for (fields) |field| {
                    print("- {s}\n", .{field.name});
                }

                return error.InvalidArgumentValue;
            }
        }
        else if (std.mem.eql(u8, arg_name, "--img-height")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgument;
            };
            render_settings.image_height = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, std.math.maxInt(u16)}),
                    error.InvalidCharacter => print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}),
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--img-width")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgument;
            };
            render_settings.image_width = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, std.math.maxInt(u16)}),
                    error.InvalidCharacter => print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}),
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--max-bounces")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgument;
            };
            render_settings.max_ray_bounces = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, std.math.maxInt(u16)}),
                    error.InvalidCharacter => print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}),
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--samples")) {
            const val_str = arg_val orelse args_it.next() orelse {
                print("Error: missing value for '{s}'.\n", .{arg_name});
                return error.MissingArgumentValue;
            };
            render_settings.samples_per_pixel = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, std.math.maxInt(u16)}),
                    error.InvalidCharacter => print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}),
                }
                return err;
            };
            render_settings.pixel_samples_scale = 1.0 / @as(Float, @floatFromInt(render_settings.samples_per_pixel));
        }
        else if (std.mem.eql(u8, arg_name, "--track-progress")) {
            if (arg_val != null) {
                print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?});
                return error.UnexpectedArgumentValue;
            }
            track_progress = true;
        }
        else if (std.mem.eql(u8, arg_name, "--time-report")) {
            if (arg_val != null) {
                print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?});
                return error.UnexpectedArgumentValue;
            }
            time_report = true;
        }
        else if (std.mem.eql(u8, arg_name, "--help")) {
            if (arg_val != null) {
                print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?});
                return error.UnexpectedArgumentValue;
            }

            const u16Max = std.math.maxInt(u16);
            print(HELP_FMT_STR, .{u16Max, u16Max, u16Max, u16Max});
            return;
        }
        else {
            print("Error: unknown argument '{s}'.\n", .{arg_name});
            return error.UnknownArgument;
        }
    }

    const root_node: ?std.Progress.Node = if (track_progress) std.Progress.start(init.io, .{ .root_name = "Scene Render" }) else null;
    defer if (root_node) |n| n.end();

    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, FILE_PATH);
    defer file.close(init.io);

    var memory_map = blk: {
        try file.setLength(init.io, PPM_HEADER_LEN + IMG_HEIGHT * IMG_WIDTH * 3);
        const stat = try file.stat(init.io);

        break :blk try file.createMemoryMap(init.io, .{.len = stat.size });
    };
    defer memory_map.destroy(init.io);

    switch (renderer_type) {
        .Parallel => {
            if (comptime !builtin.single_threaded) {
                var threaded = std.Io.Threaded.init(allocator, .{});
                defer threaded.deinit();

                const renderer = ParallelPathTracer {
                    .settings = render_settings,
                    .io = threaded.io(),
                    .progress_root_node = root_node
                };
                try initAndRenderScene(init.io, allocator, scene_id, renderer, render_settings, memory_map.memory, time_report);
            }
            else unreachable;
        },
        .Serial => {
            const renderer = SerialPathTracer {
                .settings = render_settings,
                .progress_root_node = root_node
            };
            try initAndRenderScene(init.io, allocator, scene_id, renderer, render_settings, memory_map.memory, time_report);
        }
    }

    try memory_map.write(init.io);
}

fn initAndRenderScene(io: std.Io, gpa: std.mem.Allocator, scene_id: SceneId, renderer: anytype, render_settings: RenderSettings, out_buf: []u8, time_report: bool) !void {
    assertAnytypeHasDecls(renderer, &.{ "render" });
    switch (scene_id) {
        .ProceduralSpheres => try initAndRenderSpheresScene(io, gpa, renderer, render_settings, out_buf, time_report),
        .CornellBox => try initAndRenderCornellBox(io, gpa, renderer, render_settings, out_buf, time_report),
        .Quads => try initAndRenderQuadsScene(io, gpa, renderer, render_settings, out_buf, time_report),
    }
}

fn executeRender(io: std.Io, scene: *const Scene, renderer: anytype, render_settings: RenderSettings, out_buf: []u8, time_report: bool) !void {
    var buf_writer = std.Io.Writer.fixed(out_buf[0..PPM_HEADER_LEN]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    var time_start: std.Io.Timestamp = undefined;
    var time_end: std.Io.Timestamp = undefined;
    var duration: i96 = undefined;

    print("Render started.\n", .{});
    if (time_report) time_start = std.Io.Clock.awake.now(io);

    const result_type = @TypeOf(renderer.render(scene, out_buf[PPM_HEADER_LEN..]));
    if (@typeInfo(result_type) == .error_union) {
        try renderer.render(scene, out_buf[PPM_HEADER_LEN..]);
    }
    else {
        renderer.render(scene, out_buf[PPM_HEADER_LEN..]);
    }

    if (time_report) {
        time_end = std.Io.Clock.awake.now(io);
        duration = time_start.durationTo(time_end).toNanoseconds();
    }

    print("Render completed successfully.\n", .{});
    if (time_report) {
        print("Elapsed time: {}s, ({}ms).\n", .{
            @divTrunc(duration, std.time.ns_per_s),
            @divTrunc(duration, std.time.ns_per_ms),
        });
    }
}

fn initAndRenderSpheresScene(io: std.Io, gpa: std.mem.Allocator, renderer: anytype, render_settings: RenderSettings, out_buf: []u8, time_report: bool) !void {
    const camera = Camera.initLookAt(
        .init(13.0, 2.0, 3.0),
        .init(0.0, 0.0, 0.0),
        20.0,
        10.0,
        0.6,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, .init(0.7, 0.8, 1.0), gpa, 256);
    defer scene.deinit();

    const big_radius: Float = 1.0;
    const small_radius: Float = 0.2;

    const ground_material = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.5, 0.5, 0.5) } });
    const center_ground = Vec3.init(0.0, -1000.0, 0.0);
    try scene.add(Hittable.createSphere(center_ground, 1000, ground_material));

    const material_1 = try scene.createMaterial(.{ .dielectic = .{ .refractive_index = 1.5 } });
    const center_1 = Vec3.init(0.0, 1.0, 0.0);
    try scene.add(Hittable.createSphere(center_1, 1.0, material_1));

    const material_1_inside = try scene.createMaterial(.{ .dielectic = .{ .refractive_index = 1.0 / 1.5 } });
    try scene.add(Hittable.createSphere(center_1, 0.5, material_1_inside));

    const material_2 = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.4, 0.2, 0.1) } });
    const center_2 = Vec3.init(-4.0, 1.0, 0.0);
    try scene.add(Hittable.createSphere(center_2, 1.0, material_2));

    const material_3 = try scene.createMaterial(. { .metal = .{ .albedo = .init(0.7, 0.6, 0.5), .fuzz = 0.0 } });
    const center_3 = Vec3.init(4.0, 1.0, 0.0);
    try scene.add(Hittable.createSphere(center_3, 1.0, material_3));

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
                center = Vec3.init(x_offset, small_radius, z_offset);

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

                    const lambertian = try scene.createMaterial(.{ .lambertian = .{ .albedo = albedo } });
                    try scene.add(Hittable.createSphere(center, small_radius, lambertian));
                }
                else if (choose_mat < 0.85) {
                    // metal
                    const albedo = LinearColor.randomInRange(rand, .{ .min = 0.5, .max = 1.0 });
                    const fuzz = math_utils.rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0 }, .{ .min = 0.0, .max = 0.5});

                    const metal = try scene.createMaterial(.{ .metal = .{ .albedo = albedo, .fuzz = fuzz } });
                    try scene.add(Hittable.createSphere(center, small_radius, metal));
                }
                else {
                    // glass
                    const dielectric = try scene.createMaterial(.{ .dielectic = .{ .refractive_index = 1.5 } });
                    try scene.add(Hittable.createSphere(center, small_radius, dielectric));
                }
            }
        }
    }

    try scene.buildBvh(4);
    try executeRender(io, &scene, renderer, render_settings, out_buf, time_report);
}

fn initAndRenderQuadsScene(io: std.Io, gpa: std.mem.Allocator, renderer: anytype, render_settings: RenderSettings, out_buf: []u8, time_report: bool) !void {
    const camera = Camera.initLookAt(
        .init(0.0, 0.0, 9.0),
        .init(0.0, 0.0, 0.0),
        80.0,
        10.0,
        0.0,
        render_settings);
    var scene = try Scene.initWithCapacity(camera, .init(0.7, 0.8, 1.0), gpa, 5);
    defer scene.deinit();

    // Materials
    const left_red     = try scene.createMaterial(.{ .lambertian = .{ .albedo = LinearColor.init(1.0, 0.2, 0.2) } });
    const back_green   = try scene.createMaterial(.{ .lambertian = .{ .albedo = LinearColor.init(0.2, 1.0, 0.2) } });
    const right_blue   = try scene.createMaterial(.{ .lambertian = .{ .albedo = LinearColor.init(0.2, 0.2, 1.0) } });
    const upper_orange = try scene.createMaterial(.{ .lambertian = .{ .albedo = LinearColor.init(1.0, 0.5, 0.0) } });
    const lower_teal   = try scene.createMaterial(.{ .lambertian = .{ .albedo = LinearColor.init(0.2, 0.8, 0.8) } });

    // Quads
    try scene.add(Hittable.createQuad(
        .init(-3.0, -2.0, 5.0),
        .init(0.0, 0.0, -4.0),
        .init(0.0, 4.0, 0.0),
        left_red
    ));
    try scene.add(Hittable.createQuad(
        .init(-2.0, -2.0, 0.0),
        .init(4.0, 0.0, -0.0),
        .init(0.0, 4.0, 0.0),
        back_green
    ));
    try scene.add(Hittable.createQuad(
        .init(3.0, -2.0, 1.0),
        .init(0.0, 0.0, 4.0),
        .init(0.0, 4.0, 0.0),
        right_blue
    ));
    try scene.add(Hittable.createQuad(
        .init(-2.0, 3.0, 1.0),
        .init(4.0, 0.0, 0.0),
        .init(0.0, 0.0, 4.0),
        upper_orange
    ));
    try scene.add(Hittable.createQuad(
        .init(-2.0, -3.0, 5.0),
        .init(4.0, 0.0, 0.0),
        .init(0.0, 0.0, -4.0),
        lower_teal
    ));

    try scene.buildBvh(1);
    try executeRender(io, &scene, renderer, render_settings, out_buf, time_report);
}

fn initAndRenderCornellBox(io: std.Io, gpa: std.mem.Allocator, renderer: anytype, render_settings: RenderSettings, out_buf: []u8, time_report: bool) !void {
    const camera = Camera.initLookAt(
        .init(278.0, 278.0, -800.0),
        .init(278.0, 278.0, 0.0),
        40.0,
        10.0,
        0.0,
        render_settings
    );
    var scene = try Scene.initWithCapacity(camera, LinearColor.black, gpa, 8);
    defer scene.deinit();

    // Materials
    const red   = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.65, 0.05, 0.05) } });
    const white = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.73, 0.73, 0.73) } });
    const green = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.12, 0.45, 0.15) } });
    const light = try scene.createMaterial(.{ .diffuse_light = .{ .color = .init(10.0, 10.0, 10.0) } });
    const glass = try scene.createMaterial(.{ .dielectic = .{ .refractive_index = 1.5 } });

    // Primitives
    try scene.add(Hittable.createQuad(.init(555.0, 0.0, 0.0),     .init(0.0, 555.0, 0.0),  .init(0.0, 0.0, 555.0), red));
    try scene.add(Hittable.createQuad(.init(0.0, 0.0, 0.0),       .init(0.0, 555.0, 0.0),  .init(0.0, 0.0, 555.0), green));
    try scene.add(Hittable.createQuad(.init(375.0, 554.0, 356.25), .init(-195.0, 0.0, 0.0), .init(0.0, 0.0, -157.5), light));
    try scene.add(Hittable.createQuad(.init(0.0, 0.0, 0.0),       .init(555.0, 0.0, 0.0),  .init(0.0, 0.0, 555.0), white));
    try scene.add(Hittable.createQuad(.init(555.0, 555.0, 555.0), .init(-555.0, 0.0, 0.0), .init(0.0, 0.0, -555.0), white));
    try scene.add(Hittable.createQuad(.init(0.0, 0.0, 555.0),     .init(555.0, 0.0, 0.0),  .init(0.0, 555.0, 0.0), white));

    var box = try Hittable.createBox(.init(0.0, 0.0, 0.0), .init(165.0, 330.0, 165.0), white, gpa);
    box = try box.rotateY(15.0, gpa);
    box = try box.translate(.init(265.0, 0.0, 295.0), gpa);
    try scene.add(box);

    const sphere = Hittable.createSphere(.init(190.0, 90.0, 190.0), 90.0, glass);
    try scene.add(sphere);

    try scene.buildBvh(1);
    try executeRender(io, &scene, renderer, render_settings, out_buf, time_report);
}

test {
    _ = @import("math_utils.zig");
    _ = @import("fs_utils.zig");
    _ = @import("graphics.zig");
    _ = @import("Vec3.zig");
}
