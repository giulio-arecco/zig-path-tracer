//! Fundamental math routines and logical data structures.
//! Handles arbitrary numeric types dynamically at compile time.

const std = @import("std");
const maxInt = std.math.maxInt;
const floatMax = std.math.floatMax;
const floatEps = std.math.floatEps;
const sqrt = std.math.sqrt;
const inf = std.math.inf;
const nan = std.math.nan;


/// Evaluates equivalence between values with an adaptive layer of robustness against floating-point drift.
/// It combines strict bitwise equality for integers and a structured absolute-then-relative error bounds check for floating points.
pub fn approxEq(comptime T: type, x: T, y: T) bool {
    switch (@typeInfo(T)) {
        .float, .comptime_float => {
            if (std.math.isNan(x) or std.math.isNan(y)) return false;

            if (x == y) return true;

            // Inf equality is checked with the previous if statement. If we get here, x and y
            // are either inf with opposite signs, or at least one of them is not inf.
            if (std.math.isInf(x) or std.math.isInf(y)) return false;

            // Try the absolute equality first
            if (std.math.approxEqAbs(T, x, y, 2 * floatEps(T))) {
                return true;
            }
            // If the absolute difference is too big, try relative equality
            return std.math.approxEqRel(T, x, y, @sqrt(floatEps(T)));
        },
        .int, .comptime_int => return x == y,
        else => @compileError("approxEq not implemented for " ++ @typeName(T)),
    }
}

/// Evaluates a second-grade linear equation discriminant and returns a tuple classifying the root count alongside the computed discriminant itself.
/// Prevents catastrophic cancellation and avoids unstable evaluation near zero by factoring machine epsilon against the magnitude bounds of the local coefficients.
pub fn evaluateDiscriminant(comptime T: type, a: T, b: T, c: T) struct {u8, T} {
    // TODO: Consider checking if a or c are == 1 to avoid a multiplication branch
    switch (@typeInfo(T)) {
        .int => |int_info| {
            if (int_info.signedness == .unsigned) {
                @compileError("The integer type T must be signed (i.e. i32), found '" ++ @typeName(T) ++ "'.");
            }

            const b_sq = b * b;
            const discr = b_sq - 4 * a * c;

            if (discr > 0) {
                return .{ 2, discr };
            }
            else if (discr == 0) {
                return .{ 1, discr };
            }
            else {
                return .{ 0, discr };
            }
        },
        .comptime_int => {
            const b_sq = b * b;
            const discr = b_sq - 4 * a * c;

            if (discr > 0) {
                return .{ 2, discr };
            }
            else if (discr == 0) {
                return .{ 1, discr };
            }
            else {
                return .{ 0, discr };
            }
        },
        .float => {
            std.debug.assert(!std.math.isNan(a));
            std.debug.assert(!std.math.isNan(b));
            std.debug.assert(!std.math.isNan(c));

            const b_sq = b * b;
            // Computes the discriminant `b^2 - 4ac` using hardware FMA to limit intermediate round-off errors.
            const discr = @mulAdd(T, -4.0 * a, c, b_sq);

            // Dynamically derives a precision threshold scaling with the highest magnitude terms
            // to accurately distinguish an effective zero root.
            const max_magnitude = @max(@abs(b_sq), @abs(4.0 * a * c));
            const tolerance: T = 2.0;
            const eps = std.math.floatEpsAt(T, max_magnitude) * tolerance;

            if (discr > eps) {
                return .{ 2, discr };
            }
            else if (discr >= -eps) {
                return .{ 1, 0.0 };
            }
            else {
                return .{ 0, discr };
            }
        },
        else => @compileError("Type parameter T must be float, comptime_float, int or comptime_int, received '" ++ @typeName(T) ++ "'.")
    }
}

