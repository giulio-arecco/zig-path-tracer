pub const Color = @import("graphics/color.zig").Color;
pub const Gradient = @import("graphics/color.zig").Gradient;
pub const scene_3d = @import("graphics/scene_3d.zig");

test {
    _ = @import("graphics/color.zig");
    _ = @import("graphics/scene_3d.zig");
}
