const std = @import("std");
const config = @import("../global_config.zig");
const math_utils = @import("../math_utils.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Color = @import("Color.zig");
const LinearColor = @import("LinearColor.zig");
const FrameBuffers = @import("scene_3d/rendering.zig").FrameBuffers;
const Material = @import("scene_3d/materials.zig").Material;
const Interval = math_utils.Interval(Float);

const expectLinearColorApproxEq = LinearColor.expectLinearColorApproxEq;
const approxEq = math_utils.approxEq;

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

pub const DenoiserContext = struct {
    in_irrad: []const LinearColor,
    temp_buf: []LinearColor,
    out_irrad: []LinearColor,
    albedo: []const LinearColor,
    normal: []const Vec3,
    depth: []const Float,
    image_width: u16,
    image_height: u16,
};

pub const Denoiser = union(enum) {
    joint_bilateral_denoiser: JointBilateralDenoiser,
    atrous_denoiser: ATrousDenoiser,

    pub fn apply(self: Denoiser, ctx: DenoiserContext) void {
        switch (self) {
            inline else => |p| p.apply(ctx)
        }
    }
};

pub const JointBilateralDenoiser = struct {
    kernel_size: u8,
    sigma_space: Float,
    sigma_normal: Float,
    sigma_depth: Float,
    // sigma_luma: Float,

    pub fn apply(self: JointBilateralDenoiser, ctx: DenoiserContext) void {
        std.debug.assert(self.kernel_size > 0);
        std.debug.assert(self.kernel_size % 2 != 0);
        std.debug.assert(self.sigma_space > 0);
        std.debug.assert(self.sigma_normal > 0);
        std.debug.assert(self.sigma_depth > 0);
        // std.debug.assert(self.sigma_luma > 0);

        const inv_two_sigma_space_sq = 1.0 / (2 * self.sigma_space * self.sigma_space);
        const inv_two_sigma_normal_sq = 1.0 / (2 * self.sigma_normal * self.sigma_normal);
        const inv_two_sigma_depth_sq = 1.0 / (2 * self.sigma_depth * self.sigma_depth);
        // const inv_two_sigma_luma_sq = 1.0 / (2 * self.sigma_luma * self.sigma_luma);

        for (0..ctx.image_height) |y| {
            for (0..ctx.image_width) |x| {
                const fx = @as(Float, @floatFromInt(x));
                const fy = @as(Float, @floatFromInt(y));

                const center_index = y * ctx.image_width + x;
                const center_depth = ctx.depth[center_index];
                const center_is_bg = std.math.isInf(center_depth);
                if (center_is_bg) {
                    ctx.out_irrad[center_index] = ctx.in_irrad[center_index];
                    continue;
                }

                // const min_albedo: @Vector(3, Float) = @splat(1e-3);
                // const center_irrad = ctx.in_irrad[center_index].div(.{ .v = @max(ctx.albedo[center_index].v, min_albedo) });
                // const center_luma = luminanceSrgb(center_irrad);
                // const center_luma_norm = center_luma / (1.0 + center_luma);
                const center_normal = ctx.normal[center_index];

                var irrad_sum = LinearColor.black;
                var weights_sum: Float = 0.0;

                const kernel_radius = self.kernel_size / 2;

                const kernel_x_start = if (x >= kernel_radius) x - kernel_radius else 0;
                const kernel_x_end =   if (x + kernel_radius < ctx.image_width ) x + kernel_radius else ctx.image_width - 1;
                const kernel_y_start = if (y >= kernel_radius) y - kernel_radius else 0;
                const kernel_y_end =   if (y + kernel_radius < ctx.image_height ) y + kernel_radius else ctx.image_height - 1;

                var j: usize = kernel_y_start;
                while(j <= kernel_y_end) : (j += 1) {
                    const fj = @as(Float, @floatFromInt(j));
                    var i: usize = kernel_x_start;
                    while(i <= kernel_x_end) : (i += 1) {
                        const fi = @as(Float, @floatFromInt(i));

                        const neighbor_index = j * ctx.image_width + i;
                        const neighbor_depth = ctx.depth[neighbor_index];
                        const neighbor_is_bg = std.math.isInf(neighbor_depth);
                        if (neighbor_is_bg) continue;

                        // const neighbor_irrad = ctx.in_irrad[neighbor_index].div(.{ .v = @max(ctx.albedo[neighbor_index].v, min_albedo) });
                        // const neighbor_luma = luminanceSrgb(neighbor_irrad);
                        // const neighbor_luma_norm = neighbor_luma / (1.0 + neighbor_luma);
                        const neighbor_normal = ctx.normal[neighbor_index];

                        const sq_dist = (fx - fi) * (fx - fi) + (fy - fj) * (fy - fj);
                        const normals_delta = 1.0 - std.math.clamp(Vec3.dot(center_normal, neighbor_normal), -1.0, 1.0);
                        const depth_diff = center_depth - neighbor_depth;
                        // const luma_delta = center_luma_norm - neighbor_luma_norm;

                        const w_space = @exp(-sq_dist * inv_two_sigma_space_sq);
                        const w_normal = @exp(-(normals_delta * normals_delta) * inv_two_sigma_normal_sq);
                        const w_depth = @exp(-(depth_diff * depth_diff) * inv_two_sigma_depth_sq);
                        // const w_luma = @exp(-(luma_delta * luma_delta) * inv_two_sigma_luma_sq);

                        // const total_w = w_space * w_normal * w_depth * w_luma;
                        const total_w = w_space * w_normal * w_depth;

                        irrad_sum = irrad_sum.add(ctx.in_irrad[neighbor_index].scalarMul(total_w));
                        weights_sum += total_w;
                    }
                }

                const center_out_irrad = if (approxEq(Float, weights_sum, 0.0)) ctx.in_irrad[center_index] else irrad_sum.scalarDiv(weights_sum);
                ctx.out_irrad[center_index] = center_out_irrad;
            }
        }
    }
};

pub const ATrousDenoiser = struct {
    iterations: u8,
    sigma_normal: Float,
    sigma_depth: Float,

    pub const ATrousPassContext = struct {
        in_irrad: []const LinearColor,
        out_irrad: []LinearColor,
        albedo: []const LinearColor,
        normal: []const Vec3,
        depth: []const Float,
        image_width: u16,
        image_height: u16,
        sigma_normal: Float,
        sigma_depth: Float,
        step: usize
    };

    pub fn apply(self: ATrousDenoiser, ctx: DenoiserContext) void {
        std.debug.assert(self.sigma_normal > 0);
        std.debug.assert(self.sigma_depth > 0);

        var curr_in = ctx.in_irrad;
        var curr_out = ctx.out_irrad;
        var unused_buf = ctx.temp_buf;
        var step: usize = 1;

        for(0..self.iterations) |_| {
            atrousPass(.{
                .in_irrad = curr_in,
                .out_irrad = curr_out,
                .albedo = ctx.albedo,
                .normal = ctx.normal,
                .depth = ctx.depth,
                .image_height = ctx.image_height,
                .image_width = ctx.image_width,
                .sigma_normal = self.sigma_normal,
                .sigma_depth = self.sigma_depth,
                .step = step,
            }, );

            curr_in = curr_out;
            std.mem.swap([]LinearColor, &curr_out, &unused_buf);

            step <<= 1;
        }

        std.debug.assert(curr_in.len == ctx.out_irrad.len);
        if (curr_in.ptr != ctx.out_irrad.ptr) {
            @memcpy(ctx.out_irrad, curr_in);
        }
    }

    fn atrousPass(ctx: ATrousPassContext) void {
        // const min_albedo: @Vector(3, Float) = @splat(1e-3);
        const inv_two_sigma_normal_sq = 1.0 / (2 * ctx.sigma_normal * ctx.sigma_normal);
        const inv_two_sigma_depth_sq = 1.0 / (2 * ctx.sigma_depth * ctx.sigma_depth);
        const h = [5]Float { 1.0 / 16.0, 1.0 / 4.0, 3.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0 }; // Wavelet weights
        const int_step = @as(isize, @intCast(ctx.step));
        const int_height = @as(isize, ctx.image_height);
        const int_width = @as(isize, ctx.image_width);

        for (0..ctx.image_height) |y| {
            const int_y = @as(isize, @intCast(y));
            for (0..ctx.image_width) |x| {
                const int_x = @as(isize, @intCast(x));
                const center_index = y * ctx.image_width + x;
                const center_depth = ctx.depth[center_index];
                const center_is_bg = std.math.isInf(center_depth);
                if (center_is_bg) {
                    ctx.out_irrad[center_index] = ctx.in_irrad[center_index];
                    continue;
                }

                // const center_albedo: @Vector(3, Float) = @max(ctx.albedo[center_index].v, min_albedo);
                // const center_irrad = ctx.in_color[center_index].div(.{ .v = center_albedo });
                const center_normal = ctx.normal[center_index];

                var irrad_sum = LinearColor.black;
                var weights_sum: Float = 0.0;

                for (0..5) |ky| {
                    const neighbor_y = int_y + (@as(isize, @intCast(ky)) - 2) * int_step;
                    if (neighbor_y < 0 or neighbor_y >= int_height) continue;

                    for (0..5) |kx| {
                        const neighbor_x = int_x + (@as(isize, @intCast(kx)) - 2) * int_step;
                        if (neighbor_x < 0 or neighbor_x >= int_width) continue;

                        const neighbor_index = @as(usize, @intCast(neighbor_y)) * ctx.image_width + @as(usize, @intCast(neighbor_x));
                        const neighbor_depth = ctx.depth[neighbor_index];
                        const neighbor_is_bg = std.math.isInf(neighbor_depth);
                        if (neighbor_is_bg) continue;

                        // const neighbor_albedo: @Vector(3, Float) = @max(ctx.albedo[neighbor_index].v, min_albedo);
                        // const neighbor_irrad = ctx.in_color[neighbor_index].div(.{ .v = neighbor_albedo });
                        const neighbor_normal = ctx.normal[neighbor_index];

                        const normals_delta = 1.0 - std.math.clamp(Vec3.dot(center_normal, neighbor_normal), -1.0, 1.0);
                        const depth_diff = center_depth - neighbor_depth;

                        const w_normal = @exp(-(normals_delta * normals_delta) * inv_two_sigma_normal_sq);
                        const w_depth = @exp(-(depth_diff * depth_diff) * inv_two_sigma_depth_sq);

                        const w_kernel = h[kx] * h[ky];
                        const total_w = w_kernel * w_normal * w_depth;

                        irrad_sum = irrad_sum.add(ctx.in_irrad[neighbor_index].scalarMul(total_w));
                        weights_sum += total_w;
                    }
                }

                const center_out_irrad = if (approxEq(Float, weights_sum, 0.0)) ctx.in_irrad[center_index] else irrad_sum.scalarDiv(weights_sum);
                ctx.out_irrad[center_index] = center_out_irrad;
            }
        }
    }
};

pub const DisplayTransform = struct {
    tone_mapper: ToneMapper,
    transform_type: DisplayTransformType,

    pub const DisplayTransformType = enum { toSrgb8bit };

    pub fn apply(self: DisplayTransform, hdr_buf: []const LinearColor, out_buf: []u8) void {
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

pub fn colorRecomposition(albedo_buf: []const LinearColor, in_irrad: []const LinearColor, out_color: []LinearColor) void {
    for(in_irrad, albedo_buf, out_color) |irrad, albedo, *color| {
        color.* = irrad.mul(albedo);
    }
}

pub fn getRecompositionAlbedo(mat: *const Material) LinearColor {
    switch (mat.*) {
        inline .lambertian, .metal => |m| return m.albedo,
        inline .dielectic, .diffuse_light => return LinearColor.white,
    }
}

pub fn luminanceSrgb(c: LinearColor) Float {
    return 0.2126 * c.r() + 0.7152 * c.g() + 0.0722 * c.b();
}

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

    dt.apply(&hdr_buf, &out_buf);

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
    dt.apply(&hdr_buf, &out_buf);
}

