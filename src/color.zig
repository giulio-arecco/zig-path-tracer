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

        fn normalize(self: @This(), t: T) !f32 {
            if (t < self.min_t or t > self.max_t ) return error.GradientValueOutOfRange;
            return (t - self.min_t) / (self.max_t - self.min_t);
        }
    };
}
