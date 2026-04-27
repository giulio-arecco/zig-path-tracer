const RayTracer = @This();

const std = @import("std");
const config = @import("../../../config.zig");
const geometry = @import("../geometry.zig");

const RenderSettings = @import("RenderSettings.zig");
const Scene = @import("../Scene.zig");
const Ray = @import("../Ray.zig");
const Color = @import("../../Color.zig");
const Float = config.Float;
const Gradient = Color.Gradient;
const HitRecord = geometry.HitRecord;

const ray_color = Ray.ray_color;

settings: RenderSettings,

pub fn render(self: RayTracer, scene: Scene, out: []u8) void {
    const camera = scene.camera;
    const image_width = self.settings.image_width;
    const image_height = self.settings.image_height;
    const ray_tmin = self.settings.ray_tmin;
    const ray_tmax = self.settings.ray_tmax;

    std.debug.print("Viewport Center: {}.\n", .{camera._viewport_center});
    std.debug.print("First pixel position: {}\n", .{camera._pixel_top_left});

    for (0..image_height) |y_screen| {
        for (0..image_width) |x_screen| {
            const pixel = camera._pixel_top_left.
                add(camera._pixel_delta_u.scalarMul(@floatFromInt(x_screen))).
                add(camera._pixel_delta_v.scalarMul(@floatFromInt(y_screen)));

            const ray = Ray {
                .origin = camera._pos,
                .dir = pixel.sub(camera._pos),
            };

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

            const pixel_color = ray_color(ray, closest_hit);

            const pixel_byte_index = (y_screen * image_width + x_screen) * 3;
            std.mem.writeInt(u24, out[pixel_byte_index..][0..3], pixel_color.toPacked(), .big);
        }
    }
}
