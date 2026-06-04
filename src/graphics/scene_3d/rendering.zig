const std = @import("std");
const config = @import("../../global_config.zig");
const geometry = @import("geometry.zig");
const math_utils = @import("../../math_utils.zig");
const post_processing = @import("../post_processing.zig");

const Scene = @import("Scene.zig");
const Ray = @import("Ray.zig");
const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Camera = @import("Camera.zig");
const Material = @import("materials.zig").Material;
const Denoiser = post_processing.Denoiser;
const DenoiserContext = post_processing.DenoiserContext;
const DisplayTransform = post_processing.DisplayTransform;
const AppConfig = config.AppConfig;
const Interval = math_utils.Interval(Float);
const Float = config.Float;
const HitRecord = geometry.HitRecord;

const print = std.debug.print;
const colorRecomposition = post_processing.colorRecomposition;
const getRecompositionAlbedo = post_processing.getRecompositionAlbedo;

pub const RendererType = enum { Serial, Parallel };

pub const GBuffers = struct {
    albedo_buf: []LinearColor,
    normal_buf: []Vec3,
    depth_buf: []Float,
    roughness_buf: []Float
};

pub const GBuffersReadOnly = struct {
    albedo_buf: []const LinearColor,
    normal_buf: []const Vec3,
    depth_buf: []const Float,
    roughness_buf: []const Float
};

pub const FrameBuffers = struct {
    diffuse_buf: []LinearColor,
    specular_buf: []LinearColor,
    emission_buf: []LinearColor,
    g_buffers: GBuffers,
    ping_pong_buf_1: []LinearColor,
    // ping_pong_buf_2: []LinearColor,
    out_buf: []u8
};

pub const FrameBuffersRenderView = struct {
    diffuse_buf: []LinearColor,
    specular_buf: []LinearColor,
    emission_buf: []LinearColor,
    g_buffers: GBuffers
};

pub const PostProcessingPipeline = struct {
    denoiser: ?Denoiser = null,
    display_transform: DisplayTransform,
};

pub const PipelineContext = struct {
    io: std.Io,
    renderer: Renderer,
    post_processing_pipeline: PostProcessingPipeline,
    frame_buffers: FrameBuffers,
    image_height: u16,
    image_width: u16,
    scene: *const Scene,
    time_report: bool = false,
};

pub const UserRenderSettings = struct {
    image_width: u16 = 600,
    image_height: u16 = 600,
    ray_t_range: Interval = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
    max_ray_bounces: u16 = 50,
    samples_per_pixel: u16 = 200,
};

pub const InternalRenderSettings = struct {
    image_width: u16,
    image_height: u16,
    ray_t_range: Interval,
    max_ray_bounces: u16,
    samples_per_pixel: u16,
    sqrt_spp: u16,
    recip_sqrt_spp: Float,
    /// Color scale factor for a sum of pixel samples. A value of `1.0 / samples_per_pixel` leads to the pixel color being the average of the sampled colors.
    pixel_samples_scale: Float = 1.0 / @as(Float, @floatFromInt(200)),

    pub fn compile(settings: UserRenderSettings) InternalRenderSettings {
        const sqrt_spp: u16 = std.math.sqrt(settings.samples_per_pixel);
        return .{
            .image_width = settings.image_width,
            .image_height = settings.image_height,
            .ray_t_range = settings.ray_t_range,
            .max_ray_bounces = settings.max_ray_bounces,
            .samples_per_pixel = settings.samples_per_pixel,
            .sqrt_spp = sqrt_spp,
            .recip_sqrt_spp = 1.0 / @as(Float, @floatFromInt(sqrt_spp)),
            .pixel_samples_scale = 1.0 / @as(Float, @floatFromInt(settings.samples_per_pixel))
        };
    }

    pub fn getAspectRatio(self: InternalRenderSettings) f32 {
        const f_width: f32 = @floatFromInt(self.image_width);
        const f_height: f32 = @floatFromInt(self.image_height);

        return f_width / f_height;
    }
};

pub const SplitIrradiance = struct {
    diffuse: LinearColor,
    specular: LinearColor,
    emission: LinearColor,

    pub const allBlack = SplitIrradiance{
        .diffuse = LinearColor.black,
        .specular = LinearColor.black,
        .emission = LinearColor.black
    };

    pub fn add(a: SplitIrradiance, b: SplitIrradiance) SplitIrradiance {
        return .{
            .diffuse = a.diffuse.add(b.diffuse),
            .specular = a.specular.add(b.specular),
            .emission = a.emission.add(b.emission),
        };
    }

    pub fn initDiffuse(diffuse: LinearColor) SplitIrradiance {
        return .{
            .diffuse = diffuse,
            .specular = LinearColor.black,
            .emission = LinearColor.black
        };
    }

    pub fn initSpecular(specular: LinearColor) SplitIrradiance {
        return .{
            .diffuse = LinearColor.black,
            .specular = specular,
            .emission = LinearColor.black
        };
    }

    pub fn initEmission(emission: LinearColor) SplitIrradiance {
        return .{
            .diffuse = LinearColor.black,
            .specular = LinearColor.black,
            .emission = emission
        };
    }
};

