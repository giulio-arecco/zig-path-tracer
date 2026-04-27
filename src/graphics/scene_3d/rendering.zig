pub const RenderSettings = @import("rendering/RenderSettings.zig");
pub const RayTracer = @import("rendering/RayTracer.zig");
pub const ParallelRayTracer = @import("rendering/ParallelRayTracer.zig");

test {
    _ = @import("rendering/RayTracer.zig");
    _ = @import("rendering/ParallelRayTracer.zig");
    _ = @import("rendering/RenderSettings.zig");
}