/// Evaluates a "reduced" quadratic discriminant for cases where the 'b' coefficient is evenly
/// divisible by 2 (represented as 'h' where b = 2h). This avoids the '4' and '2' multipliers,
/// saving multiplications.
pub fn evaluateDiscriminantReduced(comptime T: type, a: T, h: T, c: T) struct {u8, T} {
    switch (@typeInfo(T)) {
        .int => |int_info| {
            if (int_info.signedness == .unsigned) {
                @compileError("The integer type T must be signed (i.e. i32), found '" ++ @typeName(T) ++ "'.");
            }

            const h_sq = h * h;
            const discr = h_sq - a * c;

            if (discr > 0) {
                return .{ 2, discr };
            }
            else if (discr == 0) {
                return .{ 1, discr };
            }
            else {
                return .{ 0, discr };
            }
        },
        .comptime_int => {
            const h_sq = h * h;
            const discr = h_sq - a * c;

            if (discr > 0) {
                return .{ 2, discr };
            }
            else if (discr == 0) {
                return .{ 1, discr };
            }
            else {
                return .{ 0, discr };
            }
        },
        .float => {
            std.debug.assert(!std.math.isNan(a));
            std.debug.assert(!std.math.isNan(h));
            std.debug.assert(!std.math.isNan(c));

            const h_sq = h * h;
            const discr = @mulAdd(T, -a, c, h_sq);

            const max_magnitude = @max(@abs(h_sq), @abs(a*c));
            const tolerance: T = 2.0;
            const eps = std.math.floatEpsAt(T, max_magnitude) * tolerance;

            if (discr > eps) {
                return .{ 2, discr };
            }
            else if (discr >= -eps) {
                return .{ 1, 0.0 };
            }
            else {
                return .{ 0, discr };
            }
        },
        else => @compileError("Type parameter T must be float or int, received '" ++ @typeName(T) ++ "'.")
    }
}

/// Closed numeric interval `[min, max]`.
pub fn Interval(comptime T: type) type {
    switch (@typeInfo(T)) {
        .int, .float => {},
        else => @compileError("T must be a numeric type (i.e. float, int), found '" ++ @typeName(T) ++ "'.")
    }

    return struct {
        const Self = @This();

        min: T,
        max: T,

        /// Create the interval tightly enclosing the two input intervals
        pub fn initEncloseTwo(a: Self, b: Self) Self {
            return .{
                .min = if (a.min <= b.min) a.min else b.min,
                .max = if (a.max >= b.max) a.max else b.max
            };
        }

        /// Calculates the absolute distance between the min and max limits.
        pub fn size(self: Self) T {
            return self.max - self.min;
        }

        /// Evaluates if the value lies tightly within or on the boundary of the interval.
        pub fn contains(self: Self, x: T) bool {
            return x >= self.min and x <= self.max;
        }

        /// Evaluates if the value is strictly constrained between, but not on, the interval boundaries.
        pub fn surrounds(self: Self, x: T) bool {
            return x > self.min and x < self.max;
        }

        /// Calculates the linearly proportional value within the target range corresponding to the given value in the current interval.
        pub fn rescaleValue(self: Self, x: T, x_range: Interval(T)) T {
            return x_range.min + (x_range.max - x_range.min) * ((x - self.min) / (self.max - self.min));
        }

        /// Widens the interval outwardly by `delta` amount spread symmetrically over both bounds.
        pub fn expand(self: Self, delta: T) Self {
            const padding = switch(@typeInfo(T)) {
                .int => @divTrunc(delta, 2),
                .float => delta / 2.0,
                else => unreachable
            };

            return .{
                .min = self.min - padding,
                .max = self.max + padding
            };
        }
    };
}

/// Translates a floating-point value constrained within an interval into a normalized scale [0.0, 1.0].
pub fn normalizeFloat(comptime T: type, x: T,  x_range: Interval(T)) T {
    if (@typeInfo(T) != .float) {
        @compileError("Type parameter T must be a float type, received: '" ++ @typeName(T) ++ "'.");
    }

    std.debug.assert(x >= x_range.min and x <= x_range.max);

    return (x - x_range.min) / (x_range.max - x_range.min);
}

/// Remaps a floating point value proportionately from one constrained interval to another.
pub fn rescaleFloat(comptime T: type, x: T, x_range: Interval(T), new_range: Interval(T)) T {
    if (@typeInfo(T) != .float) {
        @compileError("Type parameter T must be a float type, received: '" ++ @typeName(T) ++ "'.");
    }

    std.debug.assert(x >= x_range.min and x <= x_range.max);

    return new_range.min + (new_range.max - new_range.min) * ((x - x_range.min) / (x_range.max - x_range.min));
}

