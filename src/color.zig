const std = @import("std");
const testing = std.testing;

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

        pub fn eval(self: @This(), t: T) !Color {
            if (t < self.min_t or t > self.max_t ) return error.GradientValueOutOfRange;

            const norm_t = try self.normalize(t);
            const sr = @as(T, @floatFromInt(self.start_color.r));
            const sg = @as(T, @floatFromInt(self.start_color.g));
            const sb = @as(T, @floatFromInt(self.start_color.b));
            const er = @as(T, @floatFromInt(self.end_color.r));
            const eg = @as(T, @floatFromInt(self.end_color.g));
            const eb = @as(T, @floatFromInt(self.end_color.b));

            return Color {
                .r = @intFromFloat(@round(std.math.lerp(sr, er, norm_t))),
                .g = @intFromFloat(@round(std.math.lerp(sg, eg, norm_t))),
                .b = @intFromFloat(@round(std.math.lerp(sb, eb, norm_t))),
            };
        }

        pub fn evalPacked(self: @This(), t: T) !u24 {
            const color = try self.eval(t);
            return color.toPacked();
        }

        fn normalize(self: @This(), t: T) !T {
            if (t < self.min_t or t > self.max_t ) return error.GradientValueOutOfRange;
            return (t - self.min_t) / (self.max_t - self.min_t);
        }
    };
}

test "Color" {
    try testing.expectEqual(0x00_00_00, (Color { .r = 0, .g = 0, .b = 0}).toPacked());
    try testing.expectEqual(0xFF_80_40, (Color { .r = 255, .g = 128, .b = 64}).toPacked());
    try testing.expectEqual(0xFF_FF_FF, (Color { .r = 255, .g = 255, .b = 255}).toPacked());
}

test "Gradient" {
    const ftype = f32;

    const g_asc = Gradient(ftype) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
    };

    const g_desc = Gradient(ftype) {
        .start_color = .{ .r = 255, .g = 128, .b = 64},
        .end_color = .{ .r = 0, .g = 0, .b = 0 },
    };

    const g_scaled = Gradient(ftype) {
        .start_color = .{ .r = 0, .g = 0, .b = 0},
        .end_color = .{ .r = 255, .g = 128, .b = 64 },
        .min_t = 10.0,
        .max_t = 20.0
    };

    try testing.expectError(error.GradientValueOutOfRange, g_asc.eval(1.1));
    try testing.expectError(error.GradientValueOutOfRange, g_asc.evalPacked(1.1));
    try testing.expectError(error.GradientValueOutOfRange, g_asc.normalize(1.1));
    try testing.expectError(error.GradientValueOutOfRange, g_asc.eval(-0.1));
    try testing.expectError(error.GradientValueOutOfRange, g_asc.evalPacked(-0.1));
    try testing.expectError(error.GradientValueOutOfRange, g_asc.normalize(-0.1));

    try testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, try g_asc.eval(0.0));
    try testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, try g_asc.eval(0.5));
    try testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, try g_asc.eval(1.0));

    try testing.expectEqual(0x0, try g_asc.evalPacked(0.0));
    try testing.expectEqual(0x80_40_20, try g_asc.evalPacked(0.5));
    try testing.expectEqual(0xFF_80_40, try g_asc.evalPacked(1.0));

    try testing.expectEqual(Color {.r = 255, .g = 128, .b = 64}, try g_desc.eval(0.0));
    try testing.expectEqual(Color {.r = 128, .g = 64, .b = 32}, try g_desc.eval(0.5));
    try testing.expectEqual(Color {.r = 0, .g = 0, .b = 0}, try g_desc.eval(1.0));

    try testing.expectEqual(0xFF_80_40, try g_desc.evalPacked(0.0));
    try testing.expectEqual(0x80_40_20, try g_desc.evalPacked(0.5));
    try testing.expectEqual(0x0, try g_desc.evalPacked(1.0));

    try testing.expectApproxEqAbs(0.0, try g_scaled.normalize(10.0), 2 * std.math.floatEps(ftype));
    try testing.expectApproxEqAbs(0.25, try g_scaled.normalize(12.5), 2 * std.math.floatEps(ftype));
    try testing.expectApproxEqAbs(0.5, try g_scaled.normalize(15.0), 2 * std.math.floatEps(ftype));
    try testing.expectApproxEqAbs(1.0, try g_scaled.normalize(20.0), 2 * std.math.floatEps(ftype));
}