pub const Renderer = union(RendererType) {
    Serial: SerialPathTracer,
    Parallel: ParallelPathTracer,

    pub fn render(self: Renderer, scene: *const Scene, buffers: FrameBuffersRenderView) !void {
        switch (self) {
            inline else => |renderer| return renderer.render(scene, buffers)
        }
    }
};

pub const SerialPathTracer = struct {
    settings: InternalRenderSettings,
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: SerialPathTracer, scene: *const Scene, buffers: FrameBuffersRenderView) void {
        const camera = scene.camera;
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        var prng: std.Random.DefaultPrng = .init(@intFromFloat(@round(camera._pixel_top_left.squaredMagnitude())));
        const random = prng.random();

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Serial Path Tracer", image_height) else null;
        defer if (task_node) |n| n.end();

        for (0..image_height) |y_screen| {
            for (0..image_width) |x_screen| {
                const pixel_index = y_screen * image_width + x_screen;

                const rayToCenter = camera.getRayToCenter(x_screen, y_screen);
                updateFrameBuffers(scene, rayToCenter, self.settings.ray_t_range, pixel_index, buffers);

                const split_irrad = colorPixel(self.settings, scene, random, x_screen, y_screen);

                buffers.diffuse_buf[pixel_index] = split_irrad.diffuse;
                buffers.specular_buf[pixel_index] = split_irrad.specular;
                buffers.emission_buf[pixel_index] = split_irrad.emission;
            }

            if (task_node) |n| n.completeOne();
        }
    }
};

pub const ParallelPathTracer = struct {
    io: std.Io,
    settings: InternalRenderSettings,
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: ParallelPathTracer, scene: *const Scene, buffers: FrameBuffersRenderView) !void {
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        var group: std.Io.Group = .init;
        defer group.cancel(self.io);

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Parallel Path Tracer", image_height) else null;
        defer if (task_node) |n| n.end();

        for (0..image_height) |y_screen| {
            const start = y_screen * image_width;
            const end = start + image_width;
            const row_buffers = FrameBuffersRenderView {
                .diffuse_buf = buffers.diffuse_buf[start..end],
                .specular_buf = buffers.specular_buf[start..end],
                .emission_buf = buffers.emission_buf[start..end],
                .g_buffers = .{
                    .albedo_buf = buffers.g_buffers.albedo_buf[start..end],
                    .normal_buf = buffers.g_buffers.normal_buf[start..end],
                    .depth_buf = buffers.g_buffers.depth_buf[start..end],
                    .roughness_buf = buffers.g_buffers.roughness_buf[start..end]
                }

            };

            group.concurrent(self.io, renderRow, .{ self, scene, y_screen, row_buffers, task_node }) catch |err| switch (err) {
                error.ConcurrencyUnavailable => |e| {
                    std.debug.print("Error: concurrency unavailable\n", .{});
                    return e;
                },
            };
        }

        try group.await(self.io);
    }

    fn renderRow(self: ParallelPathTracer, scene: *const Scene, y_screen: usize, row_buffers: FrameBuffersRenderView, progress_node: ?std.Progress.Node) void {
        const camera = scene.camera;
        const image_width = self.settings.image_width;

        const base_seed: u64 = @intFromFloat(@round(camera._pixel_top_left.squaredMagnitude()));

        // Hash the base seed with the row index to guarantee a strong avalanche effect.
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&base_seed));
        hasher.update(std.mem.asBytes(&y_screen));

        var prng: std.Random.DefaultPrng = .init(hasher.final());
        const random = prng.random();

        for (0..image_width) |x_screen| {
            const pixel_index = x_screen;

            const rayToCenter = camera.getRayToCenter(x_screen, y_screen);
            updateFrameBuffers(scene, rayToCenter, self.settings.ray_t_range, pixel_index, row_buffers);

            const split_irrad = colorPixel(self.settings, scene, random, x_screen, y_screen);

            row_buffers.diffuse_buf[pixel_index] = split_irrad.diffuse;
            row_buffers.specular_buf[pixel_index] = split_irrad.specular;
            row_buffers.emission_buf[pixel_index] = split_irrad.emission;
        }

        if (progress_node) |n| n.completeOne();
    }
};

