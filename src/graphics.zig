pub const scene_3d = @import("graphics/scene_3d.zig");
pub const Color = @import("graphics/Color.zig");
pub const LinearColor = @import("graphics/LinearColor.zig");
pub const Gradient = Color.Gradient;
pub const LinearGradient = LinearColor.LinearGradient;

test {
    _ = @import("graphics/Color.zig");
    _ = @import("graphics/scene_3d.zig");
    _ = @import("graphics/LinearColor.zig");
}
