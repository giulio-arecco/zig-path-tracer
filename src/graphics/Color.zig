const Color = @This();

const std = @import("std");
const config = @import("../config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const approxEq = math_utils.approxEq;

r: u8,
g: u8,
b: u8,

pub inline fn toPacked(self: Color) u24 {
    return (@as(u24, self.r) << 16) | (@as(u24, self.g) << 8) | @as(u24, self.b);
}

/// Converts RGB components from a floating-point interval `[min, max]` into an 8-bit `Color`.\
/// `min` and `max` must be different, and each channel ranges from `min` to `max`, but may exceed those bounds.
pub fn fromFloats(comptime T: type, r: T, g: T, b: T, min: T, max: T) Color {
    comptime {
        if (@typeInfo(T) != .float) {
            @compileError("Type parameter T must be a float type, received: '" ++ @typeName(T) ++ "'.");
        }
    }

    std.debug.assert(!approxEq(Float, max, min));

    const scaled_r = if (r < min) min else if (r > max) max else r;
    const scaled_g = if (g < min) min else if (g > max) max else g;
    const scaled_b = if (b < min) min else if (b > max) max else b;

    return .{
        .r = @intFromFloat(@round((scaled_r - min) * 255.0 / (max - min))),
        .g = @intFromFloat(@round((scaled_g - min) * 255.0 / (max - min))),
        .b = @intFromFloat(@round((scaled_b - min) * 255.0 / (max - min))),
    };
}

/// Converts RGB components from a Vec3 with all coordinates in the range [0, 1] into an 8-bit `Color`.\
/// `v.x` is mapped to the R channel, `v.y` to G and `v.z` to B.
pub fn fromVec3(v: Vec3) Color {
    std.debug.assert(v.x >= 0.0 and v.x <= 1.0);
    std.debug.assert(v.y >= 0.0 and v.y <= 1.0);
    std.debug.assert(v.z >= 0.0 and v.z <= 1.0);

    return .{
        .r = @intFromFloat(@round(v.x * 255.0)),
        .g = @intFromFloat(@round(v.y * 255.0)),
        .b = @intFromFloat(@round(v.z * 255.0))
    };
}

pub fn toFloats(self: Color, comptime T: type) struct {T, T, T} {
    comptime {
        if (@typeInfo(T) != .float) {
            @compileError("Type parameter T must be a float type, received: '" ++ @typeName(T) ++ "'.");
        }
    }

    return .{
        @as(T, @floatFromInt(self.r)) / 255.0,
        @as(T, @floatFromInt(self.g)) / 255.0,
        @as(T, @floatFromInt(self.b)) / 255.0,
    };
}

/// Returns a Vec3 with all coordinates ranging from 0.0 to 1.0
pub fn toVec3(self: Color) Vec3 {
    return .{
        .x = @as(Float, @floatFromInt(self.r)) / 255.0,
        .y = @as(Float, @floatFromInt(self.g)) / 255.0,
        .z = @as(Float, @floatFromInt(self.b)) / 255.0,
    };
}

pub fn Gradient(comptime T: type) type {
    comptime {
        if (@typeInfo(T) != .float) {
            @compileError("Gradient requires a float type (i.e. f32, f64), received: '" ++ @typeName(T) ++ "'.");
        }
    }

    return struct {
        start_color: Color,
        end_color: Color,

        min_t: T = 0.0,
        max_t: T = 1.0,

        pub fn at(self: @This(), t: T) Color {
            std.debug.assert(t >= self.min_t and t <= self.max_t);

            const norm_t = self.normalizeT(t);
            const start_r = @as(T, @floatFromInt(self.start_color.r));
            const start_g = @as(T, @floatFromInt(self.start_color.g));
            const start_b = @as(T, @floatFromInt(self.start_color.b));
            const end_r = @as(T, @floatFromInt(self.end_color.r));
            const end_g = @as(T, @floatFromInt(self.end_color.g));
            const end_b = @as(T, @floatFromInt(self.end_color.b));

            return Color {
                .r = @intFromFloat(@round(std.math.lerp(start_r, end_r, norm_t))),
                .g = @intFromFloat(@round(std.math.lerp(start_g, end_g, norm_t))),
                .b = @intFromFloat(@round(std.math.lerp(start_b, end_b, norm_t))),
            };
        }

        pub fn atPacked(self: @This(), t: T) u24 {
            const color = self.at(t);
            return color.toPacked();
        }

        fn normalizeT(self: @This(), t: T) T {
            std.debug.assert(t >= self.min_t and t <= self.max_t);
            return (t - self.min_t) / (self.max_t - self.min_t);
        }
    };
}

test "Color - Packed" {
    try std.testing.expectEqual(0x00_00_00, (Color { .r = 0, .g = 0, .b = 0}).toPacked());
    try std.testing.expectEqual(0xFF_80_40, (Color { .r = 255, .g = 128, .b = 64}).toPacked());
    try std.testing.expectEqual(0xFF_FF_FF, (Color { .r = 255, .g = 255, .b = 255}).toPacked());
}

test "Color.fromFloats" {
    const c1 = Color.fromFloats(f32, 0.0, 0.5, 1.0, 0.0, 1.0);
    try std.testing.expectEqual(Color{ .r = 0, .g = 128, .b = 255 }, c1);

    const c2 = Color.fromFloats(f32, 10.0, 15.0, 20.0, 10.0, 20.0);
    try std.testing.expectEqual(Color{ .r = 0, .g = 128, .b = 255 }, c2);

    const c3 = Color.fromFloats(f32, -10.0, 15.0, 30.0, 10.0, 20.0);
    try std.testing.expectEqual(Color{ .r = 0, .g = 128, .b = 255 }, c3);
}

test "Color.toFloats" {
    const eps = 2 * std.math.floatEps(f32);
    const c = Color{ .r = 0, .g = 128, .b = 255 };
    const floats = c.toFloats(f32);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), floats[0], eps);
    try std.testing.expectApproxEqAbs(@as(f32, 128.0) / 255.0, floats[1], eps);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), floats[2], eps);
}

