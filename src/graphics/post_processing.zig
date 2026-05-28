const std = @import("std");
const config = @import("../global_config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Color = @import("Color.zig");
const LinearColor = @import("LinearColor.zig");
const FrameBuffers = @import("scene_3d/rendering.zig").FrameBuffers;
const Interval = math_utils.Interval(Float);

const expectLinearColorApproxEq = LinearColor.expectLinearColorApproxEq;

pub const ToneMapper = union(enum) {
    reinhard: ReinhardToneMapper,
    extended_reinhard: ExtendedReinhardToneMapper,
    clamp: ClampToneMapper,
    exp: ExpToneMapper,
    gamma: GammaCompressionToneMapper,

    pub fn toneMap(self: ToneMapper, c: LinearColor) LinearColor {
        return switch (self) {
            inline else => |mapper| mapper.apply(c)
        };
    }
};

pub const ReinhardToneMapper = struct {
    pub fn apply(self: ReinhardToneMapper, c: LinearColor) LinearColor {
        _ = self;
        const ones: @Vector(3, Float) = @splat(1.0);
        return .{ .v = c.v / (c.v + ones) };
    }
};

pub const ExtendedReinhardToneMapper = struct {
    white: Float,

    pub fn apply(self: ExtendedReinhardToneMapper, c: LinearColor) LinearColor {
        std.debug.assert(self.white > 0.0);

        const ones: @Vector(3, Float) = @splat(1.0);
        const white_vec: @Vector(3, Float) = @splat(self.white);
        return .{ .v = (c.v * (ones + (c.v / (white_vec * white_vec)))) / (ones + c.v) };
    }
};

pub const ClampToneMapper = struct {
    pub fn apply(self: ClampToneMapper, c: LinearColor) LinearColor {
        _ = self;
        const ones: @Vector(3, Float) = @splat(1.0);
        return .{ .v = @min(c.v, ones) };
}
};

pub const ExpToneMapper = struct {
    exposure: Float,

    pub fn apply(self: ExpToneMapper, c: LinearColor) LinearColor {
        const ones: @Vector(3, Float) = @splat(1.0);
        const exp_vec: @Vector(3, Float) = @splat(self.exposure);
        return .{ .v = ones - @exp(-c.v * exp_vec) };
    }
};

pub const GammaCompressionToneMapper = struct {
    a: Float,
    gamma: Float,

    pub fn apply(self: GammaCompressionToneMapper, c: LinearColor) LinearColor {
        std.debug.assert(self.gamma > 0.0 and self.gamma < 1.0);
        std.debug.assert(self.a > 0.0);

        const zeroes: @Vector(3, Float) = @splat(0.0);
        const v = @max(c.v, zeroes);

        const a_vec: @Vector(3, Float) = @splat(self.a);
        const gamma_vec: @Vector(3, Float) = @splat(self.gamma);

        const v_pow_gamma = @exp(gamma_vec * @log(v));
        return .{ .v = a_vec * v_pow_gamma };
    }
};

pub const StepContext = struct {
    in_color: []const LinearColor,
    out_color: []LinearColor,
};

pub const PostProcessorHdr = union(enum) {
    // TODO: add denoiser

    pub fn process(self: PostProcessorHdr, ctx: StepContext) void {
        switch (self) {
            inline else => |p| p.process(ctx)
        }
    }
};

pub const DisplayTransformType = enum { toSrgb8bit };

pub const DisplayTransform = struct {
    tone_mapper: ToneMapper,
    transform_type: DisplayTransformType,

    pub fn process(self: DisplayTransform, hdr_buf: []const LinearColor, out_buf: []u8) void {
        for(hdr_buf, 0..hdr_buf.len) |lin_col, i| {
            const out_col = switch (self.transform_type) {
                .toSrgb8bit => self.toSrgb8bit(lin_col)
            };

            const pixel_byte_index = i * 3;
            std.mem.writeInt(u24, out_buf[pixel_byte_index..][0..3], out_col.toPacked(), .big);
        }
    }

    fn toSrgb8bit(self: DisplayTransform, c: LinearColor) Color {
        std.debug.assert(c.isValid());

        var mapped = self.tone_mapper.toneMap(c);

        // Clamp the tone mapped values to the [0.0, 1.0] interval
        const zeroes: @Vector(3, Float) = @splat(0.0);
        const ones: @Vector(3, Float) = @splat(1.0);
        mapped.v = @max(@min(mapped.v, ones), zeroes);

        const gamma_col = srgbGammaCorrection(mapped);
        const r_gamma = gamma_col.r();
        const g_gamma = gamma_col.g();
        const b_gamma = gamma_col.b();

        return .{
            .r = @intFromFloat(@round(r_gamma * 255.0)),
            .g = @intFromFloat(@round(g_gamma * 255.0)),
            .b = @intFromFloat(@round(b_gamma * 255.0))
        };
    }

    fn fromSrgb8bit(c: Color) LinearColor {
        var res_v: @Vector(3, Float) = undefined;

        res_v[0] = @as(Float, @floatFromInt(c.r)) / 255.0;
        res_v[1] = @as(Float, @floatFromInt(c.g)) / 255.0;
        res_v[2] = @as(Float, @floatFromInt(c.b)) / 255.0;

        return inverseSrgbGammaCorrection(.{ .v = res_v });
    }

    /// Performs the *gamma 2* correction.\
    /// Asserts that each LinearColor component is normalized.
    fn gamma2Correction(c: LinearColor) LinearColor {
        const zeroes: @Vector(3, Float) = @splat(0.0);
        const ones: @Vector(3, Float) = @splat(1.0);
        std.debug.assert(@reduce(.And, c.v >= zeroes) and @reduce(.And, c.v <= ones));

        return .{ .v = @sqrt(c.v) };
    }

    /// Performs the *SRGB* gamma correction.\
    /// Asserts that each LinearColor component is normalized.
    fn srgbGammaCorrection(c: LinearColor) LinearColor {
        const zeroes: @Vector(3, Float) = @splat(0.0);
        const ones: @Vector(3, Float) = @splat(1.0);
        std.debug.assert(@reduce(.And, c.v >= zeroes) and @reduce(.And, c.v <= ones));

        var res_v: @Vector(3, Float) = undefined;

        comptime var i = 0;
        inline while(i < 3) : (i += 1) {
            const channel = c.v[i];
            if (channel <= 0.0031308) {
                res_v[i] = 12.92 * channel;
            }
            else {
                res_v[i] = 1.055 * std.math.pow(Float, channel, 1.0 / 2.4) - 0.055;
            }
        }

        return .{ .v = res_v };
    }

    /// Performs the *inverse SRGB* gamma correction.\
    /// Asserts that each LinearColor component is normalized.
    fn inverseSrgbGammaCorrection(c: LinearColor) LinearColor {
        const zeroes: @Vector(3, Float) = @splat(0.0);
        const ones: @Vector(3, Float) = @splat(1.0);
        std.debug.assert(@reduce(.And, c.v >= zeroes) and @reduce(.And, c.v <= ones));

        var res_v: @Vector(3, Float) = undefined;

        comptime var i = 0;
        inline while(i < 3) : (i += 1) {
            const channel = c.v[i];
            if (channel <= 0.04045) {
                res_v[i] = channel / 12.92;
            }
            else {
                res_v[i] = std.math.pow(Float, (channel + 0.055) / 1.055, 2.4);
            }
        }

        return .{ .v = res_v };
    }

    /// Performs gamma correction based on the provided gamma value.\
    /// Asserts that each LinearColor component is normalized.
    fn gammaCorrection(c: LinearColor, gamma: Float) LinearColor {
        const zeroes: @Vector(3, Float) = @splat(0.0);
        const ones: @Vector(3, Float) = @splat(1.0);
        std.debug.assert(@reduce(.And, c.v >= zeroes) and @reduce(.And, c.v <= ones));

        const gamma_vec: @Vector(3, Float) = @splat(gamma);

        return .{ .v = @exp((ones / gamma_vec) * @log(c.v)) };
    }
};

const eps = std.math.floatEps(Float);

test "ToneMapper - Behavior and clamps" {
    const c = LinearColor.init(0.5, 1.0, 10.0);

    // Clamp
    const clamp_mapper = ToneMapper{ .clamp = .{} };
    try expectLinearColorApproxEq(LinearColor.init(0.5, 1.0, 1.0), clamp_mapper.toneMap(c), eps);

    // Reinhard
    const reinhard = ToneMapper{ .reinhard = .{} };
    try expectLinearColorApproxEq(LinearColor.init(1.0 / 3.0, 0.5, 10.0 / 11.0), reinhard.toneMap(c), eps);

    // Extended Reinhard (white = 2.0)
    // - c=0.5 -> 0.5*(1 + 0.125) / 1.5 = 0.375
    // - c=1.0 -> 1.0*(1 + 0.25) / 2.0 = 0.625
    // - c=10.0 -> 10.0*(1 + 25) / 11.0 = 35.0 / 11.0
    const ext_reinhard = ToneMapper{ .extended_reinhard = .{ .white = 2.0 } };
    try expectLinearColorApproxEq(LinearColor.init(0.375, 0.625, 35.0 / 11.0), ext_reinhard.toneMap(c), eps);

    // Exp
    const exp_mapper = ToneMapper{ .exp = .{ .exposure = 1.0 } };
    try expectLinearColorApproxEq(LinearColor.init(
        1.0 - @exp(@as(Float, -0.5)),
        1.0 - @exp(@as(Float, -1.0)),
        1.0 - @exp(@as(Float, -10.0))
    ), exp_mapper.toneMap(c), eps);

    // Gamma (a=1.0, gamma=0.5)
    const gamma_mapper = ToneMapper{ .gamma = .{ .a = 1.0, .gamma = 0.5 } };
    try expectLinearColorApproxEq(LinearColor.init(
        @sqrt(@as(Float, 0.5)), 1.0, @sqrt(@as(Float, 10.0))
    ), gamma_mapper.toneMap(c), eps);
}

test "DisplayTransform.srgbGammaCorrection" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const srgb = DisplayTransform.srgbGammaCorrection(c);

    try std.testing.expectApproxEqAbs(@as(Float, 0.0), srgb.v[0], eps);
    const expected_mid = 1.055 * std.math.pow(Float, 0.5, 1.0 / 2.4) - 0.055;
    try std.testing.expectApproxEqAbs(expected_mid, srgb.v[1], eps);
    try std.testing.expectApproxEqAbs(@as(Float, 1.0), srgb.v[2], eps);
}

