const Scene = @This();

const std = @import("std");
const geometry = @import("geometry.zig");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");

const Ray = @import("Ray.zig");
const LinearColor = @import("../LinearColor.zig");
const Material = @import("materials.zig").Material;
const HitRecord = geometry.HitRecord;
const Float = config.Float;
const Interval = math_utils.Interval(Float);
const Aabb = geometry.Aabb;
const BvhTree = geometry.BvhTree;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;

/// The scene main camera.
camera: Camera,
/// The collection of all hittable objects in the scene.\
/// Treat as **immutable**.
hittables: ArrayList(Hittable),
/// Owned list of pointers to heap-allocated `Material` instances.
///
/// This collection holds every material used in the scene. Individual primitives
/// may reference the same `Material` (sharing is allowed). The Scene is
/// responsible for freeing the memory referenced by these pointers when it is deinitialized.
///
/// All materials must be allocated with the same allocator
/// provided to the Scene during initialization. Use
/// `Scene.createMaterial` to allocate and register materials so ownership and
/// deallocation are handled correctly.
materials: ArrayList(*const Material),
/// The scene background color.
bg_color: LinearColor,
/// The scene bounding volume hierarchy, initialized as `null` and built on request from the current primitives list.\
/// Treat as **immutable**.
bvh: ?BvhTree,
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

pub fn init(camera: Camera, bg_color: LinearColor, allocator: Allocator) Scene {
    return .{
        .camera = camera,
        .hittables = .empty,
        .materials = .empty,
        .bg_color = bg_color,
        .bvh = null,
        .allocator = allocator
    };
}

pub fn initWithCapacity(camera: Camera, bg_color: LinearColor, allocator: Allocator, capacity: usize) Allocator.Error!Scene {
    return .{
        .camera = camera,
        .hittables = try .initCapacity(allocator, capacity),
        .materials = .empty,
        .bg_color = bg_color,
        .bvh = null,
        .allocator = allocator
    };
}

pub fn deinit(self: *Scene) void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
    }

    for (self.hittables.items) |*hittable| {
        hittable.deinit(self.allocator);
    }
    self.hittables.deinit(self.allocator);

    for(self.materials.items) |mat_ptr| {
        self.allocator.destroy(mat_ptr);
    }
    self.materials.deinit(self.allocator);

    self.* = undefined;
}

/// Invalidates the current scene active BVH (if present). It must be rebuilt if needed.
pub fn add(self: *Scene, surface: Hittable) Allocator.Error!void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
        self.bvh = null;
    }

    try self.hittables.append(self.allocator, surface);
}

pub fn createMaterial(self: *Scene, mat: Material) Allocator.Error!*const Material {
    const mat_ptr = try self.allocator.create(Material);
    mat_ptr.* = mat;
    try self.materials.append(self.allocator, mat_ptr);

    return mat_ptr;
}

pub fn buildBvh(self: *Scene, min_node_size: usize) Allocator.Error!void {
    if (self.bvh) |*bvh| {
        bvh.deinit(self.allocator);
    }

    self.bvh = try .init(self.hittables.items, min_node_size, self.allocator);
}

const testing = std.testing;
const absEps = std.math.floatEps(Float);
const relEps = @sqrt(std.math.floatEps(Float));
const Vec3 = @import("../../Vec3.zig");

test "Scene.init" {
    const bg_color = LinearColor{ .v = .{ 0.5, 0.5, 0.5 } };
    var scene = Scene.init(undefined, bg_color, testing.allocator);
    defer scene.deinit();

    try testing.expectEqual(@as(usize, 0), scene.hittables.items.len);
    try testing.expectEqual(@as(usize, 0), scene.materials.items.len);
    try testing.expectEqual(bg_color.v[0], scene.bg_color.v[0]);
    try testing.expectEqual(bg_color.v[1], scene.bg_color.v[1]);
    try testing.expectEqual(bg_color.v[2], scene.bg_color.v[2]);
    try testing.expect(scene.bvh == null);
}

test "Scene.initWithCapacity" {
    const bg_color = LinearColor{ .v = .{ 0.0, 0.0, 0.0 } };
    var scene = try Scene.initWithCapacity(undefined, bg_color, testing.allocator, 10);
    defer scene.deinit();

    try testing.expect(scene.hittables.capacity >= 10);
    try testing.expectEqual(@as(usize, 0), scene.hittables.items.len);
}

