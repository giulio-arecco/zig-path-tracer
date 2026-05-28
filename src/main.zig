const std = @import("std");
const builtin = @import("builtin");
const graphics = @import("graphics.zig");
const fs_utils = @import("fs_utils.zig");
const type_utils = @import("type_utils.zig");
const config = @import("global_config.zig");
const rendering = graphics.scene_3d.rendering;
const materials = graphics.scene_3d.materials;
const math_utils = @import("math_utils.zig");

const Vec3 = @import("Vec3.zig");
const SceneId = config.SceneId;
const AppConfig = config.AppConfig;
const LinearColor = graphics.LinearColor;
const Scene = graphics.scene_3d.Scene;
const Camera = graphics.scene_3d.Camera;
const Hittable = graphics.scene_3d.geometry.Hittable;
const PipelineContext = rendering.PipelineContext;
const RenderSettings = rendering.RenderSettings;
const RendererType = rendering.RendererType;
const Renderer = rendering.Renderer;
const SerialPathTracer = rendering.SerialPathTracer;
const ParallelPathTracer = rendering.ParallelPathTracer;
const Material = materials.Material;
const Float = config.Float;

const print = std.debug.print;
const createImgFile = fs_utils.createImgFile;
const assertAnytypeHasDecls = type_utils.assertAnytypeHasDecls;
const executeRenderPipeline = rendering.executeRenderPipeline;

const ArgHelp = struct {
    name: []const u8,
    desc: []const u8,
    default: ?[]const u8 = null,
    values:  ?[]const []const u8 = null,
};

const u16Max = std.math.maxInt(u16);
const default_config = AppConfig {};
const img_out_paths: []const []const u8 = &.{"renders", "output.ppm"};
const file_path = std.fmt.comptimePrint("{f}", .{std.fs.path.fmtJoin(img_out_paths)});

