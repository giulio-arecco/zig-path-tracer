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
const Float = @import("../../global_config.zig").Float;
const RenderSettings = @import("rendering.zig").RenderSettings;
const Ray = @import("Ray.zig");

const normalized = Vec3.normalized;
const sub = Vec3.sub;
const dot = Vec3.dot;
const cross = Vec3.cross;
const approxEq = math_utils.approxEq;

/// The vertical view angle (vertical field of view) in degrees. Treat as **immutable**.
_vertical_fov: Float,
/// The distance from the camera position to the plane of perfect focus.\
/// In this implementation, this is equal to the *focal length*, which is the distance from the camera position to the viewport center\
/// Treat as **immutable**.
_focus_distance: Float,
/// Variation angle of rays through each pixel, expressed in **degrees**. Treat as **immutable**.
_defocus_angle: Float,
/// Defocus disk horizontal radius. Treat as **immutable**.
_defocus_disk_u: Vec3,
/// Defocus disk vertical radius. Treat as **immutable**.
_defocus_disk_v: Vec3,
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

pub fn init(pos: Vec3, up: Vec3, right: Vec3, focus_distance: Float, defocus_angle: Float, vertical_fov: Float, render_settings: RenderSettings) Camera {
    // Determine the camera orientation
    const unit_up = if (up.isNormalized()) up else normalized(up);
    const unit_right = if (right.isNormalized()) right else normalized(right);
    const unit_forward = cross(unit_right, unit_up);

    // Finish initialization
    return viewportSetup(pos, unit_up, unit_right, unit_forward, focus_distance, defocus_angle, vertical_fov, render_settings);
}

pub fn initLookAt (from: Vec3, to: Vec3, vertical_fov: Float, focus_distance: Float, defocus_angle: Float, render_settings: RenderSettings) Camera {
    // Determine the camera orientation
    const unit_forward = normalized(sub(from, to));

    var randVec = Vec3.init(0.0, 1.0, 0.0);
    if (approxEq(Float, 1.0, @abs(dot(randVec, unit_forward)))) {
        // If @abs(a.dot(b)) == 1.0, a and b are parallel and their cross product will be a zero-vector.
        // In this case, change randVec to be z-aligned.
        randVec = Vec3.init(0.0, 0.0, 1.0);
    }

    const unit_right = cross(randVec, unit_forward);
    const unit_up = cross(unit_forward, unit_right);

    // Finish initialization
    return viewportSetup(from, unit_up, unit_right, unit_forward, focus_distance, defocus_angle, vertical_fov, render_settings);
}

/// Construct a camera ray originating from the defocus disk and directed at a randomly sampled point around the pixel location x_screen, y_screen
pub fn getRay(self: Camera, rand: std.Random, x_screen: usize, y_screen: usize, sample_center: bool) Ray {
    const offset: Vec3 = if (sample_center) .init(0.0, 0.0, 0.0) else sample_unit_square(rand);

    const pixel_sample = self._pixel_top_left.
                add(self._pixel_delta_u.scalarMul(@as(Float, @floatFromInt(x_screen)) + offset.x)).
                add(self._pixel_delta_v.scalarMul(@as(Float, @floatFromInt(y_screen)) + offset.y));

    const ray_origin = if (self._defocus_angle <= 0.0) self._pos else self.defocus_disk_sample(rand);
    return .{
        .origin = ray_origin,
        .dir = pixel_sample.sub(ray_origin),
    };
}

fn defocus_disk_sample(self: Camera, rand: std.Random) Vec3 {
    const p = Vec3.randomInUnitDisk(rand);
    return self._pos.add(self._defocus_disk_u.scalarMul(p.x)).add(self._defocus_disk_v.scalarMul(p.y));
}

fn sample_unit_square(prng: std.Random) Vec3 {
    return .init(prng.float(Float) - 0.5, prng.float(Float) - 0.5, 0.0);
}

fn viewportSetup(pos: Vec3, unit_up: Vec3, unit_right: Vec3, unit_forward: Vec3, focus_distance: Float, defocus_angle: Float, vertical_fov: Float, render_settings: RenderSettings) Camera {
    const theta: Float = std.math.degreesToRadians(vertical_fov);
    const viewport_height = 2.0 * focus_distance * @tan(theta / 2.0);
    const viewport_width = viewport_height * render_settings.getAspectRatio();

    // Calculate the horizontal and vertical delta vectors from pixel to pixel
    const pixel_delta_u = unit_right.scalarMul(viewport_width / @as(f32, @floatFromInt(render_settings.image_width)));
    const pixel_delta_v = unit_up.scalarMul(-viewport_height / @as(f32, @floatFromInt(render_settings.image_height))); // The viewport's v-axis direction is -camera_up

    // See the Camera docs to understand why the following is a subtraction and not an addition (it has to do with the camera's forward direction)
    const viewport_center = pos.sub(unit_forward.scalarMul(focus_distance));

    // Calculate the location of the upper left pixel
    const viewport_top_left = viewport_center.
        sub(unit_right.scalarMul(viewport_width / 2)).
        add(unit_up.scalarMul(viewport_height / 2));
    const pixel_top_left = viewport_top_left.add((pixel_delta_u.add(pixel_delta_v)).scalarDiv(2.0));

    const defocus_radius = focus_distance * @tan(std.math.degreesToRadians(defocus_angle / 2.0));
    const defocus_disk_u = unit_right.scalarMul(defocus_radius);
    const defocus_disk_v = unit_up.scalarMul(defocus_radius);

    return Camera {
        ._vertical_fov = vertical_fov,
        ._focus_distance = focus_distance,
        ._defocus_angle = defocus_angle,
        ._defocus_disk_u = defocus_disk_u,
        ._defocus_disk_v = defocus_disk_v,
        ._pos = pos,
        ._up = unit_up,
        ._right = unit_right,
        ._forward = unit_forward,
        ._viewport_center = viewport_center,
        ._pixel_delta_u = pixel_delta_u,
        ._pixel_delta_v = pixel_delta_v,
        ._pixel_top_left = pixel_top_left
    };
}

