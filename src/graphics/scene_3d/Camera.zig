//! A camera in 3D space.
//!
//! The camera coordinate system is right-handed, so the *forward* vector
//! points towards the camera and is computed as the cross product between
//! the *right* and the *up* vectors.
//!
//! **WARNING**: The mathematical invariants of this struct are managed internally.
//! Fields such as `_pos`, `_up`, `_right` and `_forward` should be treated as read-only
//! by external users. To mutate the camera orientation, use the provided
//! methods instead of modifying the fields directly.
const Camera = @This();

const std = @import("std");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Float = @import("../../config.zig").Float;
const RenderSettings = @import("rendering/RenderSettings.zig");
const Ray = @import("Ray.zig");

const normalized = Vec3.normalized;
const sub = Vec3.sub;
const dot = Vec3.dot;
const cross = Vec3.cross;
const approxEq = math_utils.approxEq;

/// The vertical view angle (vertical field of view) in degrees. Treat as **immutable**.
_vertical_fov: Float,
/// The camera focal distance. Treat as **immutable**.
_focal_distance: Float,
/// The position of the camera. Treat as **immutable**.
_pos: Vec3,
/// The camera up vector. Treat as **immutable**.
_up: Vec3,
/// The camera right vector. Treat as **immutable**.
_right: Vec3,
/// The camera forward vector. Treat as **immutable**.
_forward: Vec3,
/// The center of the viewport in world space coordinates. Treat as **immutable**.
_viewport_center: Vec3,
/// The horizontal distance between two adjacent pixels in the viewport. Treat as **immutable**.
_pixel_delta_u: Vec3,
/// The vertical distance between two adjacent pixels in the viewport. Treat as **immutable**.
_pixel_delta_v: Vec3,
/// The location of the first pixel in the viewport. Treat as **immutable**.
_pixel_top_left: Vec3,

pub fn init(pos: Vec3, up: Vec3, right: Vec3, focal_distance: Float, vertical_fov: Float, render_settings: RenderSettings) Camera {
    // Determine the camera orientation
    const norm_up = if (up.isNormalized()) up else normalized(up);
    const norm_right = if (right.isNormalized()) right else normalized(right);
    const norm_forward = cross(norm_right, norm_up);

    // Finish initialization
    return viewportSetup(pos, norm_up, norm_right, norm_forward, focal_distance, vertical_fov, render_settings);
}

pub fn initLookAt (from: Vec3, to: Vec3, vertical_fov: Float, focal_distance: Float, render_settings: RenderSettings) Camera {
    // Determine the camera orientation
    const norm_forward = normalized(sub(from, to));

    var randVec = Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 };
    if (approxEq(Float, 1.0, @abs(dot(randVec, norm_forward)))) {
        // If @abs(a.dot(b)) == 1.0, a and b are parallel and their cross product will be a zero-vector.
        // In this case, change randVec to be z-aligned.
        randVec = Vec3 {.x = 0.0, .y = 0.0, .z = 1.0 };
    }

    const norm_right = cross(randVec, norm_forward);
    const norm_up = cross(norm_forward, norm_right);

    // Finish initialization
    return viewportSetup(from, norm_up, norm_right, norm_forward, focal_distance, vertical_fov, render_settings);
}

pub fn getRay(self: Camera, random: std.Random, x_screen: usize, y_screen: usize, sample_center: bool) Ray {
    const offset: Vec3 = if (sample_center) .{ .x = 0.0, .y = 0.0, .z = 0.0 } else sample_unit_square(random);

    const pixel_sample = self._pixel_top_left.
                add(self._pixel_delta_u.scalarMul(@as(Float, @floatFromInt(x_screen)) + offset.x)).
                add(self._pixel_delta_v.scalarMul(@as(Float, @floatFromInt(y_screen)) + offset.y));

    return .{
        .origin = self._pos,
        .dir = pixel_sample.sub(self._pos),
    };
}

pub fn sample_unit_square(prng: std.Random) Vec3 {
    return .{ .x = prng.float(Float) - 0.5, .y = prng.float(Float) - 0.5, .z = 0.0 };
}