const help_entries = [_]ArgHelp {
    .{
        .name = "--renderer",
        .desc = "Choose the rendering algorithm.",
        .default = "Parallel if your system supports multi-threading, Serial otherwise",
        .values = &.{ "Serial", "Parallel" }
    },
    .{
        .name = "--scene",
        .desc = "Choose the scene to render.",
        .default = std.fmt.comptimePrint("{t}", .{default_config.scene_id}),
        .values = &.{ "ProceduralSpheres", "CornellBox", "Quads" }
    },
    .{
        .name = "--img_height",
        .desc = "Choose the output image height.",
        .default = std.fmt.comptimePrint("{}", .{default_config.render_settings.image_height}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--img_width",
        .desc = "Choose the output image width.",
        .default = std.fmt.comptimePrint("{}", .{default_config.render_settings.image_width}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--max-bounces",
        .desc = "Choose the maximum number of traced ray bounces before stopping the recursion.",
        .default = std.fmt.comptimePrint("{}", .{default_config.render_settings.max_ray_bounces}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--samples",
        .desc = "Choose how many times each pixel is sampled (i.e. how many rays are sent through each pixel).",
        .default = std.fmt.comptimePrint("{}", .{default_config.render_settings.samples_per_pixel}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--track-progress",
        .desc =
            \\Track the rendering progress (rendered image rows / total image rows).
            \\This argument acts as a toggle, therefore it does not require any value.
        ,
        .default = std.fmt.comptimePrint("{}", .{default_config.track_progress}),
    },
    .{
        .name = "--time-report",
        .desc =
            \\Log the rendering time once it's finished.
            \\This argument acts as a toggle, therefore it does not require any value.
        ,
        .default = std.fmt.comptimePrint("{}", .{default_config.time_report}),
    }
};

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.DebugAllocator(.{}) {};
    // defer if (gpa.deinit() == .leak) {
    //     @panic("Memory leak detected!");
    // };
    const allocator = init.arena.allocator();

    // Parse args
    var buffer: [16]u8 = undefined;
    const locked_stderr = try init.io.lockStderr(&buffer, null);

    var args_it = try init.minimal.args.iterateAllocator(allocator);

    const app_config = try parseArgs(&args_it, locked_stderr.terminal()) orelse return;
    const render_settings = app_config.render_settings;
    init.io.unlockStderr();
    args_it.deinit();

    // Setup progress tracking
    const root_node: ?std.Progress.Node = if (app_config.track_progress) std.Progress.start(init.io, .{ .root_name = "Scene Render" }) else null;
    defer if (root_node) |n| n.end();

    // Create and setup output file and memory map
    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, file_path);
    defer file.close(init.io);

    const ppm_header_len = fs_utils.computePpmP6HeaderSize(255, render_settings.image_width, render_settings.image_height);
    var memory_map = blk: {
        const height: usize = render_settings.image_height;
        const width: usize = render_settings.image_width;
        const total_size = ppm_header_len + (height * width * 3);

        try file.setLength(init.io, total_size);
        const stat = try file.stat(init.io);

        break :blk try file.createMemoryMap(init.io, .{.len = stat.size });
    };
    defer memory_map.destroy(init.io);

    var buf_writer = std.Io.Writer.fixed(memory_map.memory[0..ppm_header_len]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, render_settings.image_width, render_settings.image_height);

    // Choose rendering algorithm
    var opt_threaded: ?std.Io.Threaded = null;
    defer if (opt_threaded) |*t| t.deinit();

    const renderer: Renderer = switch (app_config.renderer_type) {
        .Parallel => blk: {
            if (comptime builtin.single_threaded) unreachable;

            opt_threaded = std.Io.Threaded.init(allocator, .{});
            break :blk .{ .Parallel = .{
                .io = opt_threaded.?.io(),
                .settings = render_settings,
                .progress_root_node = root_node
            } };
        },
        .Serial => .{ .Serial = .{
            .settings = render_settings,
            .progress_root_node = root_node
        } }
    };

    // Create the context for the rendering pipeline
    const image_size = @as(usize, render_settings.image_width) * @as(usize, render_settings.image_height);
    const linear_color_buf = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(linear_color_buf);

    var ctx = PipelineContext {
        .io = init.io,
        .renderer = renderer,
        .scene = undefined,
        .time_report = app_config.time_report,
        .linear_color_buf = linear_color_buf,
        .out_buf = memory_map.memory[ppm_header_len..],
    };

    // Init the scene and execute the rendering pipeline
    try initAndRenderScene(
        allocator,
        app_config.scene_id,
        render_settings,
        &ctx
    );

    try memory_map.write(init.io);
}

fn parseArgs(args_it: anytype, term: std.Io.Terminal) !?AppConfig {
    assertAnytypeHasDecls(args_it, &.{ "skip", "next" });

    var app_config = AppConfig{};
    const w = term.writer;

    _ = args_it.skip(); // Skip the executable name
    while(args_it.next()) |arg| {
        var split_it = std.mem.splitScalar(u8, arg, '=');
        const arg_name = split_it.first();
        const arg_val = split_it.next();

        if (std.mem.eql(u8, arg_name, "--renderer")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };

            if (std.meta.stringToEnum(RendererType, val_str)) |r| {
                if (r == .Parallel and builtin.single_threaded) {
                    w.print("Error: your system is single-threaded, therefore it can't run the '{s}' algorithm.\n", .{val_str}) catch {};
                    return error.ConcurrencyNotAvailable;
                }
                app_config.renderer_type = r;
            } else {
                w.print("Error: unknown renderer '{s}'. The available options are:\n", .{val_str}) catch {};
                const fields = @typeInfo(RendererType).@"enum".fields;
                inline for (fields) |field| {
                    w.print("- {s}\n", .{field.name}) catch {};
                }

                return error.InvalidArgumentValue;
            }
        }
        else if (std.mem.eql(u8, arg_name, "--scene")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };

            if (std.meta.stringToEnum(SceneId, val_str)) |id| {
                app_config.scene_id = id;
            } else {
                w.print("Error: unknown scene '{s}'. The available options are:\n", .{val_str}) catch {};
                const fields = @typeInfo(SceneId).@"enum".fields;
                inline for (fields) |field| {
                    w.print("- {s}\n", .{field.name}) catch {};
                }

                return error.InvalidArgumentValue;
            }
        }
        else if (std.mem.eql(u8, arg_name, "--img-height")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };
            app_config.render_settings.image_height = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => w.print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, u16Max}) catch {},
                    error.InvalidCharacter => w.print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}) catch {},
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--img-width")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };
            app_config.render_settings.image_width = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => w.print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, u16Max}) catch {},
                    error.InvalidCharacter => w.print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}) catch {},
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--max-bounces")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };
            app_config.render_settings.max_ray_bounces = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => w.print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, u16Max}) catch {},
                    error.InvalidCharacter => w.print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}) catch {},
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--samples")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgumentValue;
            };
            app_config.render_settings.samples_per_pixel = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => w.print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, u16Max}) catch {},
                    error.InvalidCharacter => w.print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}) catch {},
                }
                return err;
            };
            app_config.render_settings.pixel_samples_scale = 1.0 / @as(Float, @floatFromInt(app_config.render_settings.samples_per_pixel));
        }
        else if (std.mem.eql(u8, arg_name, "--track-progress")) {
            if (arg_val != null) {
                w.print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?}) catch {};
                return error.UnexpectedArgumentValue;
            }
            app_config.track_progress = true;
        }
        else if (std.mem.eql(u8, arg_name, "--time-report")) {
            if (arg_val != null) {
                w.print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?}) catch {};
                return error.UnexpectedArgumentValue;
            }
            app_config.time_report = true;
        }
        else if (std.mem.eql(u8, arg_name, "--help")) {
            if (arg_val != null) {
                w.print("Error: the argument '{s}' does not require a value, found '{s}'.\n", .{arg_name, arg_val.?}) catch {};
                return error.UnexpectedArgumentValue;
            }

            printHelp(term);
            return null;
        }
        else {
            w.print("Error: unknown argument '{s}'.\n", .{arg_name}) catch {};
            return error.UnknownArgument;
        }
    }

    return app_config;
}

