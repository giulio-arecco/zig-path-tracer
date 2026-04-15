//! A camera in 3D space.
//!
//! The camera coordinate system is right-handed, so the *forward* vector
//! points towards the camera and is computed as the cross product between
//! the *right* and the *up* vectors.
//!
//! **WARNING**: The mathematical invariants of this struct are managed internally.
//! Fields such as `_pos`, `_up`, `_right` and `_forward` should be treated as read-only
//! by external users. To mutate the camera's orientation, use the provided
//! methods instead of modifying the fields directly.
const Camera = @This();

const std = @import("std");
const Vec3 = @import("../../Vec3.zig");
const normalized = Vec3.normalized;
const sub = Vec3.sub;
const cross = Vec3.cross;

/// The position of the camera. Treat as **immutable**.
_pos: Vec3,
/// The camera's up vector. Treat as **immutable**.
_up: Vec3,
/// The camera's right vector. Treat as **immutable**.
_right: Vec3,
/// The camera's forward vector. Treat as **immutable**.
_forward: Vec3,

pub fn init(pos: Vec3, up: Vec3, right: Vec3) !Camera {
    const norm_up = try normalized(up);
    const norm_right = try normalized(right);

    return Camera {
        ._pos = pos,
        ._up = norm_up,
        ._right = norm_right,
        ._forward = cross(norm_right, norm_up),
    };
}

pub fn initLookAt (from: Vec3, to: Vec3) !Camera {
    const forward = try normalized(sub(from, to));
    const right = cross(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, forward);
    const up = cross(forward, right);

    return Camera {
        ._pos = from,
        ._up = up,
        ._right = right,
        ._forward = forward
    };
}

pub fn lookAt(self: *Camera, to: Vec3) !void {
    self._forward = try normalized(sub(self._pos, to));
    self._right = cross(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, self._forward);
    self._up = cross(self._forward, self._right);
}

//TODO Complete tests and make them exhaustive

const pi = std.math.pi;

test "init" {
    const pos = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };
    var up = Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 };
    var right = Vec3 { .x = 1.0, .y = 0.0, .z = 0.0 };
    var camera = try init(pos, up, right);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    up = Vec3 { .x = 0.0, .y = std.math.sqrt1_2, .z = std.math.sqrt1_2 };
    camera = try init(pos, up, right);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = -std.math.sqrt1_2, .z = std.math.sqrt1_2 }));

    up = Vec3 { .x = 0.0, .y = 1.0, .z = 0.0 };
    right = Vec3 { .x = std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 };
    camera = try init(pos, up, right);
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, up));
    try std.testing.expect(Vec3.isApproxEq(camera._right, right));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 }));
}

test "initLookAt" {
    const pos = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };
    var camera = try initLookAt(pos, .{ .x = 0.0, .y = 0.0, .z = -50.0 });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    camera = try initLookAt(pos, .{ .x = @cos(pi/4.0), .y = 0, .z = @sin(pi/4.0) });

    try std.testing.expect(Vec3.isApproxEq(camera._pos, .{ .x = 0.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = -std.math.sqrt1_2 }));

    camera = try initLookAt(pos, .{ .x = 0.0, .y = 1.0, .z = -50.0 });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(!Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    camera = try initLookAt(pos, .{ .x = 1.0, .y = 0.0, .z = -50.0 });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, pos));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));
}

test "lookAt" {
    var camera = Camera {
        ._pos = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        ._up = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        ._right = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        ._forward = .{ .x = 0.0, .y = 0.0, .z = 1.0 }
    };

    try camera.lookAt(.{ .x = @cos(pi/4.0), .y = 0, .z = @sin(pi/4.0) });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, .{ .x = 0.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = std.math.sqrt1_2 }));
    try std.testing.expect(Vec3.isApproxEq(camera._forward, .{ .x = -std.math.sqrt1_2, .y = 0.0, .z = -std.math.sqrt1_2 }));

    try camera.lookAt(.{ .x = 0.0, .y = 1.0, .z = -50.0 });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, .{ .x = 0.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));

    try camera.lookAt(.{ .x = 1.0, .y = 0.0, .z = -50.0 });
    try std.testing.expect(Vec3.isApproxEq(camera._pos, .{ .x = 0.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(Vec3.isApproxEq(camera._up, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._right, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expect(!Vec3.isApproxEq(camera._forward, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));
}