test "approxEq" {
    try std.testing.expect(approxEq(u8, 0, 0));
    try std.testing.expect(approxEq(u8, 1, 1));
    try std.testing.expect(approxEq(u32, maxInt(u32), maxInt(u32)));
    try std.testing.expect(approxEq(usize, maxInt(usize), maxInt(usize)));
    try std.testing.expect(!approxEq(u8, 1, 0));
    try std.testing.expect(!approxEq(u32, maxInt(u32), maxInt(u24)));
    try std.testing.expect(!approxEq(usize, maxInt(usize), maxInt(u16)));

    try std.testing.expect(approxEq(i8, 0, 0));
    try std.testing.expect(approxEq(i8, -1, -1));
    try std.testing.expect(approxEq(i32, maxInt(i32), maxInt(i32)));
    try std.testing.expect(approxEq(isize, -maxInt(isize), -maxInt(isize)));
    try std.testing.expect(!approxEq(i8, 1, -1));
    try std.testing.expect(!approxEq(i32, maxInt(i32), -maxInt(i32)));
    try std.testing.expect(!approxEq(isize, -maxInt(isize), -maxInt(i16)));

    try std.testing.expect(approxEq(f16, 0.0, 0.0));
    try std.testing.expect(approxEq(f16, -1.0, -1.0));
    try std.testing.expect(approxEq(f32, -floatMax(f32), -floatMax(f32)));
    try std.testing.expect(approxEq(f128, floatMax(f32), floatMax(f32)));
    try std.testing.expect(!approxEq(f16, -1.0, 0.999999));

    const delta32 = floatMax(f32) * sqrt(floatEps(f32)) + floatEps(f32);
    try std.testing.expect(!approxEq(f32, -floatMax(f32), -floatMax(f32) + delta32));
    const delta128 = floatMax(f128) * sqrt(floatEps(f128)) + floatEps(f128);
    try std.testing.expect(!approxEq(f128, floatMax(f32), floatMax(f32) - delta128));

    try std.testing.expect(approxEq(f128, inf(f128), inf(f128)));
    try std.testing.expect(approxEq(f128, -inf(f128), -inf(f128)));
    try std.testing.expect(!approxEq(f128, inf(f128), -inf(f128)));

    try std.testing.expect(!approxEq(f32, nan(f32), nan(f32)));
}

test "evaluateDiscriminant" {
    const res1 = evaluateDiscriminant(f32, 1.0, 5.0, 6.0);
    try std.testing.expectEqual(2, res1[0]);
    try std.testing.expectApproxEqAbs(1.0, res1[1], floatEps(f32));

    const res2 = evaluateDiscriminant(f32, 1.0, 2.0, 3.0);
    try std.testing.expectEqual(0, res2[0]);
    try std.testing.expectApproxEqAbs(-8.0, res2[1], floatEps(f32));

    const res3 = evaluateDiscriminant(f32, 1.0, 4.0, 4.0);
    try std.testing.expectEqual(1, res3[0]);
    try std.testing.expectApproxEqAbs(0.0, res3[1], floatEps(f32));

    const res4 = evaluateDiscriminant(f64, 0.5, @sqrt(2.0), 1.0);
    try std.testing.expectEqual(1, res4[0]);
    try std.testing.expectApproxEqAbs(0.0, res4[1], 1e-10);

    const res5 = evaluateDiscriminant(f64, 1.0, 0.0, 1e-10);
    try std.testing.expectEqual(0, res5[0]);
    try std.testing.expectApproxEqAbs(-4e-10, res5[1], 1e-15);

    const res6 = evaluateDiscriminant(f64, 1.0, 2.0, 1.0 + 1e-14);
    try std.testing.expectEqual(0, res6[0]);
    try std.testing.expectApproxEqAbs(-4e-14, res6[1], 1e-15);

    const res7 = evaluateDiscriminant(i32, 1, 5, 6);
    try std.testing.expectEqual(2, res7[0]);
    try std.testing.expectEqual(@as(i32, 1), res7[1]);

    const res8 = evaluateDiscriminant(i32, 1, 2, 3);
    try std.testing.expectEqual(0, res8[0]);
    try std.testing.expectEqual(@as(i32, -8), res8[1]);

    const res9 = evaluateDiscriminant(i32, 1, 4, 4);
    try std.testing.expectEqual(1, res9[0]);
    try std.testing.expectEqual(@as(i32, 0), res9[1]);
}

