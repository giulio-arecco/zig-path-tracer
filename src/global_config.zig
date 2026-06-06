//! Global configuration and settings structures used across the path tracer.

const builtin = @import("builtin");
const UserRenderSettings = @import("graphics/scene_3d/rendering.zig").UserRenderSettings;
const RendererType = @import("graphics/scene_3d/rendering.zig").RendererType;

/// The primary floating-point type used throughout the path tracer calculations.
pub const Float = f32;

/// Identifiers for the pre-defined scenes available for rendering.
pub const SceneId = enum { ProceduralSpheres, CornellBox, Quads };

/// Available denoising algorithms that can be applied during post-processing.
pub const DenoiserType = enum { None, JointBilateral, ATrous  };

/// The main application configuration state.
pub const AppConfig = struct {
    user_render_settings: UserRenderSettings = .{},
    scene_id: SceneId = .CornellBox,
    denoiser_type: DenoiserType = .None,
    renderer_type: RendererType = if (builtin.single_threaded) .Serial else .Parallel,
    track_progress: bool = false,
    time_report: bool = false
};
