// const ParallelRayTracer = @This();

// const std = @import("std");
// const config = @import("../../../config.zig");
// const geometry = @import("../geometry.zig");

// const RenderSettings = @import("RenderSettings.zig");
// const Scene = @import("../Scene.zig");
// const Ray = @import("../Ray.zig");
// const Color = @import("../../Color.zig");
// const Float = config.Float;
// const Gradient = Color.Gradient;
// const HitRecord = geometry.HitRecord;

// const rayColor = Ray.rayColor;

// io: std.Io,
// settings: RenderSettings,

// pub fn render(self: ParallelRayTracer, scene: Scene, out: []u8) !void {
//     const image_width = self.settings.image_width;
//     const image_height = self.settings.image_height;

//     std.debug.print("Viewport Center: {}.\n", .{scene.camera._viewport_center});
//     std.debug.print("First pixel position: {}\n", .{scene.camera._pixel_top_left});

//     var group: std.Io.Group = .init;
//     defer group.cancel(self.io);

//     for (0..image_height) |y_screen| {
//         const start = y_screen * image_width * 3;
//         const end = start + image_width * 3;
//         const row = out[start..end];

//         group.concurrent(self.io, renderRow, .{ self, scene, y_screen, row }) catch |err| switch (err) {
//             error.ConcurrencyUnavailable => {
//                 std.debug.print("Error: concurrency unavailable\n", .{});
//                 return;
//             },
//         };
//     }

//     try group.await(self.io);
// }

// fn renderRow(self: ParallelRayTracer, scene: Scene, y_screen: usize, row: []u8) void {
//     const camera = scene.camera;
//     const image_width = self.settings.image_width;
//     const ray_tmin = self.settings.ray_tmin;
//     const ray_tmax = self.settings.ray_tmax;

//     for (0..image_width) |x_screen| {
//         const pixel = camera._pixel_top_left.
//             add(camera._pixel_delta_u.scalarMul(@floatFromInt(x_screen))).
//             add(camera._pixel_delta_v.scalarMul(@floatFromInt(y_screen)));

//         const ray = Ray {
//             .origin = camera._pos,
//             .dir = pixel.sub(camera._pos),
//         };

//         var closest_t = ray_tmax;
//         var closest_hit: ?HitRecord = null;
//         for (scene.hittables) |hittable| {
//             const hit = hittable.hit(ray, ray_tmin, ray_tmax);
//             if (hit) |record| {
//                 if (record.t < closest_t) {
//                     closest_t = record.t;
//                     closest_hit = record;
//                 }
//             }
//         }

//         const pixel_color = rayColor(ray, closest_hit);

//         const pixel_byte_index = x_screen * 3;
//         std.mem.writeInt(u24, row[pixel_byte_index..][0..3], pixel_color.toPacked(), .big);
//     }
// }
