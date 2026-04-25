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

settings: RenderSettings,

pub fn renderSingleHittable(self: RayTracer, scene: Scene, out: []u8) void {
    const camera = scene.camera;
    const image_width = self.settings.image_width;
    const image_height = self.settings.image_height;

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

            const hit = scene.hittable.hit(ray, 0.0, std.math.inf(Float));
            const pixel_color = ray_color(ray, hit);

            const pixel_byte_index = (y_screen * image_width + x_screen) * 3;
            std.mem.writeInt(u24, out[pixel_byte_index..][0..3], pixel_color.toPacked(), .big);
        }
    }
}

fn ray_color(ray: Ray, hit: ?HitRecord) Color {
    if (hit) |record| {
        return Color.fromFloats(Float, record.normal.x, record.normal.y, record.normal.z, -1.0, 1.0);
    }

    const grad = Gradient(Float) {
        .start_color = .{ .r = 255, .g = 255, .b = 255 },
        .end_color = .{ .r = 128, .g = 180, .b = 255 }
    };

    const norm_dir = ray.dir.normalized();
    return grad.at(0.5 * (norm_dir.y + 1.0));
}