test "DisplayTransform.inverseSrgbGammaCorrection" {
    // Roughly recreate the srgb exact values from the previous test forward path to inverse them
    const mid_srgb = 1.055 * std.math.pow(Float, 0.5, 1.0 / 2.4) - 0.055;
    const srgb = LinearColor.init(0.0, mid_srgb, 1.0);
    const inverted = DisplayTransform.inverseSrgbGammaCorrection(srgb);
    try expectLinearColorApproxEq(LinearColor.init(0.0, 0.5, 1.0), inverted, eps);
}

test "DisplayTransform.gamma2Correction" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const g2 = DisplayTransform.gamma2Correction(c);
    try expectLinearColorApproxEq(LinearColor.init(0.0, @sqrt(0.5), 1.0), g2, eps);
}

test "DisplayTransform.gammaCorrection (Custom)" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const g_custom = DisplayTransform.gammaCorrection(c, 2.2);

    try std.testing.expectApproxEqAbs(@as(Float, 0.0), g_custom.v[0], eps);
    try std.testing.expectApproxEqAbs(@as(Float, std.math.pow(Float, 0.5, 1.0/2.2)), g_custom.v[1], eps);
    try std.testing.expectApproxEqAbs(@as(Float, 1.0), g_custom.v[2], eps);
}