fn initAndRenderScene(gpa: std.mem.Allocator, scene_id: SceneId, render_settings: RenderSettings, ctx: *PipelineContext) !void {
    switch (scene_id) {
        .ProceduralSpheres => try initAndRenderSpheresScene(gpa, render_settings, ctx),
        .CornellBox => try initAndRenderCornellBox(gpa, render_settings, ctx),
        .Quads => try initAndRenderQuadsScene(gpa, render_settings, ctx),
    }
}

fn printHelp(term: std.Io.Terminal) void {
    const w = term.writer;

    w.writeAll("Whenever an argument expects a value, it can be provided either with the syntax ") catch {};
    term.setColor(.bold) catch {};
    w.writeAll("--<argument>=<value> ") catch {};
    term.setColor(.reset) catch {};
    w.writeAll("or ") catch {};
    term.setColor(.bold) catch {};
    w.writeAll("--<argument> <value>") catch {};
    term.setColor(.reset) catch {};
    w.writeAll(".\nAvailable arguments:\n\n") catch {};

    for (help_entries) |entry| {
        // Name
        term.setColor(.bold) catch {};
        term.setColor(.cyan) catch {};
        w.print("{s}\n", .{entry.name}) catch {};

        // Description
        term.setColor(.reset) catch {};
        var desc_lines = std.mem.splitScalar(u8, entry.desc, '\n');
        while(desc_lines.next()) |line| {
            w.print("    {s}\n", .{line}) catch {};
        }


        // Default
        if (entry.default) |default| {
            w.writeAll("    Defaults to: ") catch {};
            term.setColor(.bright_white) catch {};
            w.print("{s}", .{default}) catch {};
            term.setColor(.reset) catch {};
            w.writeAll(".\n") catch {};
        }

        // Values
        if (entry.values) |values| {
            w.writeAll("    Available values:\n") catch {};

            for (values) |value| {
                w.writeAll("      - ") catch {};
                term.setColor(.yellow) catch {};
                w.print("{s}\n", .{value}) catch {};
                term.setColor(.reset) catch {};
            }
        }

        w.writeAll("\n") catch {};
    }
}

fn initAndRenderSpheresScene(gpa: std.mem.Allocator, render_settings: RenderSettings, ctx: *PipelineContext) !void {
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

    ctx.scene = &scene;
    try executeRenderPipeline(ctx.*);
}

fn initAndRenderQuadsScene(gpa: std.mem.Allocator, render_settings: RenderSettings, ctx: *PipelineContext) !void {
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

    ctx.scene = &scene;
    try executeRenderPipeline(ctx.*);
}

fn initAndRenderCornellBox(gpa: std.mem.Allocator, render_settings: RenderSettings, ctx: *PipelineContext) !void {
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

    ctx.scene = &scene;
    try executeRenderPipeline(ctx.*);
}

test {
    _ = @import("math_utils.zig");
    _ = @import("fs_utils.zig");
    _ = @import("graphics.zig");
    _ = @import("Vec3.zig");
}

const testing = std.testing;

const MockArgIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    pub fn skip(self: *@This()) bool {
        if (self.index < self.args.len) {
            self.index += 1;
            return true;
        }
        return false;
    }

    pub fn next(self: *@This()) ?[]const u8 {
        if (self.index < self.args.len) {
            const arg = self.args[self.index];
            self.index += 1;
            return arg;
        }
        return null;
    }
};

test "parseArgs - default config" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer"} };
    const cfg_opt = try parseArgs(&it, dummy_term);
    try testing.expect(cfg_opt != null);
    const cfg = cfg_opt.?;
    try testing.expectEqual(false, cfg.track_progress);
    try testing.expectEqual(false, cfg.time_report);
}

test "parseArgs - valid boolean flags" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--track-progress", "--time-report"} };
    const cfg_opt = try parseArgs(&it, dummy_term);
    try testing.expect(cfg_opt != null);
    const cfg = cfg_opt.?;
    try testing.expect(cfg.track_progress);
    try testing.expect(cfg.time_report);
}

