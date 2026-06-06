//! High Dynamic Range (HDR) Linear Color Representation.
//!
//! Uses floating-point values to represent unbounded light energy in a scene.
//! Unlike standard 8-bit RGB (where values are clamped to [0, 255] or [0.0, 1.0] and gamma-corrected),
//! linear colors accurately accumulate and scale radiant energy during physically-based rendering without
//! loss of precision or premature clipping.

const LinearColor = @This();

const std = @import("std");
const config = @import("../global_config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Color = @import("Color.zig");
const Interval = math_utils.Interval(Float);

const approxEq = math_utils.approxEq;
const normalizeFloat = math_utils.normalizeFloat;
const rescaleFloat = math_utils.rescaleFloat;

v: @Vector(3, Float),

/// Initialize a pure black LinearColor (0, 0, 0)
pub const black = LinearColor { .v = @splat(0.0) };

/// Initialize a pure white LinearColor (1, 1, 1)
pub const white = LinearColor { .v = @splat(1.0) };

/// Represents a smooth linear transition between two linear colors.
pub const LinearGradient = struct {
    start_color: LinearColor,
    end_color: LinearColor,
    t_range: Interval = .{ .min = 0.0, .max = 1.0 },

    /// Calculates the interpolated `LinearColor` value at the given progression t.
    pub fn at(self: LinearGradient, t: Float) LinearColor {
        std.debug.assert(self.t_range.contains(t));

        const norm_t = normalizeFloat(Float, t, self.t_range);
        const t_vec: @Vector(3, Float) = @splat(norm_t);
        const one_minus_t: @Vector(3, Float) = @splat(1.0 - norm_t);

        return .{ .v = (self.start_color.v * one_minus_t) + (self.end_color.v * t_vec) };
    }
};

pub fn init(red: Float, green: Float, blue: Float) LinearColor {
    return .{ .v = .{ red, green, blue } };
}

/// Retrieves the raw red intensity component.
pub fn r(self: LinearColor) Float {
    return self.v[0];
}

/// Retrieves the raw green intensity component.
pub fn g(self: LinearColor) Float {
    return self.v[1];
}

/// Retrieves the raw blue intensity component.
pub fn b(self: LinearColor) Float {
    return self.v[2];
}

/// Ensures the color vector does not contain corrupted values like NaN or negative energy.
pub fn isValid(self: LinearColor) bool {
    const is_valid = @reduce(.And, self.v >= @as(@Vector(3, Float), @splat(0.0))) and
                     !std.math.isNan(self.v[0]) and !std.math.isNan(self.v[1]) and !std.math.isNan(self.v[2]) and
                     !std.math.isInf(self.v[0]) and !std.math.isInf(self.v[1]) and !std.math.isInf(self.v[2]);
    return is_valid;
}

pub fn add(self: LinearColor, other: LinearColor) LinearColor {
    return .{ .v = self.v + other.v };
}

pub fn mul(self: LinearColor, other: LinearColor) LinearColor {
    return .{ .v = self.v * other.v };
}

pub fn div(self: LinearColor, other: LinearColor) LinearColor {
    return .{ .v = self.v / other.v };
}

pub fn scalarMul(self: LinearColor, scalar: Float) LinearColor {
    const s_vec: @Vector(3, Float) = @splat(scalar);
    return .{ .v = self.v * s_vec };
}

pub fn scalarDiv(self: LinearColor, scalar: Float) LinearColor {
    std.debug.assert(scalar != 0.0);
    const s_vec: @Vector(3, Float) = @splat(scalar);
    return .{ .v = self.v / s_vec };
}

pub fn random(rand: std.Random) LinearColor {
    return .init(rand.float(Float), rand.float(Float), rand.float(Float));
}

pub fn randomInRange(rand: std.Random, range: Interval) LinearColor {
    return .init(
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, range),
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, range),
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, range)
    );
}

// TESTING
pub fn expectLinearColorApproxEq(lhs: LinearColor, rhs: LinearColor, tolerance: Float) !void {
    try std.testing.expectApproxEqAbs(lhs.v[0], rhs.v[0], tolerance);
    try std.testing.expectApproxEqAbs(lhs.v[1], rhs.v[1], tolerance);
    try std.testing.expectApproxEqAbs(lhs.v[2], rhs.v[2], tolerance);
}

const eps = std.math.floatEps(Float);

test "LinearColor.init" {
    const c = LinearColor.init(0.1, 0.5, 0.9);
    try std.testing.expectEqual(@as(Float, 0.1), c.v[0]);
    try std.testing.expectEqual(@as(Float, 0.5), c.v[1]);
    try std.testing.expectEqual(@as(Float, 0.9), c.v[2]);
}

test "LinearColor.isValid" {
    try std.testing.expect(LinearColor.init(0.0, 0.5, 100.0).isValid());
    try std.testing.expect(!LinearColor.init(-0.1, 0.5, 1.0).isValid());
    try std.testing.expect(!LinearColor.init(std.math.nan(Float), 0.5, 1.0).isValid());
    try std.testing.expect(!LinearColor.init(std.math.inf(Float), 0.5, 1.0).isValid());
}

test "LinearColor - Math operations" {
    const c1 = LinearColor.init(0.2, 0.4, 0.6);
    const c2 = LinearColor.init(0.1, 0.2, 0.3);

    try expectLinearColorApproxEq(LinearColor.init(0.3, 0.6, 0.9), c1.add(c2), eps);
    try expectLinearColorApproxEq(LinearColor.init(0.02, 0.08, 0.18), c1.mul(c2), eps);
    try expectLinearColorApproxEq(LinearColor.init(2.0, 2.0, 2.0), c1.div(c2), eps);
    try expectLinearColorApproxEq(LinearColor.init(0.4, 0.8, 1.2), c1.scalarMul(2.0), eps);
    try expectLinearColorApproxEq(LinearColor.init(0.1, 0.2, 0.3), c1.scalarDiv(2.0), eps);
}

test "LinearGradient.at" {
    const grad = LinearGradient{
        .start_color = LinearColor.init(0.0, 0.0, 0.0),
        .end_color = LinearColor.init(2.0, 4.0, 6.0),
        .t_range = .{ .min = 0.0, .max = 10.0 }
    };

    const mid = grad.at(5.0);
    try expectLinearColorApproxEq(LinearColor.init(1.0, 2.0, 3.0), mid, eps);
}

