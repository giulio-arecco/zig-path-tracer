const std = @import("std");
const builtin = @import("builtin");
const graphics = @import("graphics.zig");
const fs_utils = @import("fs_utils.zig");
const type_utils = @import("type_utils.zig");
const config = @import("global_config.zig");
const rendering = graphics.scene_3d.rendering;
const materials = graphics.scene_3d.materials;
const post_processing = graphics.post_processing;
const math_utils = @import("math_utils.zig");

const Vec3 = @import("Vec3.zig");
const SceneId = config.SceneId;
const DenoiserType = config.DenoiserType;
const AppConfig = config.AppConfig;
const LinearColor = graphics.LinearColor;
const Scene = graphics.scene_3d.Scene;
const Camera = graphics.scene_3d.Camera;
const Hittable = graphics.scene_3d.geometry.Hittable;
const DisplayTransform = post_processing.DisplayTransform;
const Denoiser = post_processing.Denoiser;
const FrameBuffers = rendering.FrameBuffers;
const PipelineContext = rendering.PipelineContext;
const UserRenderSettings = rendering.UserRenderSettings;
const InternalRenderSettings = rendering.InternalRenderSettings;
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

/// Meta-information about a supported CLI argument to standardize formatted `--help` output.
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
const maxSceneIdLen = blk: {
    var max: usize = 0;
    for(@typeInfo(SceneId).@"enum".fields) |f| {
        const len = f.name.len;
        if (len > max) max = len;
    }
    break :blk max;
};

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
        .values = &.{ "ProceduralSpheres", "CornellBox", "Quads", "Final" }
    },
    .{
        .name = "--img-height",
        .desc = "Choose the output image height.",
        .default = std.fmt.comptimePrint("{}", .{default_config.user_render_settings.image_height}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--img-width",
        .desc = "Choose the output image width.",
        .default = std.fmt.comptimePrint("{}", .{default_config.user_render_settings.image_width}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--max-bounces",
        .desc = "Choose the maximum number of traced ray bounces before stopping the recursion.",
        .default = std.fmt.comptimePrint("{}", .{default_config.user_render_settings.max_ray_bounces}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--samples",
        .desc = "Choose how many times each pixel is sampled (i.e. how many rays are sent through each pixel).",
        .default = std.fmt.comptimePrint("{}", .{default_config.user_render_settings.samples_per_pixel}),
        .values = &.{ std.fmt.comptimePrint("Any integer between 0 and {}", .{u16Max}) }
    },
    .{
        .name = "--denoiser",
        .desc = "Choose a denoiser.",
        .default = std.fmt.comptimePrint("{t}", .{default_config.denoiser_type}),
        .values = &.{ "None", "JointBilateral", "ATrous" }
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
    },
};

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.DebugAllocator(.{}) {};
    // defer if (gpa.deinit() == .leak) {
    //     @panic("Memory leak detected!");
    // };
    // const allocator = gpa.allocator();
    const allocator = init.arena.allocator();

    // Parse args
    const app_config = blk: {
        var buffer: [32]u8 = undefined;
        const locked_stderr = try init.io.lockStderr(&buffer, null);
        defer init.io.unlockStderr();

        var args_it = try init.minimal.args.iterateAllocator(allocator);
        defer args_it.deinit();

        break :blk try parseArgs(&args_it, locked_stderr.terminal()) orelse return;
    };
    const urs = app_config.user_render_settings;

    // Setup progress tracking
    const root_name_end = " Scene Render";
    var buf: [maxSceneIdLen + root_name_end.len]u8 = undefined;
    const root_name = try std.fmt.bufPrint(&buf, "{t}{s}", .{ app_config.scene_id, root_name_end });

    const root_node = if (app_config.track_progress) std.Progress.start(init.io, .{ .root_name = root_name }) else null;
    defer if (root_node) |n| n.end();

    // Create and setup output file and memory map
    const cwd = std.Io.Dir.cwd();
    const file = try createImgFile(init.io, cwd, file_path);
    defer file.close(init.io);

    const ppm_header_len = fs_utils.computePpmP6HeaderSize(255, urs.image_width, urs.image_height);

    // Explicitly sizes the file, then establishes a direct OS-level memory mapping
    // accommodating the header and RGB pixel data to circumvent buffered disk writes.
    var memory_map = blk: {
        const height: usize = urs.image_height;
        const width: usize = urs.image_width;
        const total_size = ppm_header_len + (height * width * 3);

        try file.setLength(init.io, total_size);
        const stat = try file.stat(init.io);

        break :blk try file.createMemoryMap(init.io, .{.len = stat.size });
    };
    defer memory_map.destroy(init.io);

    var buf_writer = std.Io.Writer.fixed(memory_map.memory[0..ppm_header_len]);
    const writer = &buf_writer;
    try fs_utils.writePpmP6Header(writer, 255, urs.image_width, urs.image_height);

    // Choose rendering algorithm
    var opt_threaded: ?std.Io.Threaded = if (!builtin.single_threaded) std.Io.Threaded.init(allocator, .{}) else null;
    defer if (opt_threaded) |*t| t.deinit();

    const renderer: Renderer = switch (app_config.renderer_type) {
        .Parallel => blk: {
            if (comptime builtin.single_threaded) unreachable;

            break :blk .{
                .settings = InternalRenderSettings.compile(urs),
                .backend = .{ .Parallel = .{} }
            };
        },
        .Serial => .{
            .settings = InternalRenderSettings.compile(urs),
            .backend = .{ .Serial = .{} }
        }
    };

    // Create the context for the rendering pipeline
    const image_size = @as(usize, urs.image_width) * @as(usize, urs.image_height);
    const diffuse_buf = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(diffuse_buf);

    const specular_buf = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(specular_buf);

    const emission_buf = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(emission_buf);

    const albedo_buf = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(albedo_buf);

    const normal_buf = try allocator.alloc(Vec3, image_size);
    defer allocator.free(normal_buf);

    const depth_buf = try allocator.alloc(Float, image_size);
    defer allocator.free(depth_buf);

    const roughness_buf = try allocator.alloc(Float, image_size);
    defer allocator.free(roughness_buf);

    const image_sized_buf_1 = try allocator.alloc(LinearColor, image_size);
    defer allocator.free(image_sized_buf_1);

    // const image_sized_buf_2 = try allocator.alloc(LinearColor, image_size);
    // defer allocator.free(image_sized_buf_2);

    var ctx = PipelineContext {
        .io = if (opt_threaded) |*t| t.io() else init.io,
        .progress_node = root_node,
        .renderer = renderer,
        .post_processing_pipeline = .{
            .denoiser = switch (app_config.denoiser_type) {
                .None => null,
                .JointBilateral => .{ .joint_bilateral_denoiser = .{
                    .kernel_size = 15,
                    .sigma_space = 3.5,
                    .sigma_normal = 0.15,
                    .sigma_depth = 0.04,
                    .diffuse_sigma_luma = 0.12,
                    .specular_sigma_luma = 0.3
                }},
                .ATrous => .{ .atrous_denoiser = .{
                    .diffuse_iterations = 5,
                    .specular_iterations = 3,
                    .sigma_normal = 0.15,
                    .sigma_depth = 0.04,
                    .diffuse_sigma_luma = 0.12,
                    .specular_sigma_luma = 0.3
                }},
            },
            .display_transform = .{
                .tone_mapper = .{ .extended_reinhard = .{ .white = 4.0 } },
                .transform_type = .toSrgb8bit
            },
        },
        .frame_buffers = .{
            .diffuse_buf = diffuse_buf,
            .specular_buf = specular_buf,
            .emission_buf = emission_buf,
            .g_buffers = .{
                .albedo_buf = albedo_buf,
                .normal_buf = normal_buf,
                .depth_buf = depth_buf,
                .roughness_buf = roughness_buf
            },
            .ping_pong_buf_1 = image_sized_buf_1,
            // .ping_pong_buf_2 = image_sized_buf_2,
            .out_buf = memory_map.memory[ppm_header_len..],
        },
        .scene = undefined,
        .time_report = app_config.time_report,
        .image_height = urs.image_height,
        .image_width = urs.image_width
    };

    // Init the scene and execute the rendering pipeline
    try initAndRenderScene(
        allocator,
        app_config.scene_id,
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
            app_config.user_render_settings.image_height = std.fmt.parseInt(u16, val_str, 10) catch |err| {
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
            app_config.user_render_settings.image_width = std.fmt.parseInt(u16, val_str, 10) catch |err| {
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
            app_config.user_render_settings.max_ray_bounces = std.fmt.parseInt(u16, val_str, 10) catch |err| {
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
            app_config.user_render_settings.samples_per_pixel = std.fmt.parseInt(u16, val_str, 10) catch |err| {
                switch (err) {
                    error.Overflow => w.print("Error: the value for argument '{s}' must be an integer between 0 and {}.\n", .{arg_name, u16Max}) catch {},
                    error.InvalidCharacter => w.print("Error: the argument '{s}' requires a positive integer value, found '{s}' instead.\n", .{arg_name, val_str}) catch {},
                }
                return err;
            };
        }
        else if (std.mem.eql(u8, arg_name, "--denoiser")) {
            const val_str = arg_val orelse args_it.next() orelse {
                w.print("Error: missing value for '{s}'.\n", .{arg_name}) catch {};
                return error.MissingArgument;
            };

            if (std.meta.stringToEnum(DenoiserType, val_str)) |denoiser_t| {
                app_config.denoiser_type = denoiser_t;
            } else {
                w.print("Error: unknown scene '{s}'. The available options are:\n", .{val_str}) catch {};
                const fields = @typeInfo(DenoiserType).@"enum".fields;
                inline for (fields) |field| {
                    w.print("- {s}\n", .{field.name}) catch {};
                }

                return error.InvalidArgumentValue;
            }
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

/// Routes the selected scene identifier to its hardcoded creation subroutine.
fn initAndRenderScene(gpa: std.mem.Allocator, scene_id: SceneId, ctx: *PipelineContext) !void {
    switch (scene_id) {
        .ProceduralSpheres => try initAndRenderSpheresScene(gpa, ctx),
        .CornellBox => try initAndRenderCornellBox(gpa, ctx),
        .Quads => try initAndRenderQuadsScene(gpa, ctx),
        .Final => try initAndRenderFinalScene(gpa, ctx)
    }
}

/// Prints formatted, colorized text to the terminal, displaying valid command-line flags.
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

fn initAndRenderSpheresScene(gpa: std.mem.Allocator, ctx: *PipelineContext) !void {
    const camera = Camera.initLookAt(
        .init(13.0, 2.0, 3.0),
        .init(0.0, 0.0, 0.0),
        20.0,
        10.0,
        0.6,
        ctx.renderer.settings.image_width,
        ctx.renderer.settings.image_height,
        ctx.renderer.settings.recip_sqrt_spp
    );

    var scene = try Scene.initWithCapacity(camera, .init(0.7, 0.8, 1.0), gpa, 256);
    defer scene.deinit();

    const big_radius: Float = 1.0;
    const small_radius: Float = 0.2;

    const ground_material = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.5, 0.5, 0.5) } });
    const center_ground = Vec3.init(0.0, -1000.0, 0.0);
    try scene.add(Hittable.createSphere(center_ground, 1000, ground_material));

    const material_1 = try scene.createMaterial(.{ .dielectric = .{ .refractive_index = 1.5 } });
    const center_1 = Vec3.init(0.0, 1.0, 0.0);
    try scene.add(Hittable.createSphere(center_1, 1.0, material_1));

    const material_1_inside = try scene.createMaterial(.{ .dielectric = .{ .refractive_index = 1.0 / 1.5 } });
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
                    const dielectric = try scene.createMaterial(.{ .dielectric = .{ .refractive_index = 1.5 } });
                    try scene.add(Hittable.createSphere(center, small_radius, dielectric));
                }
            }
        }
    }

    try scene.buildBvh(4);

    ctx.scene = &scene;
    try executeRenderPipeline(ctx.*);
}

