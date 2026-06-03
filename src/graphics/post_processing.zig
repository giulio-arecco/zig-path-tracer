const std = @import("std");
const config = @import("../global_config.zig");
const math_utils = @import("../math_utils.zig");
const rendering = @import("scene_3d/rendering.zig");

const Float = config.Float;
const Vec3 = @import("../Vec3.zig");
const Color = @import("Color.zig");
const LinearColor = @import("LinearColor.zig");
const FrameBuffers = rendering.FrameBuffers;
const GBuffers = rendering.GBuffers;
const GBuffersReadOnly = rendering.GBuffersReadOnly;
const Material = @import("scene_3d/materials.zig").Material;
const Camera = @import("scene_3d/Camera.zig");
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
    camera: Camera,
    in_out_buf: []LinearColor,
    ping_pong_buf: []LinearColor,
    is_specular: bool,
    g_buffers: GBuffersReadOnly,
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
    /// A high tolerance smooths GI noise, but blocks the kernel at sharp irradiance cliffs (like coplanar emissive lights) to reduce ringing.
    diffuse_sigma_luma: Float,
    specular_sigma_luma: Float,

    pub fn apply(self: JointBilateralDenoiser, ctx: DenoiserContext) void {
        std.debug.assert(self.kernel_size > 0);
        std.debug.assert(self.kernel_size % 2 != 0);
        std.debug.assert(self.sigma_space > 0);
        std.debug.assert(self.sigma_normal > 0);
        std.debug.assert(self.sigma_depth > 0);
        std.debug.assert(self.diffuse_sigma_luma > 0);


        const inv_two_sigma_normal_sq = 1.0 / (2.0 * self.sigma_normal * self.sigma_normal);
        const inv_two_sigma_depth_sq = 1.0 / (2.0 * self.sigma_depth * self.sigma_depth);
        const diffuse_inv_two_sigma_space_sq = 1.0 / (2.0 * self.sigma_space * self.sigma_space);
        const diffuse_inv_two_sigma_luma_sq = 1.0 / (2.0 * self.diffuse_sigma_luma * self.diffuse_sigma_luma);

        // const albedo_buf = ctx.g_buffers.albedo_buf;
        const normal_buf = ctx.g_buffers.normal_buf;
        const depth_buf = ctx.g_buffers.depth_buf;
        const roughness_buf = ctx.g_buffers.roughness_buf;

        for (0..ctx.image_height) |y| {
            for (0..ctx.image_width) |x| {
                const fx = @as(Float, @floatFromInt(x));
                const fy = @as(Float, @floatFromInt(y));

                const center_index = y * ctx.image_width + x;
                const center_depth = depth_buf[center_index];
                const center_is_bg = std.math.isInf(center_depth);
                if (center_is_bg) {
                    ctx.ping_pong_buf[center_index] = ctx.in_out_buf[center_index];
                    continue;
                }

                const center_normal = normal_buf[center_index];

                const rayToCenter = ctx.camera.getRayToCenter(x, y);
                const p_center = rayToCenter.at(center_depth);

                const l_center = luminanceSrgb(ctx.in_out_buf[center_index]);
                const center_luma_norm = l_center / (1.0 + l_center);

                var inv_two_sigma_space_sq = diffuse_inv_two_sigma_space_sq;
                var inv_two_sigma_luma_sq = diffuse_inv_two_sigma_luma_sq;
                if (ctx.is_specular) {
                    // Modulate luma tolerance with roughness to protect sharp reflections.
                    const modulated_sigma_space = @max(self.sigma_space * roughness_buf[center_index], 1e-3);
                    inv_two_sigma_space_sq = 1.0 / (2.0 * modulated_sigma_space * modulated_sigma_space);

                    const modulated_sigma_luma = @max(self.specular_sigma_luma * roughness_buf[center_index], 1e-3);
                    inv_two_sigma_luma_sq = 1.0 / (2.0 * modulated_sigma_luma * modulated_sigma_luma);
                }

                var color_sum = LinearColor.black;
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
                        const neighbor_depth = depth_buf[neighbor_index];
                        const neighbor_normal = normal_buf[neighbor_index];

                        const l = luminanceSrgb(ctx.in_out_buf[neighbor_index]);
                        const neighbor_luma_norm = l / (1.0 + l);

                        const sq_dist = (fx - fi) * (fx - fi) + (fy - fj) * (fy - fj);
                        const normals_delta = 1.0 - std.math.clamp(Vec3.dot(center_normal, neighbor_normal), -1.0, 1.0);
                        const luma_delta = center_luma_norm - neighbor_luma_norm;
                        const plane_dist = blk: {
                            // Infinite depth mathematically forces w_depth to 0.0, handling background boundaries without explicit branching
                            if (std.math.isInf(neighbor_depth)) break :blk std.math.inf(Float);

                            const rayToNeighbor = ctx.camera.getRayToCenter(i, j);
                            const p_neighbor = rayToNeighbor.at(neighbor_depth);

                            const v_diff = p_neighbor.sub(p_center);
                            break :blk @abs(Vec3.dot(v_diff, center_normal));
                        };

                        const w_space = @exp(-sq_dist * inv_two_sigma_space_sq);
                        const w_normal = @exp(-(normals_delta * normals_delta) * inv_two_sigma_normal_sq);
                        const w_depth = @exp(-(plane_dist * plane_dist) * inv_two_sigma_depth_sq);
                        const w_luma = @exp(-(luma_delta * luma_delta) * inv_two_sigma_luma_sq);

                        const total_w = w_space * w_normal * w_depth * w_luma;

                        color_sum = color_sum.add(ctx.in_out_buf[neighbor_index].scalarMul(total_w));
                        weights_sum += total_w;
                    }
                }

                const center_out = if (approxEq(Float, weights_sum, 0.0)) ctx.in_out_buf[center_index] else color_sum.scalarDiv(weights_sum);
                ctx.ping_pong_buf[center_index] = center_out;
            }
        }

        @memcpy(ctx.in_out_buf, ctx.ping_pong_buf);
    }
};

