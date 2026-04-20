pub const Scene = @import("scene_3d/Scene.zig");
pub const Camera = @import("scene_3d/Camera.zig");
pub const Ray = @import("scene_3d/Ray.zig");
pub const rendering = @import("scene_3d/rendering.zig");

test {
    _ = @import("scene_3d/Scene.zig");
    _ = @import("scene_3d/Camera.zig");
    _ = @import("scene_3d/Ray.zig");
    _ = @import("scene_3d/rendering.zig");
}