test "Color.toVec3" {
    const eps = @sqrt(std.math.floatEps(Float));
    const c = Color{ .r = 0, .g = 128, .b = 255 };
    const vec = c.toVec3();

    try std.testing.expectApproxEqRel(@as(Float, 0.0), vec.x, eps);
    try std.testing.expectApproxEqRel(@as(Float, 128.0) / 255.0, vec.y, eps);
    try std.testing.expectApproxEqRel(@as(Float, 1.0), vec.z, eps);
}

test "Color.fromVec3" {
    const c1 = Color.fromVec3(.{ .x = 0.0, .y = 0.5, .z = 1.0 });
    try std.testing.expectEqual(Color{ .r = 0, .g = 128, .b = 255 }, c1);

    const c2 = Color.fromVec3(.{ .x = 0.25, .y = 0.75, .z = 0.33333333 });
    try std.testing.expectEqual(Color{ .r = 64, .g = 191, .b = 85 }, c2);

    const c3 = Color.fromVec3(.{ .x = 1.0, .y = 1.0, .z = 1.0 });
    try std.testing.expectEqual(Color{ .r = 255, .g = 255, .b = 255 }, c3);
}

test "Gradient - Ascending gradient at" {
    const g_asc = Gradient(f32) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, g_asc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, g_asc.at(0.5));
    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, g_asc.at(1.0));
}

test "Gradient - Ascending gradient atPacked" {
    const g_asc = Gradient(f32) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(0x0, g_asc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, g_asc.atPacked(0.5));
    try std.testing.expectEqual(0xFF_80_40, g_asc.atPacked(1.0));
}

test "Gradient - Descending gradient at" {
    const g_desc = Gradient(f32) {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, g_desc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, g_desc.at(0.5));
    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, g_desc.at(1.0));
}

test "Gradient - Descending gradient atPacked" {
    const g_desc = Gradient(f32) {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(0xFF_80_40, g_desc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, g_desc.atPacked(0.5));
    try std.testing.expectEqual(0x0, g_desc.atPacked(1.0));
}

test "Gradient - Normalization" {
    const ftype = f32;

    const g_scaled = Gradient(ftype) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
        .min_t = 10.0,
        .max_t = 20.0
    };

    try std.testing.expectApproxEqAbs(0.0, g_scaled.normalizeT(10.0), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(0.25, g_scaled.normalizeT(12.5), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(0.5, g_scaled.normalizeT(15.0), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(1.0, g_scaled.normalizeT(20.0), 2 * std.math.floatEps(ftype));
}
