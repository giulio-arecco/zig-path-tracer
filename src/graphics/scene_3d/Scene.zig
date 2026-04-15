const Scene = @This();

const std = @import("std");
const Vec3 = @import("../../Vec3.zig");
const Camera = @import("Camera.zig");
const math_utils = @import("../../math_utils.zig");
const approxEq = math_utils.approxEq;
const evaluateDiscriminant = math_utils.evaluateDiscriminant;

const dot = Vec3.dot;

pub const Sphere = struct {
    center: Vec3,
    radius: f32
};

camera: Camera,
// shapes: []const Sphere, //TODO: Possibly make this dynamically allocated so that it can be interacted with at runtime
sphere: Sphere,
screen_width: u16,
screen_height: u16,


pub fn drawSphere(sceneData: Scene, writer: anytype) !void {
    comptime {
        const WriterType = @TypeOf(writer);

        const ActualType = switch (@typeInfo(WriterType)) {
            .pointer => |ptr_info| ptr_info.child,
            else => WriterType
        };

        switch (@typeInfo(ActualType)) {
            .@"struct" => {
                if (!@hasDecl(ActualType, "write")) {
                    @compileError("The stuct '" ++ @typeName(ActualType) ++ "' does not implement the 'write' method.");
                }
            },
            else => @compileError("Expected a struct or a pointer to struct, received '" ++ @typeName(ActualType) ++ "' instead.")
        }
    }

    const focal_distance = sceneData.camera.focal_distance;
    const camera_pos = sceneData.camera._pos;
    const camera_up = sceneData.camera._up;
    const camera_right = sceneData.camera._right;
    const camera_forward = sceneData.camera._forward;
    const screen_width = sceneData.screen_width;
    const screen_height = sceneData.screen_height;

    // See the Camera docs to understand where the '-' comes from (it has to do with the camera's forward direction)
    const screen_center = camera_pos.add(camera_forward.scalarMul(-focal_distance));
    std.debug.print("Screen Center: {}.\n", .{screen_center});

    const screen_top_left = screen_center.
        sub(camera_right.scalarMul(@floatFromInt(@as(i24, screen_width / 2)))).
        add(camera_up.scalarMul(@floatFromInt(@as(i24, screen_height / 2))));

    std.debug.print("Screen Top Left: {}.\n", .{screen_top_left});

    for (0..screen_height) |y_screen| {
        for (0..screen_width) |x_screen| {
            // Pixel center
            const u = @as(f32, @floatFromInt(x_screen)) + 0.5;
            const v = @as(f32, @floatFromInt(y_screen)) + 0.5;

            const pixel = screen_top_left.add(camera_right.scalarMul(u)).sub(camera_up.scalarMul(v));
            const ray = pixel.sub(camera_pos);
            const dir = ray.normalized();

            if (raySphereIntersection(camera_pos, dir, sceneData.sphere)) {
                try writer.writeInt(u24, 0xFF_FF_FF, .big); // White pixel in PPM P6
            }
            else {
                try writer.writeInt(u24, 0x00_00_00, .big); // Black Pixel in PPM P6
            }
        }
    }

   try writer.flush();
}

/// Parameter `ray_dir` must be normalized.
pub fn raySphereIntersection(camera_pos: Vec3, ray_dir: Vec3, sphere: Sphere) bool {
    // Intersection between a ray and a sphere (implicit eq: (x - x_c)^2 + (y - y_c)^2 + (z - z_c)^2 = r^2, parametric eq: (P - C)^2 - r^2 = 0)\
    const r = sphere.radius;
    const cam_to_sphere = camera_pos.sub(sphere.center);

    // To find the t parameter we must solve a second-grade linear equation with the following parameters:
    const a: f32 = 1.0; // If the ray dir is normalized, otherwise it's equal to: dot(dir, dir);
    const b = dot(ray_dir.scalarMul(2.0), camera_pos.sub(sphere.center));
    const c = dot(cam_to_sphere, cam_to_sphere) - r * r;

    return evaluateDiscriminant(f32, a, b, c);
}
