const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub inline fn toPacked(self: @This()) u24 {
        return (@as(u24, self.r) << 16) | (@as(u24, self.g) << 8) | @as(u24, self.b);
    }
};

pub fn Gradient(comptime T: type) type {
    comptime {
        if (@typeInfo(T) != .float) {
            @compileError("Gradient requires a float type (i.e. f32, f64), received: " ++ @typeName(T));
        }
    }

    return struct {
        start_color: Color,
        end_color: Color,

        min_t: T = 0.0,
        max_t: T = 1.0,

        pub fn at(self: @This(), t: T) !Color {
            if (t < self.min_t or t > self.max_t ) return error.GradientValueOutOfRange; // TODO: make this an assertion

            const norm_t = try self.normalize(t);
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

        pub fn atPacked(self: @This(), t: T) !u24 {
            const color = try self.at(t);
            return color.toPacked();
        }

        fn normalize(self: @This(), t: T) !T {
            if (t < self.min_t or t > self.max_t ) return error.GradientValueOutOfRange; // TODO: make this an assertion
            return (t - self.min_t) / (self.max_t - self.min_t);
        }
    };
}

test "Color - Packed" {
    try std.testing.expectEqual(0x00_00_00, (Color { .r = 0, .g = 0, .b = 0}).toPacked());
    try std.testing.expectEqual(0xFF_80_40, (Color { .r = 255, .g = 128, .b = 64}).toPacked());
    try std.testing.expectEqual(0xFF_FF_FF, (Color { .r = 255, .g = 255, .b = 255}).toPacked());
}

test "Gradient - Out of range values" {
    const g = Gradient(f32) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectError(error.GradientValueOutOfRange, g.at(1.1));
    try std.testing.expectError(error.GradientValueOutOfRange, g.atPacked(1.1));
    try std.testing.expectError(error.GradientValueOutOfRange, g.normalize(1.1));
    try std.testing.expectError(error.GradientValueOutOfRange, g.at(-0.1));
    try std.testing.expectError(error.GradientValueOutOfRange, g.atPacked(-0.1));
    try std.testing.expectError(error.GradientValueOutOfRange, g.normalize(-0.1));
}

test "Gradient - Ascending gradient eval" {
    const g_asc = Gradient(f32) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, try g_asc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, try g_asc.at(0.5));
    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, try g_asc.at(1.0));
}

test "Gradient - Ascending gradient evalPacked" {
    const g_asc = Gradient(f32) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    try std.testing.expectEqual(0x0, try g_asc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, try g_asc.atPacked(0.5));
    try std.testing.expectEqual(0xFF_80_40, try g_asc.atPacked(1.0));
}

test "Gradient - Descending gradient eval" {
    const g_desc = Gradient(f32) {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, try g_desc.at(0.0));
    try std.testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, try g_desc.at(0.5));
    try std.testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, try g_desc.at(1.0));
}

test "Gradient - Descending gradient evalPacked" {
    const g_desc = Gradient(f32) {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    try std.testing.expectEqual(0xFF_80_40, try g_desc.atPacked(0.0));
    try std.testing.expectEqual(0x80_40_20, try g_desc.atPacked(0.5));
    try std.testing.expectEqual(0x0, try g_desc.atPacked(1.0));
}

test "Gradient - Normalization" {
    const ftype = f32;

    const g_scaled = Gradient(ftype) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
        .min_t = 10.0,
        .max_t = 20.0
    };

    try std.testing.expectApproxEqAbs(0.0, try g_scaled.normalize(10.0), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(0.25, try g_scaled.normalize(12.5), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(0.5, try g_scaled.normalize(15.0), 2 * std.math.floatEps(ftype));
    try std.testing.expectApproxEqAbs(1.0, try g_scaled.normalize(20.0), 2 * std.math.floatEps(ftype));
}