fn updateFrameBuffers(scene: *const Scene, ray: Ray, ray_t_range: Interval, index: usize, buffers: FrameBuffersRenderView) void {
    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) {
        // Black albedo prevents sub-pixel irradiance leaks during recomposition.
        // Infinite depth acts as a mathematical wall for the denoiser's spatial edge-stopping.
        buffers.g_buffers.albedo_buf[index] = LinearColor.black;
        buffers.g_buffers.normal_buf[index] = ray.dir.normalized();
        buffers.g_buffers.depth_buf[index]  = std.math.inf(Float);
        buffers.g_buffers.roughness_buf[index] = 0.0; // The background is considered emissive
        return;
    }

    buffers.g_buffers.albedo_buf[index] = getRecompositionAlbedo(hit_record.material);
    buffers.g_buffers.normal_buf[index] = hit_record.normal;
    buffers.g_buffers.depth_buf[index] = hit_record.t;
    buffers.g_buffers.roughness_buf[index] = hit_record.material.getRoughness();
}

pub fn executeRenderPipeline(ctx: PipelineContext) !void {
    const buf_len = ctx.frame_buffers.diffuse_buf.len;
    std.debug.assert(ctx.frame_buffers.specular_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.emission_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.g_buffers.albedo_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.g_buffers.normal_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.g_buffers.depth_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.g_buffers.roughness_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.ping_pong_buf_1.len == buf_len);
    // std.debug.assert(ctx.frame_buffers.ping_pong_buf_2.len == buf_len);
    std.debug.assert(ctx.frame_buffers.out_buf.len == buf_len);
    std.debug.assert(ctx.image_height > 0);
    std.debug.assert(ctx.image_width > 0);

    var time_start: std.Io.Timestamp = undefined;
    var time_end: std.Io.Timestamp = undefined;
    var duration: i96 = undefined;

    print("Render started.\n", .{});
    if (ctx.time_report) time_start = std.Io.Clock.awake.now(ctx.io);

    try renderStep(ctx.scene, ctx.renderer, .{
        .diffuse_buf = ctx.frame_buffers.diffuse_buf,
        .specular_buf = ctx.frame_buffers.specular_buf,
        .emission_buf = ctx.frame_buffers.emission_buf,
        .g_buffers = .{
            .albedo_buf = ctx.frame_buffers.g_buffers.albedo_buf,
            .normal_buf = ctx.frame_buffers.g_buffers.normal_buf,
            .depth_buf = ctx.frame_buffers.g_buffers.depth_buf,
            .roughness_buf = ctx.frame_buffers.g_buffers.roughness_buf
        }
    });

    if (ctx.time_report) {
        time_end = std.Io.Clock.awake.now(ctx.io);
        duration = time_start.durationTo(time_end).toNanoseconds();
    }

    print("Render completed successfully.\n", .{});

    if (ctx.time_report) {
        print("Render step: {}s, ({}ms).\n", .{
            @divTrunc(duration, std.time.ns_per_s),
            @divTrunc(duration, std.time.ns_per_ms),
        });
    }

    print("Post-process started.\n", .{});
    if (ctx.time_report) time_start = std.Io.Clock.awake.now(ctx.io);

    try postProcessStep(ctx.post_processing_pipeline, ctx.io, ctx.scene.camera, ctx.frame_buffers, ctx.image_height, ctx.image_width);

    if (ctx.time_report) {
        time_end = std.Io.Clock.awake.now(ctx.io);
        duration = time_start.durationTo(time_end).toNanoseconds();
    }

    print("Post-process completed successfully.\n", .{});

    if (ctx.time_report) {
        print("Post-process step: {}s, ({}ms).\n", .{
            @divTrunc(duration, std.time.ns_per_s),
            @divTrunc(duration, std.time.ns_per_ms),
        });
    }
}

fn renderStep(scene: *const Scene, renderer: Renderer, buffers: FrameBuffersRenderView) !void {
    return renderer.render(scene, buffers);
}

