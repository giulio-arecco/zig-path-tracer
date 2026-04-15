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
