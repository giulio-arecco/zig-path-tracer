const std = @import("std");
const config = @import("../../../config.zig");
const geometry = @import("../geometry.zig");

const RenderSettings = @import("RenderSettings.zig");
const Scene = @import("../Scene.zig");
const Ray = @import("../Ray.zig");
const Color = @import("../../Color.zig");
const Vec3 = @import("../../../Vec3.zig");
const Float = config.Float;
const Gradient = Color.Gradient;
const HitRecord = geometry.HitRecord;

const rayColorVec3 = Ray.rayColorVec3;

pub const RayTracer = struct {
    settings: RenderSettings,
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: RayTracer, scene: Scene, out: []u8) void {
        const camera = scene.camera;
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        std.debug.print("Viewport Center: {}.\n", .{camera._viewport_center});
        std.debug.print("First pixel position: {}\n", .{camera._pixel_top_left});

        var prng: std.Random.DefaultPrng = .init(@intFromFloat(@round(camera._pixel_top_left.squaredMagnitude())));
        const random = prng.random();

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Serial Ray Tracing", image_height) else null;
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

pub const ParallelRayTracer = struct {
    io: std.Io,
    settings: RenderSettings,
    progress_root_node: ?std.Progress.Node = null,

    pub fn render(self: ParallelRayTracer, scene: Scene, out: []u8) !void {
        const image_width = self.settings.image_width;
        const image_height = self.settings.image_height;

        std.debug.print("Viewport Center: {}.\n", .{scene.camera._viewport_center});
        std.debug.print("First pixel position: {}\n", .{scene.camera._pixel_top_left});

        var group: std.Io.Group = .init;
        defer group.cancel(self.io);

        const task_node: ?std.Progress.Node = if (self.progress_root_node) |root| root.start("Parallel Ray Tracing", image_height) else null;
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

    fn renderRow(self: ParallelRayTracer, scene: Scene, y_screen: usize, row: []u8, progress_node: ?std.Progress.Node) void {
        const camera = scene.camera;
        const image_width = self.settings.image_width;

        var prng: std.Random.DefaultPrng = .init(@intFromFloat(@round(camera._pixel_top_left.squaredMagnitude())));
        const random = prng.random();

        for (0..image_width) |x_screen| {
            const pixel_byte_index = x_screen * 3;
            colorPixel(self.settings, scene, random, x_screen, y_screen, row[pixel_byte_index..][0..3]);
        }

        if (progress_node) |n| n.completeOne();
    }
};

fn colorPixel(settings: RenderSettings, scene: Scene, random: std.Random, x_screen: usize, y_screen: usize, out: *[3]u8) void {
    const camera = scene.camera;
    const samples_per_pixel = settings.samples_per_pixel;
    const pixel_samples_scale = settings.pixel_samples_scale;
    const ray_tmin = settings.ray_tmin;
    const ray_tmax = settings.ray_tmax;

    var pixel_color_sum = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };

    for (0..samples_per_pixel) |sample| {
        const ray = if (sample == 0) camera.getRay(random, x_screen, y_screen, true)
            else camera.getRay(random, x_screen, y_screen, false);

        var closest_t = ray_tmax;
        var closest_hit: ?HitRecord = null;

        for (scene.hittables) |hittable| {
            const hit = hittable.hit(ray, ray_tmin, ray_tmax);
            if (hit) |record| {
                if (record.t < closest_t) {
                    closest_t = record.t;
                    closest_hit = record;
                }
            }
        }

        pixel_color_sum = pixel_color_sum.add(rayColorVec3(ray, closest_hit));
    }

    const pixel_color = Color.fromVec3(pixel_color_sum.scalarMul(pixel_samples_scale));
    std.mem.writeInt(u24, out, pixel_color.toPacked(), .big);
}