fn postProcessStep(pipeline: PostProcessingPipeline, io: std.Io, camera: Camera, frame_buffers: FrameBuffers, image_height: u16, image_width: u16,) !void {
    var denoiser_ctx = DenoiserContext {
        .io = io,
        .camera = camera,
        .in_out_buf = frame_buffers.diffuse_buf,
        .ping_pong_buf = frame_buffers.ping_pong_buf_1,
        .is_specular = false,
        .g_buffers = .{
            .albedo_buf = frame_buffers.g_buffers.albedo_buf,
            .normal_buf = frame_buffers.g_buffers.normal_buf,
            .depth_buf = frame_buffers.g_buffers.depth_buf,
            .roughness_buf = frame_buffers.g_buffers.roughness_buf,
        },
        .image_height = image_height,
        .image_width = image_width
    };

    if (pipeline.denoiser) |d| {
        try d.apply(denoiser_ctx);

        denoiser_ctx.in_out_buf = frame_buffers.specular_buf;
        denoiser_ctx.is_specular = true;

        try d.apply(denoiser_ctx);
    }

    colorRecomposition(frame_buffers.diffuse_buf, frame_buffers.specular_buf, frame_buffers.emission_buf, frame_buffers.g_buffers.albedo_buf, frame_buffers.ping_pong_buf_1);

    pipeline.display_transform.apply(frame_buffers.ping_pong_buf_1, frame_buffers.out_buf);
}

fn colorPixel(settings: InternalRenderSettings, scene: *const Scene, random: std.Random, x_screen: usize, y_screen: usize) SplitIrradiance {
    const camera = scene.camera;
    const pixel_samples_scale = settings.pixel_samples_scale;
    const ray_t_range = settings.ray_t_range;
    const max_depth = settings.max_ray_bounces;

    var pixel_split_irrad = SplitIrradiance {
        .diffuse = LinearColor.black,
        .specular = LinearColor.black,
        .emission = LinearColor.black,
    };

    for(0..settings.sqrt_spp) |sample_j| {
        for (0..settings.sqrt_spp) |sample_i| {
            const ray = camera.getRay(random, x_screen, y_screen, sample_i, sample_j);
            const color_data = tracePrimaryRay(ray, scene, ray_t_range, max_depth, random);
            pixel_split_irrad = pixel_split_irrad.add(color_data);
        }
    }

    pixel_split_irrad.diffuse = pixel_split_irrad.diffuse.scalarMul(pixel_samples_scale);
    pixel_split_irrad.specular = pixel_split_irrad.specular.scalarMul(pixel_samples_scale);
    pixel_split_irrad.emission = pixel_split_irrad.emission.scalarMul(pixel_samples_scale);
    return pixel_split_irrad;
}

fn tracePrimaryRay(ray: Ray, scene: *const Scene, ray_t_range: Interval, depth: u16, rand: std.Random) SplitIrradiance {
    if (depth == 0) {
        return SplitIrradiance.allBlack;
    }

    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) return .initEmission(scene.bg_color);

    var result = SplitIrradiance.allBlack;

    result.emission = hit_record.material.emit() orelse LinearColor.black;

    if (hit_record.material.scatter(ray, hit_record, rand)) |res| {
        const incoming_light = rayColor(res.scattered_ray, scene, ray_t_range, depth - 1, rand);
        switch (res.scatter_type) {
            // Diffuse accumulates pure irradiance (albedo is applied later in the pipeline).
            .diffuse => result.diffuse = incoming_light,
            // Specular relies on view-dependent attenuation. We apply it right away to bake the reflection color.
            .specular => result.specular = incoming_light.mul(res.attenuation),
        }
    }

    return result;
}

fn rayColor(ray: Ray, scene: *const Scene, ray_t_range: Interval, depth: u16, rand: std.Random) LinearColor {
    if (depth == 0) {
        return LinearColor.black;
    }

    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) return scene.bg_color;

    const scatterRes = hit_record.material.scatter(ray, hit_record, rand);
    const color_from_scatter = if (scatterRes) |res|
        rayColor(res.scattered_ray, scene, ray_t_range, depth - 1, rand).mul(res.attenuation)
    else
        LinearColor.black;

    const color_from_emission = hit_record.material.emit() orelse LinearColor.black;
    return color_from_scatter.add(color_from_emission);
}

test "InternalRenderSettings.getAspectRatio" {
    const rs1 = InternalRenderSettings.compile(.{ .image_width = 1920, .image_height = 1080, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .max_ray_bounces = 10 });
    try std.testing.expectApproxEqAbs(1.7777777, rs1.getAspectRatio(), 0.000001);

    const rs2 = InternalRenderSettings.compile(.{ .image_width = 800, .image_height = 600, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .max_ray_bounces = 10 });
    try std.testing.expectApproxEqAbs(1.3333333, rs2.getAspectRatio(), 0.000001);

    const rs3 = InternalRenderSettings.compile(.{ .image_width = 1000, .image_height = 1000, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .max_ray_bounces = 10 });
    try std.testing.expectApproxEqAbs(1.0, rs3.getAspectRatio(), 0.000001);
}