pub const ATrousDenoiser = struct {
    diffuse_iterations: u8,
    specular_iterations: u8,
    sigma_normal: Float,
    sigma_depth: Float,
    /// A high tolerance smooths GI noise, but blocks the kernel at sharp irradiance cliffs (like coplanar emissive lights) to reduce ringing.
    diffuse_sigma_luma: Float,
    specular_sigma_luma: Float,

    pub const h = [5]Float { 1.0 / 16.0, 1.0 / 4.0, 3.0 / 8.0, 1.0 / 4.0, 1.0 / 16.0 }; // Wavelet weights

    pub const ATrousPassContext = struct {
        camera: Camera,
        in_buf: []LinearColor,
        out_buf: []LinearColor,
        is_specular: bool,
        g_buffers: GBuffersReadOnly,
        image_width: u16,
        image_height: u16,
        sigma_normal: Float,
        sigma_depth: Float,
        diffuse_sigma_luma: Float,
        specular_sigma_luma: Float,
        step: usize
    };

    pub fn apply(self: ATrousDenoiser, ctx: DenoiserContext) void {
        std.debug.assert(self.sigma_normal > 0);
        std.debug.assert(self.sigma_depth > 0);

        var curr_in = ctx.in_out_buf;
        var curr_out = ctx.ping_pong_buf;
        var step: usize = 1;

        const iterations = if (ctx.is_specular) self.specular_iterations else self.diffuse_iterations;
        for(0..iterations) |_| {
            atrousPass(.{
                .camera = ctx.camera,
                .in_buf = curr_in,
                .out_buf = curr_out,
                .is_specular = ctx.is_specular,
                .g_buffers = ctx.g_buffers,
                .image_height = ctx.image_height,
                .image_width = ctx.image_width,
                .sigma_normal = self.sigma_normal,
                .sigma_depth = self.sigma_depth,
                .diffuse_sigma_luma = self.diffuse_sigma_luma,
                .specular_sigma_luma = self.specular_sigma_luma,
                .step = step,
            }, );

            // Ping-pong buffering minimizes memory footprint by swapping pointers between two shared buffers across all iterations and channels
            std.mem.swap([]LinearColor, &curr_in, &curr_out);
            step <<= 1;
        }

        std.debug.assert(curr_in.len == ctx.in_out_buf.len);
        // Ensure the final denoised data always lands in the original input buffer if the total number of iterations was odd
        if (curr_in.ptr != ctx.in_out_buf.ptr) {
            @memcpy(ctx.in_out_buf, curr_in);
        }
    }

    fn atrousPass(ctx: ATrousPassContext) void {
        // const min_albedo: @Vector(3, Float) = @splat(1e-3);
        const inv_two_sigma_normal_sq = 1.0 / (2 * ctx.sigma_normal * ctx.sigma_normal);
        const inv_two_sigma_depth_sq = 1.0 / (2 * ctx.sigma_depth * ctx.sigma_depth);
        const diffuse_inv_two_sigma_luma_sq =
            if (!ctx.is_specular) 1.0 / (2.0 * ctx.diffuse_sigma_luma * ctx.diffuse_sigma_luma)
            else undefined;

        const int_step = @as(isize, @intCast(ctx.step));
        const int_height = @as(isize, ctx.image_height);
        const int_width = @as(isize, ctx.image_width);

        const normal_buf = ctx.g_buffers.normal_buf;
        const depth_buf = ctx.g_buffers.depth_buf;
        const roughness_buf = ctx.g_buffers.roughness_buf;

        for (0..ctx.image_height) |y| {
            const int_y = @as(isize, @intCast(y));
            for (0..ctx.image_width) |x| {
                const int_x = @as(isize, @intCast(x));
                const center_index = y * ctx.image_width + x;
                const center_depth = depth_buf[center_index];
                const center_is_bg = std.math.isInf(center_depth);
                if (center_is_bg) {
                    ctx.out_buf[center_index] = ctx.in_buf[center_index];
                    continue;
                }

                const center_normal = normal_buf[center_index];

                const rayToCenter = ctx.camera.getRayToCenter(x, y);
                const p_center = rayToCenter.at(center_depth);

                const l_center = luminanceSrgb(ctx.in_buf[center_index]);
                const center_luma_norm = l_center / (1.0 + l_center);

                const inv_two_sigma_luma_sq = if (ctx.is_specular) blk: {
                    // Modulate luma tolerance with roughness to protect sharp reflections.
                    const modulated_sigma_luma = @max(ctx.specular_sigma_luma * roughness_buf[center_index], 1e-3);
                    break :blk 1.0 / (2.0 * modulated_sigma_luma * modulated_sigma_luma);
                }
                else diffuse_inv_two_sigma_luma_sq;

                var color_sum = LinearColor.black;
                var weights_sum: Float = 0.0;

                for (0..5) |ky| {
                    const neighbor_y = int_y + (@as(isize, @intCast(ky)) - 2) * int_step;
                    if (neighbor_y < 0 or neighbor_y >= int_height) continue;

                    const neighbor_y_usize = @as(usize, @intCast(neighbor_y));
                    for (0..5) |kx| {
                        const neighbor_x = int_x + (@as(isize, @intCast(kx)) - 2) * int_step;
                        if (neighbor_x < 0 or neighbor_x >= int_width) continue;

                        const neighbor_x_usize = @as(usize, @intCast(neighbor_x));
                        const neighbor_index = neighbor_y_usize * ctx.image_width + neighbor_x_usize;
                        const neighbor_depth = depth_buf[neighbor_index];
                        const neighbor_normal = normal_buf[neighbor_index];

                        const l = luminanceSrgb(ctx.in_buf[neighbor_index]);
                        const neighbor_luma_norm = l / (1.0 + l);

                        const normals_delta = 1.0 - std.math.clamp(Vec3.dot(center_normal, neighbor_normal), -1.0, 1.0);
                        const luma_delta = center_luma_norm - neighbor_luma_norm;
                        const plane_dist = blk: {
                            // Infinite depth mathematically forces w_depth to 0.0, handling background boundaries without explicit branching
                            if (std.math.isInf(neighbor_depth)) break :blk std.math.inf(Float);

                            const rayToNeighbor = ctx.camera.getRayToCenter(neighbor_x_usize, neighbor_y_usize);
                            const p_neighbor = rayToNeighbor.at(neighbor_depth);

                            const v_diff = p_neighbor.sub(p_center);
                            break :blk @abs(Vec3.dot(v_diff, center_normal));
                        };

                        const w_normal = @exp(-(normals_delta * normals_delta) * inv_two_sigma_normal_sq);
                        const w_depth = @exp(-(plane_dist * plane_dist) * inv_two_sigma_depth_sq);
                        const w_luma = @exp(-(luma_delta * luma_delta) * inv_two_sigma_luma_sq);

                        const w_kernel = h[kx] * h[ky];
                        const total_w = w_kernel * w_normal * w_depth * w_luma;

                        color_sum = color_sum.add(ctx.in_buf[neighbor_index].scalarMul(total_w));
                        weights_sum += total_w;
                    }
                }

                const center_out = if (approxEq(Float, weights_sum, 0.0)) ctx.in_buf[center_index] else color_sum.scalarDiv(weights_sum);
                ctx.out_buf[center_index] = center_out;
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

pub fn colorRecomposition(diffuse_buf: []const LinearColor, specular_buf: []const LinearColor, emission_buf: []const LinearColor, albedo_buf: []const LinearColor, out_buf: []LinearColor) void {
    for(diffuse_buf, specular_buf, emission_buf, albedo_buf, out_buf) |diffuse, specular, emission, albedo, *out| {
        out.* = (diffuse.mul(albedo)).add(specular).add(emission);
    }
}

pub fn getRecompositionAlbedo(mat: *const Material) LinearColor {
    switch (mat.*) {
        inline .lambertian, .metal => |m| return m.albedo,
        inline .dielectric, .diffuse_light => return LinearColor.white,
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

