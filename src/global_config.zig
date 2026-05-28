const builtin = @import("builtin");
const RenderSettings = @import("graphics/scene_3d/rendering.zig").RenderSettings;
const RendererType = @import("graphics/scene_3d/rendering.zig").RendererType;

pub const Float = f32;
pub const SceneId = enum { ProceduralSpheres, CornellBox, Quads };

pub const AppConfig = struct {
    render_settings: RenderSettings = .{},
    scene_id: SceneId = .CornellBox,
    renderer_type: RendererType = if (builtin.single_threaded) .Serial else .Parallel,
    track_progress: bool = false,
    time_report: bool = false
};

pub const default_app_config = AppConfig {};
