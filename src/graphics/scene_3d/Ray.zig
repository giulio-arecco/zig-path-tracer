const Ray = @This();

const std = @import("std");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Scene = @import("Scene.zig");
const Float = @import("../../config.zig").Float;
const LinearColor = @import("../LinearColor.zig");
const LinearGradient = LinearColor.LinearGradient;
const HitRecord = @import("geometry.zig").HitRecord;
const Interval = math_utils.Interval;

const normalizeFloat = math_utils.normalizeFloat;

origin: Vec3,
dir: Vec3,

pub fn at(self: Ray, t: Float) Vec3 {
    return self.origin.add(self.dir.scalarMul(t));
}

pub fn rayColorVec3(ray: Ray, scene: Scene, ray_tmin: Float, ray_tmax: Float, depth: u16, rand: std.Random) LinearColor {
    if (depth <= 0) {
        return LinearColor.black;
    }

    const hit = scene.hit(ray, ray_tmin, ray_tmax);

    if (hit) |record| {
        const res = record.material.scatter(ray, record, rand);

        if (res.scattered_ray) |scattered_ray| {
            return rayColorVec3(scattered_ray, scene, ray_tmin, ray_tmax, depth - 1, rand).mul(res.attenuation);
        }

        return LinearColor.black;
    }

    const grad = LinearGradient {
        .start_color = LinearColor.white,
        .end_color = LinearColor.init(0.25, 0.5, 1.0)
    };

    const normalized_dir = ray.dir.normalized();
    return grad.at(0.5 * (normalized_dir.y + 1.0));
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