test "evaluateDiscriminantReduced" {
    // a=1, b=5 (h=2.5), c=6 => h^2 - ac = 6.25 - 6 = 0.25 > 0 => Two real roots
    const res1 = evaluateDiscriminantReduced(f32, 1.0, 2.5, 6.0);
    try std.testing.expectEqual(2, res1[0]);
    try std.testing.expectApproxEqAbs(0.25, res1[1], floatEps(f32));

    // a=1, b=2 (h=1), c=3 => h^2 - ac = 1 - 3 = -2 < 0 => No real roots
    const res2 = evaluateDiscriminantReduced(f32, 1.0, 1.0, 3.0);
    try std.testing.expectEqual(0, res2[0]);
    try std.testing.expectApproxEqAbs(-2.0, res2[1], floatEps(f32));

    // a=1, b=4 (h=2), c=4 => h^2 - ac = 4 - 4 = 0 => Repeated real root
    const res3 = evaluateDiscriminantReduced(f32, 1.0, 2.0, 4.0);
    try std.testing.expectEqual(1, res3[0]);
    try std.testing.expectApproxEqAbs(0.0, res3[1], floatEps(f32));

    const res4 = evaluateDiscriminantReduced(i32, 1, 2, -3);
    try std.testing.expectEqual(2, res4[0]);
    try std.testing.expectEqual(@as(i32, 7), res4[1]);
}

test "Interval.size" {
    const IntervalF32 = Interval(f32);
    const intvlF = IntervalF32{ .min = 1.0, .max = 5.0 };
    try std.testing.expectApproxEqAbs(4.0, intvlF.size(), floatEps(f32));

    const IntervalI32 = Interval(i32);
    const intvlI = IntervalI32{ .min = -2, .max = 3 };
    try std.testing.expectEqual(@as(i32, 5), intvlI.size());
}

test "Interval.contains" {
    const IntervalF32 = Interval(f32);
    const intvlF = IntervalF32{ .min = 1.0, .max = 5.0 };
    try std.testing.expect(intvlF.contains(1.0));
    try std.testing.expect(intvlF.contains(3.0));
    try std.testing.expect(intvlF.contains(5.0));
    try std.testing.expect(!intvlF.contains(0.9));
    try std.testing.expect(!intvlF.contains(5.1));

    const IntervalI32 = Interval(i32);
    const intvlI = IntervalI32{ .min = -2, .max = 3 };
    try std.testing.expect(intvlI.contains(-2));
    try std.testing.expect(intvlI.contains(0));
    try std.testing.expect(intvlI.contains(3));
    try std.testing.expect(!intvlI.contains(-3));
    try std.testing.expect(!intvlI.contains(4));
}

test "Interval.surrounds" {
    const IntervalF32 = Interval(f32);
    const intvlF = IntervalF32{ .min = 1.0, .max = 5.0 };
    try std.testing.expect(!intvlF.surrounds(1.0));
    try std.testing.expect(intvlF.surrounds(3.0));
    try std.testing.expect(!intvlF.surrounds(5.0));
    try std.testing.expect(!intvlF.surrounds(0.9));
    try std.testing.expect(!intvlF.surrounds(5.1));

    const IntervalI32 = Interval(i32);
    const intvlI = IntervalI32{ .min = -2, .max = 3 };
    try std.testing.expect(!intvlI.surrounds(-2));
    try std.testing.expect(intvlI.surrounds(0));
    try std.testing.expect(!intvlI.surrounds(3));
    try std.testing.expect(!intvlI.surrounds(-3));
    try std.testing.expect(!intvlI.surrounds(4));
}

test "Interval.rescaleValue" {
    const IntervalF32 = Interval(f32);
    const source_range = IntervalF32{ .min = 0.0, .max = 10.0 };
    const target_range = IntervalF32{ .min = -1.0, .max = 1.0 };

    try std.testing.expectApproxEqAbs(-1.0, source_range.rescaleValue(0.0, target_range), floatEps(f32));
    try std.testing.expectApproxEqAbs(0.0, source_range.rescaleValue(5.0, target_range), floatEps(f32));
    try std.testing.expectApproxEqAbs(1.0, source_range.rescaleValue(10.0, target_range), floatEps(f32));

    try std.testing.expectApproxEqAbs(-2.0, source_range.rescaleValue(-5.0, target_range), floatEps(f32));
    try std.testing.expectApproxEqAbs(2.0, source_range.rescaleValue(15.0, target_range), floatEps(f32));
}