const pi = std.math.pi;
const abs_eps = 2 * std.math.floatEps(Float);
const rel_eps = @sqrt(std.math.floatEps(Float));

test "init" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    const pos = Vec3.init(0.0, 0.0, 0.0);
    var up = Vec3.init(0.0, 1.0, 0.0);
    var right = Vec3.init(1.0, 0.0, 0.0);
    var camera = init(pos, up, right, 10.0, 0.0, 90.0, rs);

    try std.testing.expectApproxEqRel(10.0, camera._focus_distance, rel_eps);
    try std.testing.expectApproxEqAbs(0.0, camera._defocus_angle, abs_eps);
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(0.0, 0.0, 1.0)));

    up = Vec3.init(0.0, std.math.sqrt1_2, std.math.sqrt1_2);
    camera = init(pos, up, right, std.math.floatMax(Float) / 2.0, 0.0, 90.0, rs);
    try std.testing.expectApproxEqRel(std.math.floatMax(Float) / 2.0, camera._focus_distance, rel_eps);
    try std.testing.expectApproxEqAbs(0.0, camera._defocus_angle, abs_eps);
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(0.0, -std.math.sqrt1_2, std.math.sqrt1_2)));

    up = Vec3.init(0.0, 1.0, 0.0);
    right = Vec3.init(std.math.sqrt1_2, 0.0, std.math.sqrt1_2);
    camera = init(pos, up, right, std.math.floatMax(Float) / 2.0, 0.0, 90.0, rs);
    try std.testing.expectApproxEqRel(std.math.floatMax(Float) / 2.0, camera._focus_distance, rel_eps);
    try std.testing.expectApproxEqRel(90.0, camera._vertical_fov, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(-std.math.sqrt1_2, 0.0, std.math.sqrt1_2)));
}

test "initLookAt" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    const pos = Vec3.init(0.0, 0.0, 0.0);
    var to = Vec3.init(0.0, 0.0, -50.0);
    var camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);

    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expectApproxEqAbs(0.0, camera._defocus_angle, abs_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .init(0.0, 1.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .init(1.0, 0.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(0.0, 0.0, 1.0)));

    to = Vec3.init(@cos(pi / 4.0), 0, @sin(pi / 4.0));
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, .init(0.0, 0.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .init(0.0, 1.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .init(-std.math.sqrt1_2, 0.0, std.math.sqrt1_2)));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(-std.math.sqrt1_2, 0.0, -std.math.sqrt1_2)));

    to = Vec3.init(0.0, 1.0, -50.0);
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(!Vec3.isApproxEq(camera._up, .init(0.0, 1.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .init(1.0, 0.0, 0.0)));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .init(0.0, 0.0, 1.0)));

    to = Vec3.init(1.0, 0.0, -50.0);
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .init(0.0, 1.0, 0.0)));
    try std.testing.expect(!Vec3.isApproxEq(camera._right, .init(1.0, 0.0, 0.0)));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .init(0.0, 0.0, 1.0)));

    to = Vec3.init(0.0, 20.0, 0.0);
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .init(0.0, 0.0, 1.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .init(1.0, 0.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(0.0, -1.0, 0.0)));

    to = Vec3.init(0.0, -20.0, 0.0);
    camera = initLookAt(pos, to, 90.0, Vec3.distance(pos, to), 0.0, rs);
    try std.testing.expectApproxEqRel(Vec3.distance(pos, to), camera._focus_distance, rel_eps);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .init(0.0, 0.0, 1.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .init(-1.0, 0.0, 0.0)));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .init(0.0, 1.0, 0.0)));
}

test "viewportSetup" {
    const rs = RenderSettings{ .image_width = 800, .image_height = 400, .ray_t_range = .{ .min = 0.0, .max = 100.0 }, .samples_per_pixel = 1, .pixel_samples_scale = 1.0, .max_ray_bounces = 10 };
    const pos = Vec3.init(0.0, 0.0, 0.0);
    const to = Vec3.init(0.0, 0.0, -10.0);
    const fov: Float = 90.0;
    const defocus_angle: Float = 10.0;
    const focus_distance: Float = 10.0;
    const camera = initLookAt(pos, to, fov, focus_distance, defocus_angle, rs);

    // Verify orthogonality
    try std.testing.expectApproxEqAbs(0.0, dot(camera._right, camera._up), abs_eps);
    try std.testing.expectApproxEqAbs(0.0, dot(camera._right, camera._forward), abs_eps);
    try std.testing.expectApproxEqAbs(0.0, dot(camera._up, camera._forward), abs_eps);

    const h = 2.0 * camera._focus_distance * @tan(std.math.degreesToRadians(fov) / 2.0);
    try std.testing.expectApproxEqRel(20.0, h, rel_eps);
    const w = h * rs.getAspectRatio();
    try std.testing.expectApproxEqRel(40.0, w, rel_eps);

    try std.testing.expectApproxEqRel(w / 800.0, camera._pixel_delta_u.magnitude(), rel_eps);
    try std.testing.expectApproxEqRel(h / 400.0, camera._pixel_delta_v.magnitude(), rel_eps);

    const defocus_radius = focus_distance * @tan(std.math.degreesToRadians(defocus_angle / 2.0));
    try std.testing.expectApproxEqRel(defocus_radius, camera._defocus_disk_u.magnitude(), rel_eps);
    try std.testing.expectApproxEqRel(defocus_radius, camera._defocus_disk_v.magnitude(), rel_eps);
}
