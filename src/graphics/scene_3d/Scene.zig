const Scene = @This();

const std = @import("std");
const geometry = @import("geometry.zig");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");

const Ray = @import("Ray.zig");
const HitRecord = geometry.HitRecord;
const Float = config.Float;
const Interval = math_utils.Interval(Float);
const Aabb = geometry.Aabb;
const BvhTree = geometry.BvhTree;
const Allocator = std.mem.Allocator;

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;

/// The scene main camera.\
/// Treat as **immutable**.
camera: Camera,
/// The collection of all hittable objects in scene.\
/// Treat as **immutable**.
hittables: std.ArrayList(Hittable),
/// The scene bounding volume hierarchy, initialized as `null` and built on request from the current primitives list.\
/// Treat as **immutable**.
bvh: ?BvhTree,
// The bounding box containing all the hittable objects in the scene. It is `null` if the scene is empty.\
// Treat as **immutable**.
// bbox: ?AABB,
/// The scene underlying allocator, used to dynamically update the scene content.\
/// Treat as **immutable**.
allocator: Allocator,

pub fn hit(self: *const Scene, ray: Ray, ray_t_range: Interval, hit_record: *HitRecord) bool {
    // Use the BVH if available
    if (self.bvh) |*bvh| {
        return bvh.hit(self.hittables.items, ray, ray_t_range, hit_record);
    }

    // Otherwise fallback to the primitives list
    var current_t_range = ray_t_range;
    var hit_anything = false;

    for (self.hittables.items) |*hittable| {
        if (hittable.hit(ray, current_t_range, hit_record)) {
            current_t_range.max = hit_record.t;
            hit_anything = true;
        }
    }

    return hit_anything;
}

pub fn init(camera: Camera, allocator: Allocator) Scene {
    return .{
        .camera = camera,
        .hittables = .empty,
        .bvh = null,
        // .bbox = null,
        .allocator = allocator
    };
}

pub fn initWithCapacity(camera: Camera, allocator: Allocator, capacity: usize) Allocator.Error!Scene {
    return .{
        .camera = camera,
        .hittables = try .initCapacity(allocator, capacity),
        .bvh = null,
        // .bbox = null,
        .allocator = allocator
    };
}

pub fn deinit(self: *Scene) void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
    }

    self.hittables.deinit(self.allocator);
}

/// Invalidates the current scene active BVH (if present). It must be rebuilt if needed.
pub fn add(self: *Scene, surface: Hittable) Allocator.Error!void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
        self.bvh = null;
    }

    try self.hittables.append(self.allocator, surface);
    // self.bbox = if (self.bbox == null) surface.bbox() else .initMergeTwo(self.bbox.?, surface.bbox());
}

pub fn buildBvh(self: *Scene, min_node_size: usize) Allocator.Error!void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
    }

    self.bvh = try .init(self.hittables.items, min_node_size, self.allocator);
}