test "Interval.expand" {
    const IntervalF32 = Interval(f32);
    const intvlF = IntervalF32{ .min = 1.0, .max = 5.0 };
    const expandedF = intvlF.expand(2.0);
    try std.testing.expectApproxEqAbs(0.0, expandedF.min, floatEps(f32));
    try std.testing.expectApproxEqAbs(6.0, expandedF.max, floatEps(f32));

    const smallExpandedF = intvlF.expand(0.1);
    try std.testing.expectApproxEqAbs(0.95, smallExpandedF.min, floatEps(f32));
    try std.testing.expectApproxEqAbs(5.05, smallExpandedF.max, floatEps(f32));

    const zeroExpandedF = intvlF.expand(0.0);
    try std.testing.expectApproxEqAbs(1.0, zeroExpandedF.min, floatEps(f32));
    try std.testing.expectApproxEqAbs(5.0, zeroExpandedF.max, floatEps(f32));

    const IntervalI32 = Interval(i32);
    const intvlI = IntervalI32{ .min = -2, .max = 4 };
    const expandedI = intvlI.expand(2);
    try std.testing.expectEqual(@as(i32, -3), expandedI.min);
    try std.testing.expectEqual(@as(i32, 5), expandedI.max);

    const oddExpandedI = intvlI.expand(3);
    try std.testing.expectEqual(@as(i32, -3), oddExpandedI.min); // -2 - 1 = -3
    try std.testing.expectEqual(@as(i32, 5), oddExpandedI.max);  // 4 + 1 = 5

    const zeroExpandedI = intvlI.expand(0);
    try std.testing.expectEqual(@as(i32, -2), zeroExpandedI.min);
    try std.testing.expectEqual(@as(i32, 4), zeroExpandedI.max);
}

test "Interval.initEncloseTwo" {
    const IntervalF32 = Interval(f32);
    const aF = IntervalF32{ .min = 1.0, .max = 5.0 };
    const bF = IntervalF32{ .min = 3.0, .max = 7.0 };
    const enclosedF = IntervalF32.initEncloseTwo(aF, bF);
    try std.testing.expectApproxEqAbs(1.0, enclosedF.min, floatEps(f32));
    try std.testing.expectApproxEqAbs(7.0, enclosedF.max, floatEps(f32));

    const IntervalI32 = Interval(i32);
    const aI = IntervalI32{ .min = -2, .max = 3 };
    const bI = IntervalI32{ .min = -5, .max = 0 };
    const enclosedI = IntervalI32.initEncloseTwo(aI, bI);
    try std.testing.expectEqual(@as(i32, -5), enclosedI.min);
    try std.testing.expectEqual(@as(i32, 3), enclosedI.max);
}

test "normalizeFloat" {
    const IntervalF32 = Interval(f32);
    const range = IntervalF32{ .min = 0.0, .max = 10.0 };

    try std.testing.expectApproxEqAbs(0.0, normalizeFloat(f32, 0.0, range), floatEps(f32));
    try std.testing.expectApproxEqAbs(0.5, normalizeFloat(f32, 5.0, range), floatEps(f32));
    try std.testing.expectApproxEqAbs(1.0, normalizeFloat(f32, 10.0, range), floatEps(f32));

    const range_neg = IntervalF32{ .min = -10.0, .max = 0.0 };
    try std.testing.expectApproxEqAbs(0.5, normalizeFloat(f32, -5.0, range_neg), floatEps(f32));

    const range_pos = IntervalF32{ .min = 10.0, .max = 20.0 };
    try std.testing.expectApproxEqAbs(0.5, normalizeFloat(f32, 15.0, range_pos), floatEps(f32));

    const range_nonzero = IntervalF32{ .min = 5.0, .max = 15.0 };
    try std.testing.expectApproxEqAbs(0.0, normalizeFloat(f32, 5.0, range_nonzero), floatEps(f32));
    try std.testing.expectApproxEqAbs(1.0, normalizeFloat(f32, 15.0, range_nonzero), floatEps(f32));
}

test "rescaleFloat" {
    const IntervalF32 = Interval(f32);
    const old_range = IntervalF32{ .min = 0.0, .max = 10.0 };
    const new_range = IntervalF32{ .min = -1.0, .max = 1.0 };

    try std.testing.expectApproxEqAbs(-1.0, rescaleFloat(f32, 0.0, old_range, new_range), floatEps(f32));
    try std.testing.expectApproxEqAbs(0.0, rescaleFloat(f32, 5.0, old_range, new_range), floatEps(f32));
    try std.testing.expectApproxEqAbs(1.0, rescaleFloat(f32, 10.0, old_range, new_range), floatEps(f32));

    const old_range_neg = IntervalF32{ .min = -10.0, .max = 0.0 };
    try std.testing.expectApproxEqAbs(0.0, rescaleFloat(f32, -5.0, old_range_neg, new_range), floatEps(f32));

    const old_range_pos = IntervalF32{ .min = 10.0, .max = 20.0 };
    try std.testing.expectApproxEqAbs(0.0, rescaleFloat(f32, 15.0, old_range_pos, new_range), floatEps(f32));
}

