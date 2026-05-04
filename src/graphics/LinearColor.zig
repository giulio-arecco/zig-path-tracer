const LinearColor = @This();

const std = @import("std");
const config = @import("../config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Color = @import("Color.zig");
const Interval = math_utils.Interval(Float);

const approxEq = math_utils.approxEq;
const normalizeFloat = math_utils.normalizeFloat;
const rescaleFloat = math_utils.rescaleFloat;

v: @Vector(3, Float),

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

pub const LinearGradient = struct {
    start_color: LinearColor,
    end_color: LinearColor,
    t_range: Interval = .{ .min = 0.0, .max = 1.0 },

    pub fn at(self: LinearGradient, t: Float) LinearColor {
        std.debug.assert(self.t_range.contains(t));

        const norm_t = normalizeFloat(Float, t, self.t_range);
        const t_vec: @Vector(3, Float) = @splat(norm_t);
        const one_minus_t: @Vector(3, Float) = @splat(1.0 - norm_t);

        return .{ .v = (self.start_color.v * one_minus_t) + (self.end_color.v * t_vec) };
    }
};

/// Initialize a pure black LinearColor (0, 0, 0)
pub const black = LinearColor { .v = @splat(0.0) };

/// Initialize a pure white LinearColor (1, 1, 1)
pub const white = LinearColor { .v = @splat(1.0) };

pub fn init(r: Float, g: Float, b: Float) LinearColor {
    return .{ .v = .{ r, g, b } };
}

/// Performs the *gamma 2* correction.\
/// Asserts that each LinearColor component is normalized.
pub fn gamma2Correction(self: LinearColor) LinearColor {
    const zeroes: @Vector(3, Float) = @splat(0.0);
    const ones: @Vector(3, Float) = @splat(1.0);
    std.debug.assert(@reduce(.And, self.v >= zeroes) and @reduce(.And, self.v <= ones));

    return .{ .v = @sqrt(self.v) };
}

/// Performs the *SRGB* gamma correction.\
/// Asserts that each LinearColor component is normalized.
pub fn srgbGammaCorrection(self: LinearColor) LinearColor {
    const zeroes: @Vector(3, Float) = @splat(0.0);
    const ones: @Vector(3, Float) = @splat(1.0);
    std.debug.assert(@reduce(.And, self.v >= zeroes) and @reduce(.And, self.v <= ones));

    var res_v: @Vector(3, Float) = undefined;

    comptime var i = 0;
    inline while(i < 3) : (i += 1) {
        const c = self.v[i];
        if (c <= 0.0031308) {
            res_v[i] = 12.92 * c;
        }
        else {
            res_v[i] = 1.055 * std.math.pow(Float, c, 1.0 / 2.4) - 0.055;
        }
    }

    return .{ .v = res_v };
}

/// Performs the *inverse SRGB* gamma correction.\
/// Asserts that each LinearColor component is normalized.
pub fn inverseSrgbGammaCorrection(self: LinearColor) LinearColor {
    const zeroes: @Vector(3, Float) = @splat(0.0);
    const ones: @Vector(3, Float) = @splat(1.0);
    std.debug.assert(@reduce(.And, self.v >= zeroes) and @reduce(.And, self.v <= ones));

    var res_v: @Vector(3, Float) = undefined;

    comptime var i = 0;
    inline while(i < 3) : (i += 1) {
        const c = self.v[i];
        if (c <= 0.04045) {
            res_v[i] = c / 12.92;
        }
        else {
            res_v[i] = std.math.pow(Float, (c + 0.055) / 1.055, 2.4);
        }
    }

    return .{ .v = res_v };
}

/// Performs gamma correction based on the provided gamma value.\
/// Asserts that each LinearColor component is normalized.
pub fn gammaCorrection(self: LinearColor, gamma: Float) LinearColor {
    const zeroes: @Vector(3, Float) = @splat(0.0);
    const ones: @Vector(3, Float) = @splat(1.0);
    std.debug.assert(@reduce(.And, self.v >= zeroes) and @reduce(.And, self.v <= ones));

    const gamma_vec: @Vector(3, Float) = @splat(gamma);

    return .{ .v = @exp((ones / gamma_vec) * @log(self.v)) };
}

pub fn toSrgb8bit(self: LinearColor, mapper: ToneMapper) Color {
    std.debug.assert(self.isValid());

    var mapped = mapper.toneMap(self);

    // Clamp the tone mapped values to the [0.0, 1.0] interval
    const zeroes: @Vector(3, Float) = @splat(0.0);
    const ones: @Vector(3, Float) = @splat(1.0);
    mapped.v = @max(@min(mapped.v, ones), zeroes);

    const gamma_col = srgbGammaCorrection(mapped);
    const r_gamma = gamma_col.v[0];
    const g_gamma = gamma_col.v[1];
    const b_gamma = gamma_col.v[2];

    return .{
        .r = @intFromFloat(@round(r_gamma * 255.0)),
        .g = @intFromFloat(@round(g_gamma * 255.0)),
        .b = @intFromFloat(@round(b_gamma * 255.0))
    };
}

pub fn fromSrgb8bit(c: Color) LinearColor {
    var res_v: @Vector(3, Float) = undefined;

    res_v[0] = @as(Float, @floatFromInt(c.r)) / 255.0;
    res_v[1] = @as(Float, @floatFromInt(c.g)) / 255.0;
    res_v[2] = @as(Float, @floatFromInt(c.b)) / 255.0;

    return inverseSrgbGammaCorrection(.{ .v = res_v });
}

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

pub fn randomInRange(rand: std.Random, min: Float, max: Float) LinearColor {
    return .init(
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max }),
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max }),
        rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max })
    );
}

