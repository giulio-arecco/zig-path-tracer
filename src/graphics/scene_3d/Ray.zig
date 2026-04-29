const Ray = @This();

const std = @import("std");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Scene = @import("Scene.zig");
const Float = @import("../../config.zig").Float;
const Color = @import("../Color.zig");
const Gradient = Color.Gradient;
const HitRecord = @import("geometry.zig").HitRecord;
const Interval = math_utils.Interval;

const normalizeFloat = math_utils.normalizeFloat;

origin: Vec3,
dir: Vec3,

pub fn at(self: Ray, t: Float) Vec3 {
    return self.origin.add(self.dir.scalarMul(t));
}

// pub fn rayColor(ray: Ray, hit: ?HitRecord) Color {
//     if (hit) |record| {
//         return Color.fromFloats(Float, record.normal.x, record.normal.y, record.normal.z, -1.0, 1.0);
//     }

//     const grad = Gradient(Float) {
//         .start_color = .{ .r = 255, .g = 255, .b = 255 },
//         .end_color = .{ .r = 128, .g = 180, .b = 255 }
//     };

//     const norm_dir = ray.dir.normalized();
//     return grad.at(0.5 * (norm_dir.y + 1.0));
// }

pub fn rayColorVec3(ray: Ray, scene: Scene, ray_tmin: Float, ray_tmax: Float, depth: u16, rand: std.Random) Vec3 {
    if (depth <= 0) {
        return .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    }

    const hit = scene.hit(ray, ray_tmin, ray_tmax);

    if (hit) |record| {
        const new_dir = record.normal.add(Vec3.randomNormalized(rand)); // Lambertian reflection
        const new_ray = Ray { .origin = record.point, .dir = new_dir };
        return rayColorVec3(new_ray, scene, ray_tmin, ray_tmax, depth - 1, rand).scalarMul(0.5);
    }

    const grad = Gradient(Float) {
        .start_color = .{ .r = 255, .g = 255, .b = 255 },
        .end_color = .{ .r = 128, .g = 180, .b = 255 }
    };

    const norm_dir = ray.dir.normalized();
    return grad.at(0.5 * (norm_dir.y + 1.0)).toVec3();
}

test "at" {
    const origin = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const dir = Vec3{ .x = 0.5, .y = 0.0, .z = -0.5 };
    const ray = Ray{ .origin = origin, .dir = dir };
    const absEps = 2 * std.math.floatEps(Float);

    const p0 = ray.at(0.0);
    try std.testing.expectApproxEqAbs(origin.x, p0.x, absEps);
    try std.testing.expectApproxEqAbs(origin.y, p0.y, absEps);
    try std.testing.expectApproxEqAbs(origin.z, p0.z, absEps);

    const p1 = ray.at(2.0);
    try std.testing.expectApproxEqAbs(2.0, p1.x, absEps);
    try std.testing.expectApproxEqAbs(2.0, p1.y, absEps);
    try std.testing.expectApproxEqAbs(2.0, p1.z, absEps);

    const p2 = ray.at(-2.0);
    try std.testing.expectApproxEqAbs(0.0, p2.x, absEps);
    try std.testing.expectApproxEqAbs(2.0, p2.y, absEps);
    try std.testing.expectApproxEqAbs(4.0, p2.z, absEps);
}