fn initAndRenderQuadsScene(gpa: std.mem.Allocator, ctx: *PipelineContext) !void {
    const camera = Camera.initLookAt(
        .init(0.0, 0.0, 9.0),
        .init(0.0, 0.0, 0.0),
        80.0,
        10.0,
        0.0,
        ctx.renderer.settings.image_width,
        ctx.renderer.settings.image_height,
        ctx.renderer.settings.recip_sqrt_spp
    );

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

fn initAndRenderCornellBox(gpa: std.mem.Allocator, ctx: *PipelineContext) !void {
    const camera = Camera.initLookAt(
        .init(278.0, 278.0, -800.0),
        .init(278.0, 278.0, 0.0),
        40.0,
        10.0,
        0.0,
        ctx.renderer.settings.image_width,
        ctx.renderer.settings.image_height,
        ctx.renderer.settings.recip_sqrt_spp
    );

    var scene = try Scene.initWithCapacity(camera, LinearColor.black, gpa, 8);
    defer scene.deinit();

    // Materials
    const red   = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.65, 0.05, 0.05) } });
    const white = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.73, 0.73, 0.73) } });
    const green = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.12, 0.45, 0.15) } });
    const light = try scene.createMaterial(.{ .diffuse_light = .{ .color = .init(10.0, 10.0, 10.0) } });
    const glass = try scene.createMaterial(.{ .dielectric = .{ .refractive_index = 1.5 } });
    // const metal = try scene.createMaterial(.{ .metal = .{ .albedo = .init(0.73, 0.73, 0.73), .fuzz = 0.9 } });

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

