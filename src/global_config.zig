const builtin = @import("builtin");
const UserRenderSettings = @import("graphics/scene_3d/rendering.zig").UserRenderSettings;
const RendererType = @import("graphics/scene_3d/rendering.zig").RendererType;

pub const Float = f32;
pub const SceneId = enum { ProceduralSpheres, CornellBox, Quads };
pub const DenoiserType = enum { None, JointBilateral, ATrous  };

pub const AppConfig = struct {
    user_render_settings: UserRenderSettings = .{},
    scene_id: SceneId = .CornellBox,
    denoiser_type: DenoiserType = .None,
    renderer_type: RendererType = if (builtin.single_threaded) .Serial else .Parallel,
    track_progress: bool = false,
    time_report: bool = false
};
