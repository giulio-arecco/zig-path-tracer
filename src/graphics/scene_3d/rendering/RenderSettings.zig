const RenderSettings = @This();

image_width: u16,
image_height: u16,

pub fn getAspectRatio(self: RenderSettings) f32 {
    const f_width: f32 = @floatFromInt(self.image_width);
    const f_height: f32 = @floatFromInt(self.image_height);

    return f_width / f_height;
}

const std = @import("std");
const testing = std.testing;

test "getAspectRatio" {
    const rs1 = RenderSettings{ .image_width = 1920, .image_height = 1080 };
    try testing.expectApproxEqAbs(1.7777777, rs1.getAspectRatio(), 0.000001);

    const rs2 = RenderSettings{ .image_width = 800, .image_height = 600 };
    try testing.expectApproxEqAbs(1.3333333, rs2.getAspectRatio(), 0.000001);

    const rs3 = RenderSettings{ .image_width = 1000, .image_height = 1000 };
    try testing.expectApproxEqAbs(1.0, rs3.getAspectRatio(), 0.000001);
}