test "parseArgs - equal syntax" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{
        "zig-pathtracer",
        "--renderer=Serial",
        "--scene=CornellBox",
        "--img-height=720",
        "--img-width=1280",
        "--max-bounces=50",
        "--samples=100"
    } };
    const cfg_opt = try parseArgs(&it, dummy_term);
    try testing.expect(cfg_opt != null);
    const cfg = cfg_opt.?;
    try testing.expectEqual(RendererType.Serial, cfg.renderer_type);
    try testing.expectEqual(SceneId.CornellBox, cfg.scene_id);
    try testing.expectEqual(@as(u16, 720), cfg.render_settings.image_height);
    try testing.expectEqual(@as(u16, 1280), cfg.render_settings.image_width);
    try testing.expectEqual(@as(u16, 50), cfg.render_settings.max_ray_bounces);
    try testing.expectEqual(@as(u16, 100), cfg.render_settings.samples_per_pixel);
    try testing.expectApproxEqAbs(@as(Float, 0.01), cfg.render_settings.pixel_samples_scale, std.math.floatEps(Float));
}

test "parseArgs - space syntax" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{
        "zig-pathtracer",
        "--renderer", "Serial",
        "--scene", "ProceduralSpheres",
        "--img-height", "720",
        "--img-width", "1280",
        "--max-bounces", "50",
        "--samples", "100"
    } };
    const cfg_opt = try parseArgs(&it, dummy_term);
    try testing.expect(cfg_opt != null);
    const cfg = cfg_opt.?;
    try testing.expectEqual(RendererType.Serial, cfg.renderer_type);
    try testing.expectEqual(SceneId.ProceduralSpheres, cfg.scene_id);
    try testing.expectEqual(@as(u16, 720), cfg.render_settings.image_height);
    try testing.expectEqual(@as(u16, 1280), cfg.render_settings.image_width);
}

test "parseArgs - help" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--help"} };
    const cfg_opt = try parseArgs(&it, dummy_term);
    try testing.expect(cfg_opt == null);
}

test "parseArgs - unknown argument" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--unknown-arg"} };
    try testing.expectError(error.UnknownArgument, parseArgs(&it, dummy_term));
}

test "parseArgs - missing value" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--renderer"} };
    try testing.expectError(error.MissingArgument, parseArgs(&it, dummy_term));

    var it2 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--samples"} };
    try testing.expectError(error.MissingArgumentValue, parseArgs(&it2, dummy_term));
}

test "parseArgs - invalid integer" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--img-height=abc"} };
    try testing.expectError(error.InvalidCharacter, parseArgs(&it, dummy_term));
}

test "parseArgs - integer overflow" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--img-width=999999"} };
    try testing.expectError(error.Overflow, parseArgs(&it, dummy_term));
}

test "parseArgs - integer boundary constraints" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    // Exact u16 max
    var it_max = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--img-height=65535"} };
    const cfg_opt = try parseArgs(&it_max, dummy_term);
    try testing.expect(cfg_opt != null);
    try testing.expectEqual(@as(u16, 65535), cfg_opt.?.render_settings.image_height);

    // Negative numbers
    var it_neg = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--img-width=-1"} };
    try testing.expectError(error.Overflow, parseArgs(&it_neg, dummy_term));

    // Zero
    var it_zero = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--max-bounces=0"} };
    const cfg_zero_opt = try parseArgs(&it_zero, dummy_term);
    try testing.expect(cfg_zero_opt != null);
    try testing.expectEqual(@as(u16, 0), cfg_zero_opt.?.render_settings.max_ray_bounces);
}

test "parseArgs - invalid enum values" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it1 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--renderer=FakeRenderer"} };
    try testing.expectError(error.InvalidArgumentValue, parseArgs(&it1, dummy_term));

    var it2 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--scene=FakeScene"} };
    try testing.expectError(error.InvalidArgumentValue, parseArgs(&it2, dummy_term));
}

test "parseArgs - unexpected value for time-report, track_progress and help" {
    var trash_buffer: [4]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&trash_buffer);
    const dummy_term: std.Io.Terminal = .{
        .writer = &dw.writer,
        .mode = .no_color,
    };

    var it1 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--time-report=1"} };
    try testing.expectError(error.UnexpectedArgumentValue, parseArgs(&it1, dummy_term));

    var it2 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--help=true"} };
    try testing.expectError(error.UnexpectedArgumentValue, parseArgs(&it2, dummy_term));

    var it3 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--track-progress=true"} };
    try testing.expectError(error.UnexpectedArgumentValue, parseArgs(&it3, dummy_term));
}