test "Scene.createMaterial" {
    var scene = Scene.init(undefined, LinearColor{ .v = .{ 0.0, 0.0, 0.0 } }, testing.allocator);
    defer scene.deinit();

    const mat = Material{ .lambertian = .{ .albedo = LinearColor{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const mat_ptr = try scene.createMaterial(mat);

    try testing.expectEqual(@as(usize, 1), scene.materials.items.len);
    try testing.expectEqual(mat_ptr, scene.materials.items[0]);
}

test "Scene.add and Scene.buildBvh" {
    var scene = Scene.init(undefined, LinearColor{ .v = .{ 0.0, 0.0, 0.0 } }, testing.allocator);
    defer scene.deinit();

    const mat_ptr = try scene.createMaterial(Material{ .lambertian = .{ .albedo = LinearColor{ .v = .{ 0.5, 0.5, 0.5 } } } });

    // Add first element
    const sphere1 = geometry.Sphere.init(Vec3.init(1.0, 1.0, -5.0), 1.0, mat_ptr);
    try scene.add(Hittable{ .sphere = sphere1 });
    try testing.expectEqual(@as(usize, 1), scene.hittables.items.len);

    // Build BVH
    try scene.buildBvh(1);
    try testing.expect(scene.bvh != null);

    // Add second element. Adding to the scene invalidates the BVH.
    const sphere2 = geometry.Sphere.init(Vec3.init(-1.0, -1.0, -5.0), 1.0, mat_ptr);
    try scene.add(Hittable{ .sphere = sphere2 });
    try testing.expectEqual(@as(usize, 2), scene.hittables.items.len);
    try testing.expect(scene.bvh == null);
}

test "Scene.hit without BVH" {
    var scene = Scene.init(undefined, LinearColor{ .v = .{ 0.0, 0.0, 0.0 } }, testing.allocator);
    defer scene.deinit();

    const mat_ptr = try scene.createMaterial(Material{ .lambertian = .{ .albedo = LinearColor{ .v = .{ 0.5, 0.5, 0.5 } } } });
    const sphere = geometry.Sphere.init(Vec3.init(0.0, 0.0, -5.0), 1.0, mat_ptr);
    try scene.add(Hittable{ .sphere = sphere });

    const ray = Ray{ .origin = .init(0.0, 0.0, 0.0), .dir = .init(0.0, 0.0, -1.0) };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const is_hit = scene.hit(ray, ray_t_range, &h);

    try testing.expect(is_hit);
    if (is_hit) {
        try testing.expectApproxEqRel(@as(Float, 4.0), h.t, relEps);
    }
}

test "Scene.hit with BVH" {
    var scene = Scene.init(undefined, LinearColor{ .v = .{ 0.0, 0.0, 0.0 } }, testing.allocator);
    defer scene.deinit();

    const mat_ptr = try scene.createMaterial(Material{ .lambertian = .{ .albedo = LinearColor{ .v = .{ 0.5, 0.5, 0.5 } } } });
    const sphere = geometry.Sphere.init(Vec3.init(0.0, 0.0, -5.0), 1.0, mat_ptr);
    try scene.add(Hittable{ .sphere = sphere });

    try scene.buildBvh(1);

    const ray = Ray{ .origin = .init(0.0, 0.0, 0.0), .dir = .init(0.0, 0.0, -1.0) };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const is_hit = scene.hit(ray, ray_t_range, &h);

    try testing.expect(is_hit);
    if (is_hit) {
        try testing.expectApproxEqRel(@as(Float, 4.0), h.t, relEps);
    }
}

test "Scene.hit with empty scene" {
    var scene = Scene.init(undefined, LinearColor{ .v = .{ 0.0, 0.0, 0.0 } }, testing.allocator);
    defer scene.deinit();

    const ray = Ray{ .origin = .init(0.0, 0.0, 0.0), .dir = .init(0.0, 0.0, -1.0) };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const is_hit = scene.hit(ray, ray_t_range, &h);
    try testing.expect(!is_hit);
}
