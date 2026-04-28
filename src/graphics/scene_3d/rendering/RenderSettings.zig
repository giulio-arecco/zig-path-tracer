const RenderSettings = @This();

const config = @import("../../../config.zig");
const Float = config.Float;

image_width: u16,
image_height: u16,
ray_tmin: Float,
ray_tmax: Float,
samples_per_pixel: u16,
/// Color scale factor for a sum of pixel samples. A value of `1.0 / samples_per_pixel` leads to the pixel color being the average of the sampled colors.
pixel_samples_scale: Float,

pub fn getAspectRatio(self: RenderSettings) f32 {
    const f_width: f32 = @floatFromInt(self.image_width);
    const f_height: f32 = @floatFromInt(self.image_height);

    return f_width / f_height;
}

const std = @import("std");
const testing = std.testing;

test "getAspectRatio" {
    const rs1 = RenderSettings{ .image_width = 1920, .image_height = 1080, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    try testing.expectApproxEqAbs(1.7777777, rs1.getAspectRatio(), 0.000001);

    const rs2 = RenderSettings{ .image_width = 800, .image_height = 600, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    try testing.expectApproxEqAbs(1.3333333, rs2.getAspectRatio(), 0.000001);

    const rs3 = RenderSettings{ .image_width = 1000, .image_height = 1000, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    try testing.expectApproxEqAbs(1.0, rs3.getAspectRatio(), 0.000001);
}

