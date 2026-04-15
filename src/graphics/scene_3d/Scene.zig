const Scene = @This();

const Vec3 = @import("../../Vec3.zig");
const Camera = @import("Camera.zig");

camera: Camera,
focal_length: f16,
screen_width: u16,
screen_height: u16
