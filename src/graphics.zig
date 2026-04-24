pub const scene_3d = @import("graphics/scene_3d.zig");
pub const Color = @import("graphics/Color.zig");
pub const Gradient = Color.Gradient;

test {
    _ = @import("graphics/Color.zig");
    _ = @import("graphics/scene_3d.zig");
}