fn initAndRenderFinalScene(gpa: std.mem.Allocator, ctx: *PipelineContext) !void {
    const camera = Camera.initLookAt(
        .init(478.0, 278.0, -600.0),
        .init(278.0, 278.0, 0.0),
        40.0,
        632.0,
        0.0,
        ctx.renderer.settings.image_width,
        ctx.renderer.settings.image_height,
        ctx.renderer.settings.recip_sqrt_spp
    );

    var scene = Scene.init(camera, LinearColor.black, gpa);
    defer scene.deinit();

    var prng: std.Random.DefaultPrng = .init(121);
    const rand = prng.random();

    // Materials
    const ground = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.48, 0.83, 0.53) } });
    const light = try scene.createMaterial(.{ .diffuse_light = .{ .color = .init(9.0, 9.0, 9.0) } });
    const white = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.73, 0.73, 0.73) } });
    const wall_lambertian = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.05, 0.05, 0.05) } });
    const sphere_lambertian = try scene.createMaterial(.{ .lambertian = .{ .albedo = .init(0.7, 0.3, 0.1) } });
    const sphere_glass = try scene.createMaterial(.{ .dielectric = .{ .refractive_index = 1.5 } });
    const sphere_fuzzy_metal = try scene.createMaterial(.{ .metal = .{ .albedo = .init(0.8, 0.8, 0.9), .fuzz = 1.0 } });
    const sphere_glossy_metal = try scene.createMaterial(.{ .metal = .{ .albedo = .init(0.1, 0.1, 1.0), .fuzz = 0.0 } });

    // Primitives
    const boxes_per_side: usize = 20;
    for (0..boxes_per_side) |i| {
        for(0..boxes_per_side) |j| {
            const w: Float = 100.0;
            const x0 = -1000.0 + @as(Float, @floatFromInt(i)) * w;
            const z0 = -1000.0 + @as(Float, @floatFromInt(j)) * w;
            const y0: Float = 0.0;
            const x1 = x0 + w;
            const y1 = math_utils.rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0 }, .{ .min = 1.0, .max = 101.0 });
            const z1 = z0 + w;

            try scene.add(try Hittable.createBox(.init(x0, y0, z0), .init(x1, y1, z1), ground, gpa));
        }
    }

    const base: Float = 1900.0;
    const height: Float = 550.0;
    const quad_size: Float = 50.0;
    const xz_quads = @as(usize, @intFromFloat(base / quad_size));
    const y_quads = @as(usize, @intFromFloat(height / quad_size));

    // Back wall
    for (0..xz_quads) |i| {
        for (0..y_quads) |j| {
            try scene.add(Hittable.createQuad(
                .init(900.0 - quad_size * @as(Float, @floatFromInt(i)), quad_size * @as(Float, @floatFromInt(j)), 900.0),
                .init(-quad_size, 0.0, 0.0), .init(0.0, quad_size, 0.0),
                wall_lambertian)
            );
        }
    }

    // Top wall
    for (0..xz_quads) |i| {
        for (0..xz_quads) |j| {
            try scene.add(Hittable.createQuad(
                .init(900.0 - quad_size * @as(Float, @floatFromInt(i)), height, 900.0 - quad_size * @as(Float, @floatFromInt(j))),
                .init(-quad_size, 0.0, 0.0), .init(0.0, 0.0, -quad_size),
                wall_lambertian)
            );
        }
    }

    try scene.add(Hittable.createQuad(.init(123.0, 549.0, 147.0), .init(300.0, 0.0, 0.0), .init(0.0, 0.0, 265.0), light));
    try scene.add(Hittable.createSphere(.init(400.0, 400.0, 200.0), 50.0, sphere_lambertian));
    try scene.add(Hittable.createSphere(.init(260.0, 150.0, 45.0), 50.0, sphere_glass));
    try scene.add(Hittable.createSphere(.init(375.0, 230.0, 175.0), 75.0, sphere_glossy_metal));
    try scene.add(Hittable.createSphere(.init(0.0, 150.0, 145.0), 50.0, sphere_fuzzy_metal));

    const ns: usize = 1000;
    for (0..ns) |_| {
        var sphere = Hittable.createSphere(.randomInRange(rand, 0.0, 165.0), 10.0, white);
        sphere = try sphere.rotateY(15.0, gpa);
        sphere = try sphere.translate(.init(-100.0, 270.0, 395.0), gpa);
        try scene.add(sphere);
    }

    try scene.buildBvh(4);

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
        "--denoiser=JointBilateral",
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
    try testing.expectEqual(DenoiserType.JointBilateral, cfg.denoiser_type);
    try testing.expectEqual(@as(u16, 720), cfg.user_render_settings.image_height);
    try testing.expectEqual(@as(u16, 1280), cfg.user_render_settings.image_width);
    try testing.expectEqual(@as(u16, 50), cfg.user_render_settings.max_ray_bounces);
    try testing.expectEqual(@as(u16, 100), cfg.user_render_settings.samples_per_pixel);
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
        "--denoiser", "ATrous",
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
    try testing.expectEqual(DenoiserType.ATrous, cfg.denoiser_type);
    try testing.expectEqual(@as(u16, 720), cfg.user_render_settings.image_height);
    try testing.expectEqual(@as(u16, 1280), cfg.user_render_settings.image_width);
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

    var it3 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--denoiser"} };
    try testing.expectError(error.MissingArgument, parseArgs(&it3, dummy_term));
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
    try testing.expectEqual(@as(u16, 65535), cfg_opt.?.user_render_settings.image_height);

    // Negative numbers
    var it_neg = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--img-width=-1"} };
    try testing.expectError(error.Overflow, parseArgs(&it_neg, dummy_term));

    // Zero
    var it_zero = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--max-bounces=0"} };
    const cfg_zero_opt = try parseArgs(&it_zero, dummy_term);
    try testing.expect(cfg_zero_opt != null);
    try testing.expectEqual(@as(u16, 0), cfg_zero_opt.?.user_render_settings.max_ray_bounces);
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

    var it3 = MockArgIterator{ .args = &[_][]const u8{"zig-pathtracer", "--denoiser=FakeDenoiser"} };
    try testing.expectError(error.InvalidArgumentValue, parseArgs(&it3, dummy_term));
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


