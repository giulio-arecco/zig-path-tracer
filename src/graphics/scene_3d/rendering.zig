pub const RenderSettings = @import("rendering/RenderSettings.zig");
pub const RayTracer = @import("rendering/RayTracer.zig");

test {
    _= @import("rendering/RayTracer.zig");
    _ = @import("rendering/RenderSettings.zig");
}
