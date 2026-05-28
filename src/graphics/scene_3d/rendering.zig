const std = @import("std");
const config = @import("../../global_config.zig");
const geometry = @import("geometry.zig");
const math_utils = @import("../../math_utils.zig");

const Scene = @import("Scene.zig");
const Ray = @import("Ray.zig");
const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Interval = math_utils.Interval(Float);
const Float = config.Float;
const HitRecord = geometry.HitRecord;

pub const RendererType = enum { Serial, Parallel };

pub const RenderSettings = struct {
    image_width: u16 = 600,
    image_height: u16 = 600,
    ray_t_range: Interval = .{ .min = 0.001, .max = std.math.inf(Float) }, // Avoid min == 0.0 to prevent shadow acne
    max_ray_bounces: u16 = 50,
    samples_per_pixel: u16 = 200,
    /// Color scale factor for a sum of pixel samples. A value of `1.0 / samples_per_pixel` leads to the pixel color being the average of the sampled colors.
    pixel_samples_scale: Float = 1.0 / @as(Float, @floatFromInt(200)),

    pub fn getAspectRatio(self: RenderSettings) f32 {
        const f_width: f32 = @floatFromInt(self.image_width);
        const f_height: f32 = @floatFromInt(self.image_height);

        return f_width / f_height;
    }
};

pub const Renderer = union(RendererType) {
    Serial: SerialPathTracer,
    Parallel: ParallelPathTracer,

    pub fn render(self: Renderer, scene: *const Scene, out: []u8) !void {
        switch (self) {
            inline else => |renderer| return renderer.render(scene, out)
        }
    }
};

pub const SerialPathTracer = struct {
    settings: RenderSettings = .{},
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: SerialPathTracer, scene: *const Scene, out: []u8) void {
        const camera = scene.camera;
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        var prng: std.Random.DefaultPrng = .init(@intFromFloat(@round(camera._pixel_top_left.squaredMagnitude())));
        const random = prng.random();

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Serial Path Tracer", image_height) else null;
        defer if (task_node) |n| n.end();

        for (0..image_height) |y_screen| {
            for (0..image_width) |x_screen| {
                const pixel_byte_index = (y_screen * image_width + x_screen) * 3;
                colorPixel(self.settings, scene, random, x_screen, y_screen, out[pixel_byte_index..][0..3]);
            }

            if (task_node) |n| n.completeOne();
        }
    }
};

pub const ParallelPathTracer = struct {
    io: std.Io,
    settings: RenderSettings = .{},
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: ParallelPathTracer, scene: *const Scene, out: []u8) !void {
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        var group: std.Io.Group = .init;
        defer group.cancel(self.io);

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Parallel Path Tracer", image_height) else null;
        defer if (task_node) |n| n.end();

        for (0..image_height) |y_screen| {
            const start = y_screen * image_width * 3;
            const end = start + image_width * 3;
            const row = out[start..end];

            group.concurrent(self.io, renderRow, .{ self, scene, y_screen, row, task_node }) catch |err| switch (err) {
                error.ConcurrencyUnavailable => {
                    std.debug.print("Error: concurrency unavailable\n", .{});
                    return;
                },
            };
        }

        try group.await(self.io);
    }

    fn renderRow(self: ParallelPathTracer, scene: *const Scene, y_screen: usize, row: []u8, progress_node: ?std.Progress.Node) void {
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
            const pixel_byte_index = x_screen * 3;
            colorPixel(self.settings, scene, random, x_screen, y_screen, row[pixel_byte_index..][0..3]);
        }

        if (progress_node) |n| n.completeOne();
    }
};

fn colorPixel(settings: RenderSettings, scene: *const Scene, random: std.Random, x_screen: usize, y_screen: usize, out: *[3]u8) void {
    const camera = scene.camera;
    const samples_per_pixel = settings.samples_per_pixel;
    const pixel_samples_scale = settings.pixel_samples_scale;
    const ray_t_range = settings.ray_t_range;
    const max_depth = settings.max_ray_bounces;

    var pixel_color_sum = LinearColor.black;

    for (0..samples_per_pixel) |sample| {
        const ray = if (sample == 0) camera.getRay(random, x_screen, y_screen, true)
            else camera.getRay(random, x_screen, y_screen, false);

        pixel_color_sum = pixel_color_sum.add(rayColor(ray, scene, ray_t_range, max_depth, random));
    }

    const pixel_color = blk: {
        const linear = pixel_color_sum.scalarMul(pixel_samples_scale);
        const srgb = linear.toSrgb8bit(.{ .clamp = .{} });
        break :blk srgb;
    };

    std.mem.writeInt(u24, out, pixel_color.toPacked(), .big);
}

fn rayColor(ray: Ray, scene: *const Scene, ray_t_range: Interval, depth: u16, rand: std.Random) LinearColor {
    if (depth == 0) {
        return LinearColor.black;
    }

    var hit_record: HitRecord = undefined;
    const hit = scene.hit(ray, ray_t_range, &hit_record);

    if (!hit) {
        return scene.bg_color;

        // const grad = LinearGradient {
        //     .start_color = LinearColor.white,
        //     .end_color = LinearColor.init(0.25, 0.5, 1.0)
        // };

        // const normalized_dir = ray.dir.normalized();
        // return grad.at(0.5 * (normalized_dir.y + 1.0));
    }


    const scatterRes = hit_record.material.scatter(ray, hit_record, rand);
    const color_from_scatter = if (scatterRes) |res|
        rayColor(res.scattered_ray, scene, ray_t_range, depth - 1, rand).mul(res.attenuation)
    else
        LinearColor.black;

    const color_from_emission = hit_record.material.emit() orelse LinearColor.black;
    return color_from_scatter.add(color_from_emission);
}

test "RenderSettings.getAspectRatio" {
    const rs1 = RenderSettings{ .image_width = 1920, .image_height = 1080, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    try std.testing.expectApproxEqAbs(1.7777777, rs1.getAspectRatio(), 0.000001);

    const rs2 = RenderSettings{ .image_width = 800, .image_height = 600, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    try std.testing.expectApproxEqAbs(1.3333333, rs2.getAspectRatio(), 0.000001);

    const rs3 = RenderSettings{ .image_width = 1000, .image_height = 1000, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    try std.testing.expectApproxEqAbs(1.0, rs3.getAspectRatio(), 0.000001);
}
