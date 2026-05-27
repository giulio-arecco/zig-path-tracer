const builtin = @import("builtin");
const RenderSettings = @import("graphics/scene_3d/rendering/RenderSettings.zig");

pub const Float = f32;
pub const SceneId = enum { ProceduralSpheres, CornellBox, Quads };
pub const RendererType = enum { Serial, Parallel };

pub const AppConfig = struct {
    render_settings: RenderSettings = .{},
    scene_id: SceneId = .CornellBox,
    renderer_type: RendererType = if (builtin.single_threaded) .Serial else .Parallel,
    track_progress: bool = false,
    time_report: bool = false
};