fn viewportSetup(pos: Vec3, norm_up: Vec3, norm_right: Vec3, norm_forward: Vec3, focal_distance: Float, vertical_fov: Float, render_settings: RenderSettings) Camera {
    const theta: Float = std.math.degreesToRadians(vertical_fov);
    const viewport_height = 2.0 * focal_distance * @tan(theta / 2.0);
    const viewport_width = viewport_height * render_settings.getAspectRatio();

    // Calculate the horizontal and vertical delta vectors from pixel to pixel
    const pixel_delta_u = norm_right.scalarMul(viewport_width / @as(f32, @floatFromInt(render_settings.image_width)));
    const pixel_delta_v = norm_up.scalarMul(-viewport_height / @as(f32, @floatFromInt(render_settings.image_height))); // The viewport's v-axis direction is -camera_up

    // See the Camera docs to understand why the following is a subtraction and not an addition (it has to do with the camera's forward direction)
    const viewport_center = pos.sub(norm_forward.scalarMul(focal_distance));

    // Calculate the location of the upper left pixel
    const viewport_top_left = viewport_center.
        sub(norm_right.scalarMul(viewport_width / 2)).
        add(norm_up.scalarMul(viewport_height / 2));
    const pixel_top_left = viewport_top_left.add((pixel_delta_u.add(pixel_delta_v)).scalarDiv(2.0));

    return Camera {
        ._vertical_fov = vertical_fov,
        ._focal_distance = focal_distance,
        ._pos = pos,
        ._up = norm_up,
        ._right = norm_right,
        ._forward = norm_forward,
        ._viewport_center = viewport_center,
        ._pixel_delta_u = pixel_delta_u,
        ._pixel_delta_v = pixel_delta_v,
        ._pixel_top_left = pixel_top_left
    };
}

const pi = std.math.pi;

test "init" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    const pos = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    var right = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    var camera = init(pos, up, right, 10.0, 90.0, rs);

    try std.testing.expectApproxEqRel(10.0, camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    up = Vec3{ .x = 0.0, .y = std.math.sqrt1_2, .z = std.math.sqrt1_2 };
    camera = init(pos, up, right, std.math.floatMax(Float) / 2.0, 90.0, rs);
    try std.testing.expectApproxEqRel(std.math.floatMax(Float) / 2.0, camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = -std.math.sqrt1_2, .z = std.math.sqrt1_2 }));

    up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    right = Vec3{ .x = std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 };
    camera = init(pos, up, right, std.math.floatMax(Float) / 2.0, 90.0, rs);
    try std.testing.expectApproxEqRel(std.math.floatMax(Float) / 2.0, camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 }));
}

test "initLookAt" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    const pos = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    var to = Vec3{ .x = 0.0, .y = 0.0, .z = -50.0 };
    var camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);

    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    to = Vec3{ .x = @cos(pi / 4.0), .y = 0, .z = @sin(pi / 4.0) };
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, .{ .x = 0.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = -std.math.sqrt1_2 }));

    to = Vec3{ .x = 0.0, .y = 1.0, .z = -50.0 };
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(!Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    to = Vec3{ .x = 1.0, .y = 0.0, .z = -50.0 };
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    to = Vec3{ .x = 0.0, .y = 20.0, .z = 0.0 };
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = -1.0, .z = 0.0 }));

    to = Vec3{ .x = 0.0, .y = -20.0, .z = 0.0 };
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focal_distance, @sqrt(std.math.floatEps(Float)));
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = -1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
}

test "viewportSetup" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_tmin = 0.0, .ray_tmax = 100.0, .samples_per_pixel = 1, .pixel_samples_scale = 1.0 };
    const pos = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const to = Vec3{ .x = 0.0, .y = 0.0, .z = -10.0 };
    const fov: Float = 90.0;
    const camera = initLookAt(pos, to, fov, 10.0, rs);

    // Verify orthogonality
    try std.testing.expectApproxEqAbs(0.0, dot(camera._right, camera._up), @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqAbs(0.0, dot(camera._right, camera._forward), @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqAbs(0.0, dot(camera._up, camera._forward), @sqrt(std.math.floatEps(Float)));

    const h = 2.0 * camera._focal_distance * @tan(std.math.degreesToRadians(fov) / 2.0);
    try std.testing.expectApproxEqRel(20.0, h, @sqrt(std.math.floatEps(Float)));
    const w = h * rs.getAspectRatio();
    try std.testing.expectApproxEqRel(40.0, w, @sqrt(std.math.floatEps(Float)));

    try std.testing.expectApproxEqRel(w / 800.0, camera._pixel_delta_u.magnitude(), @sqrt(std.math.floatEps(Float)));
    try std.testing.expectApproxEqRel(h / 400.0, camera._pixel_delta_v.magnitude(), @sqrt(std.math.floatEps(Float)));
}
