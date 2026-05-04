const Scene = @This();

const std = @import("std");
const geometry = @import("geometry.zig");
const config = @import("../../config.zig");

const Ray = @import("Ray.zig");
const HitRecord = geometry.HitRecord;
const Float = config.Float;

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;


camera: Camera,
hittables: std.ArrayList(Hittable),
allocator: std.mem.Allocator,

pub fn hit(self: Scene, ray: Ray, ray_tmin: Float, ray_tmax: Float) ?HitRecord {
    var closest_t = ray_tmax;
    var closest_hit: ?HitRecord = null;

    for (self.hittables.items) |hittable| {
        const h = hittable.hit(ray, ray_tmin, closest_t);
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
        .allocator = allocator
    };
}

pub fn initWithCapacity(camera: Camera, allocator: std.mem.Allocator, capacity: usize) !Scene {
    return .{
        .camera = camera,
        .hittables = try .initCapacity(allocator, capacity),
        .allocator = allocator
    };
}

pub fn deinit(self: *Scene) void {
    self.hittables.deinit(self.allocator);
}

pub fn add(self: *Scene, surface: Hittable) !void {
    try self.hittables.append(self.allocator, surface);
}
