pub const raytracing = @import("rendering/raytracing.zig");
pub const RenderSettings = @import("rendering/RenderSettings.zig");

test {
    _ = @import("rendering/raytracing.zig");
    _ = @import("rendering/RenderSettings.zig");
}
