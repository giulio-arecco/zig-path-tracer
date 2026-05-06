const Scene = @This();

const std = @import("std");
const geometry = @import("geometry.zig");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");

const Ray = @import("Ray.zig");
const HitRecord = geometry.HitRecord;
const Float = config.Float;
const Interval = math_utils.Interval(Float);
const AABB = geometry.AABB;

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;

/// The scene main camera.\
/// Treat as **immutable**.
camera: Camera,
/// The collection of all hittable objects in scene.\
/// Treat as **immutable**.
hittables: std.ArrayList(Hittable),
/// The bounding box containing all the hittable objects in the scene. It is `null` if the scene is empty.\
/// Treat as **immutable**.
bbox: ?AABB,
/// The scene underlying allocator, used to dynamically update the scene content.\
/// Treat as **immutable**.
allocator: std.mem.Allocator,

pub fn hit(self: Scene, ray: Ray, ray_t_range: Interval) ?HitRecord {
    var closest_t = ray_t_range.max;
    var closest_hit: ?HitRecord = null;

    for (self.hittables.items) |hittable| {
        const h = hittable.hit(ray, .{ .min = ray_t_range.min, .max = closest_t });
        if (h) |record| {
            closest_t = record.t;
            closest_hit = record;
        }
    }

    return closest_hit;
}

pub fn init(camera: Camera, allocator: std.mem.Allocator) Scene {
    return .{
        .camera = camera,
        .hittables = .empty,
        .bbox = null,
        .allocator = allocator
    };
}

pub fn initWithCapacity(camera: Camera, allocator: std.mem.Allocator, capacity: usize) !Scene {
    return .{
        .camera = camera,
        .hittables = try .initCapacity(allocator, capacity),
        .bbox = null,
        .allocator = allocator
    };
}

pub fn deinit(self: *Scene) void {
    self.hittables.deinit(self.allocator);
}

pub fn add(self: *Scene, surface: Hittable) !void {
    try self.hittables.append(self.allocator, surface);
    self.bbox = if (self.bbox == null) surface.bbox() else .initMergeTwo(self.bbox.?, surface.bbox());
}
