//! Represents a 3D ray with an origin and direction.

const Ray = @This();

const std = @import("std");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Scene = @import("Scene.zig");
const Float = @import("../../global_config.zig").Float;
const LinearColor = @import("../LinearColor.zig");
const LinearGradient = LinearColor.LinearGradient;
const HitRecord = @import("geometry.zig").HitRecord;
const Interval = math_utils.Interval(Float);

const normalizeFloat = math_utils.normalizeFloat;

/// The starting point of the ray in 3D space.
origin: Vec3,
/// The direction the ray travels in. This does not strictly need to be normalized.
dir: Vec3,

/// Calculates the 3D position along the ray at a given distance parameter `t`.
/// This implements the parametric line equation: `P(t) = origin + t * dir`.
pub fn at(self: Ray, t: Float) Vec3 {
    return self.origin.add(self.dir.scalarMul(t));
}

test "at" {
    const origin = Vec3.init(1.0, 2.0, 3.0);
    const dir = Vec3.init(0.5, 0.0, -0.5);
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
