const std = @import("std");
const config = @import("../../global_config.zig");
const geometry = @import("geometry.zig");
const math_utils = @import("../../math_utils.zig");
const post_processing = @import("../post_processing.zig");

const Scene = @import("Scene.zig");
const Ray = @import("Ray.zig");
const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Denoiser = post_processing.Denoiser;
const DisplayTransform = post_processing.DisplayTransform;
const AppConfig = config.AppConfig;
const Interval = math_utils.Interval(Float);
const Float = config.Float;
const HitRecord = geometry.HitRecord;

const print = std.debug.print;
const colorRecomposition = post_processing.colorRecomposition;
const getRecompositionAlbedo = post_processing.getRecompositionAlbedo;

pub const RendererType = enum { Serial, Parallel };

pub const FrameBuffers = struct {
    irrad_buf: []LinearColor,
    albedo_buf: []LinearColor,
    normal_buf: []Vec3,
    depth_buf: []Float,
    pp_temp_1: []LinearColor,
    pp_temp_2: []LinearColor,
    out_buf: []u8
};

pub const FrameBuffersRenderView = struct {
    irrad_buf: []LinearColor,
    albedo_buf: []LinearColor,
    normal_buf: []Vec3,
    depth_buf: []Float,
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

pub const PostProcessingPipeline = struct {
    denoiser: ?Denoiser = null,
    display_transform: DisplayTransform,
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

                colorPixel(self.settings, scene, random, x_screen, y_screen, &buffers.irrad_buf[pixel_index]);
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
                .irrad_buf = buffers.irrad_buf[start..end],
                .albedo_buf = buffers.albedo_buf[start..end],
                .normal_buf = buffers.normal_buf[start..end],
                .depth_buf = buffers.depth_buf[start..end],
            };

            group.concurrent(self.io, renderRow, .{ self, scene, y_screen, row_buffers, task_node }) catch |err| switch (err) {
                error.ConcurrencyUnavailable => {
                    std.debug.print("Error: concurrency unavailable\n", .{});
                    return;
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

            colorPixel(self.settings, scene, random, x_screen, y_screen, &row_buffers.irrad_buf[pixel_index]);
        }

        if (progress_node) |n| n.completeOne();
    }
};

fn updateFrameBuffers(scene: *const Scene, ray: Ray, ray_t_range: Interval, index: usize, buffers: FrameBuffersRenderView) void {
    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) {
        buffers.albedo_buf[index] = LinearColor.white;
        buffers.normal_buf[index] = ray.dir.normalized();
        buffers.depth_buf[index]  = 0.0;
        return;
    }

    buffers.albedo_buf[index] = getRecompositionAlbedo(hit_record.material);
    buffers.normal_buf[index] = hit_record.normal;

    const depth = -Vec3.dot(scene.camera._forward, hit_record.point.sub(ray.origin));
    std.debug.assert(depth > 0.0);
    const inv_depth = 1.0 / (depth + 2 * std.math.floatEps(Float));

    buffers.depth_buf[index] = inv_depth;
}

pub fn executeRenderPipeline(ctx: PipelineContext) !void {
    const buf_len = ctx.frame_buffers.irrad_buf.len;
    std.debug.assert(ctx.frame_buffers.albedo_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.normal_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.depth_buf.len == buf_len);
    std.debug.assert(ctx.frame_buffers.pp_temp_1.len == buf_len);
    std.debug.assert(ctx.frame_buffers.pp_temp_2.len == buf_len);
    std.debug.assert(ctx.frame_buffers.out_buf.len == buf_len);
    std.debug.assert(ctx.image_height > 0);
    std.debug.assert(ctx.image_width > 0);

    var time_start: std.Io.Timestamp = undefined;
    var time_end: std.Io.Timestamp = undefined;
    var duration: i96 = undefined;

    print("Render started.\n", .{});
    if (ctx.time_report) time_start = std.Io.Clock.awake.now(ctx.io);

    try renderStep(ctx.scene, ctx.renderer, .{
        .irrad_buf = ctx.frame_buffers.irrad_buf,
        .albedo_buf = ctx.frame_buffers.albedo_buf,
        .normal_buf = ctx.frame_buffers.normal_buf,
        .depth_buf = ctx.frame_buffers.depth_buf,
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

    postProcessStep(ctx.post_processing_pipeline, ctx.frame_buffers, ctx.image_height, ctx.image_width);

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

fn postProcessStep(pipeline: PostProcessingPipeline, frame_buffers: FrameBuffers, image_height: u16, image_width: u16,) void {
    var curr_in: []const LinearColor = frame_buffers.irrad_buf;
    var curr_out = frame_buffers.pp_temp_1;
    var unused_buf = frame_buffers.pp_temp_2;

    if (pipeline.denoiser) |d| {
        d.apply(.{
            .in_irrad = curr_in,
            .temp_buf = unused_buf,
            .out_irrad = curr_out,
            .albedo = frame_buffers.albedo_buf,
            .normal = frame_buffers.normal_buf,
            .depth = frame_buffers.depth_buf,
            .image_height = image_height,
            .image_width = image_width
        });

        curr_in = curr_out;
        std.mem.swap([]LinearColor, &curr_out, &unused_buf);
    }

    colorRecomposition(frame_buffers.albedo_buf, curr_in, curr_out);
    curr_in = curr_out;
    std.mem.swap([]LinearColor, &curr_out, &unused_buf);

    pipeline.display_transform.apply(curr_in, frame_buffers.out_buf);
}

fn colorPixel(settings: InternalRenderSettings, scene: *const Scene, random: std.Random, x_screen: usize, y_screen: usize, out_color: *LinearColor) void {
    const camera = scene.camera;
    const pixel_samples_scale = settings.pixel_samples_scale;
    const ray_t_range = settings.ray_t_range;
    const max_depth = settings.max_ray_bounces;

    var pixel_irradiance_sum = LinearColor.black;

    for(0..settings.sqrt_spp) |sample_j| {
        for (0..settings.sqrt_spp) |sample_i| {
            const ray = camera.getRay(random, x_screen, y_screen, sample_i, sample_j);
            pixel_irradiance_sum = pixel_irradiance_sum.add(tracePrimaryRay(ray, scene, ray_t_range, max_depth, random));
        }
    }

    out_color.* = pixel_irradiance_sum.scalarMul(pixel_samples_scale);
}

fn tracePrimaryRay(ray: Ray, scene: *const Scene, ray_t_range: Interval, depth: u16, rand: std.Random) LinearColor {
    if (depth == 0) {
        return LinearColor.black;
    }

    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) return scene.bg_color;

    const scatterRes = hit_record.material.scatter(ray, hit_record, rand);
    const color_from_scatter = if (scatterRes) |res|
        // We avoid multiplying by the first hit material attenuation to keep the irradiance information
        rayColor(res.scattered_ray, scene, ray_t_range, depth - 1, rand)
    else
        LinearColor.black;

    const color_from_emission = hit_record.material.emit() orelse LinearColor.black;
    return color_from_scatter.add(color_from_emission);
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
