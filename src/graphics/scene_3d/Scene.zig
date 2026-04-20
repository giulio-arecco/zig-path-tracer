const Scene = @This();

const std = @import("std");
const rendering = @import("rendering.zig");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const Camera = @import("Camera.zig");
const RenderSettings = rendering.RenderSettings;
const Float = config.Float;

const approxEq = math_utils.approxEq;
const evaluateDiscriminant = math_utils.evaluateDiscriminant;
const dot = Vec3.dot;

pub const Sphere = struct {
    center: Vec3,
    radius: Float
};

camera: Camera,
// shapes: []const Sphere, //TODO: Possibly make this dynamically allocated so that it can be interacted with at runtime
sphere: Sphere,

pub fn drawSphere(scene: Scene, settings: RenderSettings, writer: anytype) !void {
    comptime {
        const WriterType = @TypeOf(writer);

        const ActualType = switch (@typeInfo(WriterType)) {
            .pointer => |ptr_info| ptr_info.child,
            else => WriterType
        };

        switch (@typeInfo(ActualType)) {
            .@"struct" => {
                if (!@hasDecl(ActualType, "writeInt")) {
                    @compileError("The stuct '" ++ @typeName(ActualType) ++ "' does not implement the 'write' method.");
                }
            },
            else => @compileError("Expected a struct or a pointer to struct, received '" ++ @typeName(ActualType) ++ "' instead.")
        }
    }

    const camera = scene.camera;
    const image_width = settings.image_width;
    const image_height = settings.image_height;

    std.debug.print("Viewport Center: {}.\n", .{camera._viewport_center});
    std.debug.print("First pixel position: {}\n", .{camera._pixel_top_left});

    for (0..image_height) |y_screen| {
        for (0..image_width) |x_screen| {
            const pixel = camera._pixel_top_left.
                add(camera._pixel_delta_u.scalarMul(@floatFromInt(x_screen))).
                add(camera._pixel_delta_v.scalarMul(@floatFromInt(y_screen)));

            const ray = Ray {
                .origin = camera._pos,
                .dir = pixel.sub(camera._pos).normalized(),
            };

            if (raySphereIntersection(ray, scene.sphere)) {
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
pub fn raySphereIntersection(ray: Ray, sphere: Sphere) bool {
    std.debug.assert(ray.dir.isNormalized());

    // Intersection between a ray and a sphere (implicit eq: (x - x_c)^2 + (y - y_c)^2 + (z - z_c)^2 = r^2, parametric eq: (P - C)^2 - r^2 = 0)\
    const r = sphere.radius;
    const eye_to_sphere = ray.origin.sub(sphere.center);

    // To find the t parameter we must solve a second-grade linear equation with the following parameters:
    const a: Float = 1.0; // If the ray dir is normalized, otherwise it's equal to: dot(dir, dir);
    const b = dot(ray.dir.scalarMul(2.0), ray.origin.sub(sphere.center));
    const c = dot(eye_to_sphere, eye_to_sphere) - r * r;

    return evaluateDiscriminant(Float, a, b, c);
}
