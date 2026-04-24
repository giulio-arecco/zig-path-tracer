const Scene = @This();

const std = @import("std");
const rendering = @import("rendering.zig");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");
const geometry = @import("geometry.zig");

const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const Camera = @import("Camera.zig");
const Color = @import("../Color.zig");
const Gradient = Color.Gradient;
const HitRecord = geometry.HitRecord;
const Sphere = geometry.Sphere;
const Hittable = geometry.Hittable;
const RenderSettings = rendering.RenderSettings;
const Float = config.Float;

const approxEq = math_utils.approxEq;
const dot = Vec3.dot;

camera: Camera,
// hittables: []const Hittable, //TODO: Possibly make this dynamically allocated so that it can be interacted with at runtime
hittable: Hittable,

pub fn drawSphere(scene: Scene, settings: RenderSettings, writer: anytype) !void {
    comptime assertHasWriteInt(@TypeOf(writer));

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
                .dir = pixel.sub(camera._pos),
            };

            const hit = scene.hittable.hit(ray, 0.0, std.math.inf(Float));
            const pixel_color = ray_color(ray, hit);
            try writer.writeInt(u24, pixel_color.toPacked(), .big); // White pixel in PPM P6
        }
    }

   try writer.flush();
}

fn ray_color(ray: Ray, hit: ?HitRecord) Color {
    if (hit) |record| {
        return Color.fromFloats(Float, record.normal.x, record.normal.y, record.normal.z, -1.0, 1.0);
    }

    const grad = Gradient(Float) {
        .start_color = .{ .r = 255, .g = 255, .b = 255 },
        .end_color = .{ .r = 128, .g = 180, .b = 255 }
    };

    const norm_dir = ray.dir.normalized();
    return grad.at(0.5 * (norm_dir.y + 1.0));
}

fn assertHasWriteInt(WriterType: type) void {
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
