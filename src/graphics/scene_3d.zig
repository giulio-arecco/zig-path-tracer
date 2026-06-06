//! Module exporting the spatial components making up scene geometries, camera representations,
//! materials behavior and global rendering pipelines. Forms the main public API of the 3D graphics system.

pub const Scene = @import("scene_3d/Scene.zig");
pub const Camera = @import("scene_3d/Camera.zig");
pub const Ray = @import("scene_3d/Ray.zig");
pub const geometry = @import("scene_3d/geometry.zig");
pub const rendering = @import("scene_3d/rendering.zig");
pub const materials = @import("scene_3d/materials.zig");

test {
    _ = @import("scene_3d/Scene.zig");
    _ = @import("scene_3d/Camera.zig");
    _ = @import("scene_3d/Ray.zig");
    _ = @import("scene_3d/geometry.zig");
    _ = @import("scene_3d/rendering.zig");
    _ = @import("scene_3d/materials.zig");
}