test "DisplayTransform.toSrgb8bit" {
    // HDR clamping test
    const hdr_c = LinearColor.init(100.0, 0.0, 5.0);
    // GammaCompressionToneMapper won't restrict it to 1.0: 100^0.5 = 10.0 > 1.0
    const mapper = ToneMapper{ .gamma = .{ .a = 1.0, .gamma = 0.5 } };

    // toSrgb8bit MUST clamp the tone mapped result before applying srgb curve,
    // otherwise the internal asserts for <= 1.0 in srgbGammaCorrection would fail.
    const dt = DisplayTransform{ .tone_mapper = mapper, .transform_type = .toSrgb8bit };
    const hdr_c8 = dt.toSrgb8bit(hdr_c);

    // Both 100.0 and 5.0 should have been clamped to 255
    try std.testing.expectEqual(@as(u8, 255), hdr_c8.r);
    try std.testing.expectEqual(@as(u8, 0), hdr_c8.g);
    try std.testing.expectEqual(@as(u8, 255), hdr_c8.b);
}

test "DisplayTransform.fromSrgb8bit and roundtrip" {
    const c8 = Color{ .r = 0, .g = 127, .b = 255 };
    const lin = DisplayTransform.fromSrgb8bit(c8);
    // Linearized 127 is accurately calculable via the inverse curve:
    const expected_mid = std.math.pow(Float, (127.0 / 255.0 + 0.055) / 1.055, 2.4);
    try std.testing.expectApproxEqAbs(expected_mid, lin.v[1], eps);

    // Now map back with a Clamp mapper (which won't affect it since it's <= 1)
    const dt = DisplayTransform{ .tone_mapper = .{ .clamp = .{} }, .transform_type = .toSrgb8bit };
    const back_c8 = dt.toSrgb8bit(lin);
    try std.testing.expectEqual(c8.r, back_c8.r);
    try std.testing.expectEqual(c8.g, back_c8.g);
    try std.testing.expectEqual(c8.b, back_c8.b);
}

test "DisplayTransform.process" {
    const hdr_buf = [_]LinearColor{
        LinearColor.init(0.5, 0.5, 0.5),
        LinearColor.init(100.0, 0.0, 5.0),
    };
    var out_buf: [6]u8 = undefined;

    const mapper = ToneMapper{ .clamp = .{} };
    const dt = DisplayTransform{ .tone_mapper = mapper, .transform_type = .toSrgb8bit };

    dt.process(&hdr_buf, &out_buf);

    const exp_col0 = dt.toSrgb8bit(hdr_buf[0]);
    try std.testing.expectEqual(exp_col0.r, out_buf[0]);
    try std.testing.expectEqual(exp_col0.g, out_buf[1]);
    try std.testing.expectEqual(exp_col0.b, out_buf[2]);

    const exp_col1 = dt.toSrgb8bit(hdr_buf[1]);
    try std.testing.expectEqual(exp_col1.r, out_buf[3]);
    try std.testing.expectEqual(exp_col1.g, out_buf[4]);
    try std.testing.expectEqual(exp_col1.b, out_buf[5]);
}

test "DisplayTransform.process - empty buffer" {
    const hdr_buf = [_]LinearColor{};
    var out_buf: [0]u8 = undefined;
    const dt = DisplayTransform{ .tone_mapper = .{ .clamp = .{} }, .transform_type = .toSrgb8bit };
    dt.process(&hdr_buf, &out_buf);
}

