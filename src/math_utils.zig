const std = @import("std");
const maxInt = std.math.maxInt;
const floatMax = std.math.floatMax;
const floatEps = std.math.floatEps;
const sqrt = std.math.sqrt;
const inf = std.math.inf;
const nan = std.math.nan;


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

pub fn evaluateDiscriminant(comptime FType: type, a: FType, b: FType, c: FType) bool {
    const b_sq = b * b;
    const four_ac = 4.0 * a * c; // Consider checking if a or c ar == 1 to avoid a multiplication
    const discr = b_sq - four_ac;

    const max_magnitude = @max(@abs(b_sq), @abs(four_ac));
    const tolerance: FType = 2.0;
    const eps = std.math.floatEpsAt(FType, max_magnitude) * tolerance;

    if (discr > eps) {
        // Two real solutions
        return true;
    }
    else if (discr < -eps) {
        // No real solution
        return false;
    }
    else {
        // Repeated real solution
        return true;
    }
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
    // a=1, b=5, c=6 => b^2 - 4ac = 25 - 24 = 1 > 0 => Two real solutions (true)
    try std.testing.expect(evaluateDiscriminant(f32, 1.0, 5.0, 6.0));
    // a=1, b=2, c=3 => b^2 - 4ac = 4 - 12 = -8 < 0 => No real solution (false)
    try std.testing.expect(!evaluateDiscriminant(f32, 1.0, 2.0, 3.0));
    // a=1, b=4, c=4 => b^2 - 4ac = 16 - 16 = 0 => Repeated real solution (true)
    try std.testing.expect(evaluateDiscriminant(f32, 1.0, 4.0, 4.0));

    // Values that result in discriminant being zero mathematically, but might not be exactly zero due to floating point inaccuracies.
    // E.g., b = sqrt(2), a = 0.5, c = 1 => 2 - 4(0.5)(1) = 2 - 2 = 0
    try std.testing.expect(evaluateDiscriminant(f64, 0.5, @sqrt(2.0), 1.0));

    // Negative discriminant but very small in magnitude
    // e.g. a=1, b=0, c=1e-10 => 0 - 4e-10 < 0
    try std.testing.expect(!evaluateDiscriminant(f64, 1.0, 0.0, 1e-10));

    // Negative discriminant extremely close to zero
    try std.testing.expect(!evaluateDiscriminant(f64, 1.0, 2.0, 1.0 + 1e-14));
}