// TESTING

fn expectLinearColorApproxEq(a: LinearColor, b: LinearColor, tolerance: Float) !void {
    try std.testing.expectApproxEqAbs(a.v[0], b.v[0], tolerance);
    try std.testing.expectApproxEqAbs(a.v[1], b.v[1], tolerance);
    try std.testing.expectApproxEqAbs(a.v[2], b.v[2], tolerance);
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

test "LinearColor.ToneMapper - Behavior and clamps" {
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

test "LinearColor.srgbGammaCorrection" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const srgb = c.srgbGammaCorrection();

    try std.testing.expectApproxEqAbs(@as(Float, 0.0), srgb.v[0], eps);
    const expected_mid = 1.055 * std.math.pow(Float, 0.5, 1.0 / 2.4) - 0.055;
    try std.testing.expectApproxEqAbs(expected_mid, srgb.v[1], eps);
    try std.testing.expectApproxEqAbs(@as(Float, 1.0), srgb.v[2], eps);
}

test "LinearColor.inverseSrgbGammaCorrection" {
    // Roughly recreate the srgb exact values from the previous test forward path to inverse them
    const mid_srgb = 1.055 * std.math.pow(Float, 0.5, 1.0 / 2.4) - 0.055;
    const srgb = LinearColor.init(0.0, mid_srgb, 1.0);
    const inverted = srgb.inverseSrgbGammaCorrection();
    try expectLinearColorApproxEq(LinearColor.init(0.0, 0.5, 1.0), inverted, eps);
}

test "LinearColor.gamma2Correction" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const g2 = c.gamma2Correction();
    try expectLinearColorApproxEq(LinearColor.init(0.0, @sqrt(0.5), 1.0), g2, eps);
}

test "LinearColor.gammaCorrection (Custom)" {
    const c = LinearColor.init(0.0, 0.5, 1.0);
    const g_custom = c.gammaCorrection(2.2);

    try std.testing.expectApproxEqAbs(@as(Float, 0.0), g_custom.v[0], eps);
    try std.testing.expectApproxEqAbs(@as(Float, std.math.pow(Float, 0.5, 1.0/2.2)), g_custom.v[1], eps);
    try std.testing.expectApproxEqAbs(@as(Float, 1.0), g_custom.v[2], eps);
}

test "LinearColor.toSrgb8bit" {
    // HDR clamping test
    const hdr_c = LinearColor.init(100.0, 0.0, 5.0);
    // GammaCompressionToneMapper won't restrict it to 1.0: 100^0.5 = 10.0 > 1.0
    const mapper = ToneMapper{ .gamma = .{ .a = 1.0, .gamma = 0.5 } };

    // toSrgb8bit MUST clamp the tone mapped result before applying srgb curve,
    // otherwise the internal asserts for <= 1.0 in srgbGammaCorrection would fail.
    const hdr_c8 = hdr_c.toSrgb8bit(mapper);

    // Both 100.0 and 5.0 should have been clamped to 255
    try std.testing.expectEqual(@as(u8, 255), hdr_c8.r);
    try std.testing.expectEqual(@as(u8, 0), hdr_c8.g);
    try std.testing.expectEqual(@as(u8, 255), hdr_c8.b);
}

test "LinearColor.fromSrgb8bit and roundtrip" {
    const c8 = Color{ .r = 0, .g = 127, .b = 255 };
    const lin = fromSrgb8bit(c8);
    // Linearized 127 is accurately calculable via the inverse curve:
    const expected_mid = std.math.pow(Float, (127.0 / 255.0 + 0.055) / 1.055, 2.4);
    try std.testing.expectApproxEqAbs(expected_mid, lin.v[1], eps);

    // Now map back with a Clamp mapper (which won't affect it since it's <= 1)
    const back_c8 = lin.toSrgb8bit(.{ .clamp = .{} });
    try std.testing.expectEqual(c8.r, back_c8.r);
    try std.testing.expectEqual(c8.g, back_c8.g);
    try std.testing.expectEqual(c8.b, back_c8.b);
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

