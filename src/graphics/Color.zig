//! Represents an 8-bit RGB color.

const Color = @This();

const std = @import("std");
const config = @import("../global_config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Interval = math_utils.Interval(Float);
const approxEq = math_utils.approxEq;
const normalizeFloat = math_utils.normalizeFloat;

r: u8,
g: u8,
b: u8,

/// Converts the color down to a packed 24-bit integer, useful for fast memory writes.
pub inline fn toPacked(self: Color) u24 {
    return (@as(u24, self.r) << 16) | (@as(u24, self.g) << 8) | @as(u24, self.b);
}

/// Defines a linear transition between two colors.
pub const Gradient = struct {
    start_color: Color,
    end_color: Color,
    t_range: Interval = .{ .min = 0.0, .max = 1.0 },

    /// Calculates the interpolated `Color` at the given progress t.
    pub fn at(self: Gradient, t: Float) Color {
        std.debug.assert(self.t_range.contains(t));

        const norm_t = normalizeFloat(Float, t, self.t_range);
        const start_r = @as(Float, @floatFromInt(self.start_color.r));
        const start_g = @as(Float, @floatFromInt(self.start_color.g));
        const start_b = @as(Float, @floatFromInt(self.start_color.b));
        const end_r = @as(Float, @floatFromInt(self.end_color.r));
        const end_g = @as(Float, @floatFromInt(self.end_color.g));
        const end_b = @as(Float, @floatFromInt(self.end_color.b));

        return Color {
            .r = @intFromFloat(@round(std.math.lerp(start_r, end_r, norm_t))),
            .g = @intFromFloat(@round(std.math.lerp(start_g, end_g, norm_t))),
            .b = @intFromFloat(@round(std.math.lerp(start_b, end_b, norm_t))),
        };
    }

    /// Evaluates the gradient and packs the resulting color directly to a 24-bit integer.
    pub fn atPacked(self: Gradient, t: Float) u24 {
        const color = self.at(t);
        return color.toPacked();
    }
};

test "Color.toPacked" {
    try std.testing.expectEqual(0x00_00_00, (Color { .r = 0, .g = 0, .b = 0}).toPacked());
    try std.testing.expectEqual(0xFF_80_40, (Color { .r = 255, .g = 128, .b = 64}).toPacked());
    try std.testing.expectEqual(0xFF_FF_FF, (Color { .r = 255, .g = 255, .b = 255}).toPacked());
}

test "Gradient - Ascending gradient at" {
    const g_asc = Gradient {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, g_asc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, g_asc.at(0.5));
    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, g_asc.at(1.0));
}

test "Gradient - Ascending gradient atPacked" {
    const g_asc = Gradient {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(0x0, g_asc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, g_asc.atPacked(0.5));
    try std.testing.expectEqual(0xFF_80_40, g_asc.atPacked(1.0));
}

test "Gradient - Descending gradient at" {
    const g_desc = Gradient {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, g_desc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, g_desc.at(0.5));
    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, g_desc.at(1.0));
}

test "Gradient - Descending gradient atPacked" {
    const g_desc = Gradient {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(0xFF_80_40, g_desc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, g_desc.atPacked(0.5));
    try std.testing.expectEqual(0x0, g_desc.atPacked(1.0));
}
