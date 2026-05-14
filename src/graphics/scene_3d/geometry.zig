const std = @import("std");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");
const testing = std.testing;

const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const Float = config.Float;
const Material = @import("materials.zig").Material;
const IntervalFloat = math_utils.Interval(Float);
const IntervalUsize = math_utils.Interval(usize);
const LinearColor = @import("../LinearColor.zig");
const Allocator = std.mem.Allocator;

const dot = Vec3.dot;
const cross = Vec3.cross;
const evaluateDiscriminantReduced = math_utils.evaluateDiscriminantReduced;


pub const Sphere = struct {
    /// The sphere center.\
    /// Treat as **immutable**.
    center: Vec3,
    /// The sphere radius.\
    /// Treat as **immutable**.
    radius: Float,
    /// The sphere material.\
    /// Treat as **immutable**.
    material: Material,
    /// The sphere axis-aligned bounding box.\
    /// Treat as **immutable**.
    bbox: Aabb,

    pub fn init(center: Vec3, radius: Float, mat: Material) Sphere {
        const radius_vec = Vec3 { .x = radius, .y = radius, .z = radius };
        const bbox = Aabb.initFromPoints(center.sub(radius_vec), center.add(radius_vec));

        return .{
            .center = center,
            .radius = radius,
            .material = mat,
            .bbox = bbox
        };
    }

    pub fn hit(self: Sphere, ray: Ray, ray_t_range: IntervalFloat, hit_record: *HitRecord) bool {
        // Intersection between a ray and a sphere (implicit eq: (x - x_c)^2 + (y - y_c)^2 + (z - z_c)^2 = r^2, parametric eq: (P - C)^2 - r^2 = 0)\
        const eye_to_center = self.center.sub(ray.origin);

        // To find the t parameter we must solve a second-grade linear equation with the following coefficients:
        const a = ray.dir.squaredMagnitude();
        // h == -b/2, where b = dot(ray.dir, eye_to_center) * (-2.0)
        const h = dot(ray.dir, eye_to_center);
        const c = eye_to_center.squaredMagnitude() - self.radius * self.radius;

        const n_sols, const discr = evaluateDiscriminantReduced(Float, a, h, c);
        if (n_sols == 0) {
            return false;
        }

        const discr_sqrt = if (discr == 0.0) 0.0 else @sqrt(discr);

        // Find the nearest root that lies in the acceptable range
        var root = (h - discr_sqrt) / a; // Remember, we use h and not -h in the reduced formula because it's defined as -b/2.0, so b = -2.0*h
        if (!ray_t_range.contains(root)) {
            root = (h + discr_sqrt) / a;
            if (!ray_t_range.contains(root)) {
                return false;
            }
        }

        const point = ray.at(root);
        const outward_normal = (point.sub(self.center)).normalized();

        const front_face, const normal = HitRecord.determineNormalOrientation(ray, outward_normal);

        hit_record.* = .{
            .t = root,
            .point = point,
            .normal = normal,
            .material = self.material,
            .front_face = front_face
        };
        return true;
    }
};

pub const Quad = struct {
    /// The quad starting corner.\
    /// Treat as **immutable**
    q: Vec3,
    /// The quad first side. Q + u gives one of the two corners adjecent to Q.\
    /// Treat as **immutable**.
    u: Vec3,
    /// The quad second side. Q + v gives one of the two corners adjecent to Q.\
    /// Treat as **immutable**.
    v: Vec3,
    /// A constant vector for the given quad, useful for constructing a *coordinate frame* for the plane
    /// containing the quad to find the ray-quad intersection point planar coordinates.\
    /// It's equal to **n** / (**n** ⋅ **n**), where **n** is the quad normal vector (before normalization).\
    /// Treat as **immutable**,
    w: Vec3,
    /// The quad unit normal vector, computed as the cross product between u and v (u x v).\
    /// Treat as **immutable**.
    normal: Vec3,
    /// The `D` term in the implicit formula for the plane containing the quad: Ax + By + Cz + D = 0.\
    /// Treat as **immutable**.
    d: Float,
    /// The quad material.\
    /// Treat as **immutable**.
    material: Material,
    /// The quad axis-aligned bounding box.\
    /// Treat as **immutable**.
    bbox: Aabb,

    pub fn init(q: Vec3, u: Vec3, v: Vec3, mat: Material) Quad {
        const box0 = Aabb.initFromPoints(q, q.add(u).add(v));
        const box1 = Aabb.initFromPoints(q.add(u), q.add(v));
        const aabb = Aabb.initMergeTwo(box0, box1);

        const n = cross(u, v);
        const normal = n.normalized();
        const d = dot(normal, q);
        const w = n.scalarDiv(n.squaredMagnitude());

        return .{
            .q = q,
            .u = u,
            .v = v,
            .w = w,
            .normal = normal,
            .d = d,
            .material = mat,
            .bbox = aabb
        };
    }

    pub fn hit(self: Quad, ray: Ray, ray_t_range: IntervalFloat, hit_record: *HitRecord) bool {
        const denom = dot(self.normal, ray.dir);
        if (@abs(denom) < std.math.floatEps(Float)) {
            // The ray is parallel to the quad
            return false;
        }

        // Ray-plane intersection
        const t = (self.d - dot(self.normal, ray.origin)) / denom;
        if (!ray_t_range.contains(t)) {
            return false;
        }

        const point = ray.at(t);

        const planar_hit_vec = point.sub(self.q);
        const alpha = dot(self.w, cross(planar_hit_vec, self.v));
        const beta = dot(self.w, cross(self.u, planar_hit_vec));
        const unit_interval = IntervalFloat {.min = 0.0, .max = 1.0 };
        // Check if the ray-plane intersection point lies inside the quad
        if (!unit_interval.contains(alpha) or !unit_interval.contains(beta)) {
            return false;
        }

        const front_face, const normal = HitRecord.determineNormalOrientation(ray, self.normal);

        hit_record.* = .{
            .t = t,
            .point = point,
            .normal = normal,
            .material = self.material,
            .front_face = front_face
        };
        return true;
    }
};

pub const HitRecord = struct {
    t: Float,
    point: Vec3,
    normal: Vec3,
    material: Material,
    front_face: bool,

    /// Determines a normal vector orientation. The resulting normal will always point against the ray.\
    /// The first tuple field indicates whether the ray hit the outside of the surface (front face, `true`) or the inside of the surface (back face, `false`).\
    /// The second tuple field contains the oriented normal.\
    /// **NOTE**: The parameter `outward_normal` is assumed to be normalized.
    pub fn determineNormalOrientation(ray: Ray, outward_normal: Vec3) struct { bool, Vec3 } {
        std.debug.assert(outward_normal.isNormalized());

        const front_face = dot(ray.dir, outward_normal) < 0.0;
        const normal = if (front_face) outward_normal else outward_normal.negated();

        return .{ front_face, normal };
    }
};

pub const Hittable = union(enum) {
    sphere: Sphere,
    quad: Quad,

    pub fn hit(self: Hittable, ray: Ray, ray_t_range: IntervalFloat, hit_record: *HitRecord) bool {
        switch (self) {
            inline else => |hittable| return hittable.hit(ray, ray_t_range, hit_record)
        }
    }

    pub fn bbox(self: Hittable) Aabb {
        switch (self) {
            inline else => |hittable| return hittable.bbox
        }
    }
};

pub const Aabb = struct {
    /// The axis-aligned bounding box x interval.\
    /// Treat as **immutable**.
    x: IntervalFloat,
    /// The axis-aligned bounding box y interval.\
    /// Treat as **immutable**.
    y: IntervalFloat,
    /// The axis-aligned bounding box z interval.\
    /// Treat as **immutable**.
    z: IntervalFloat,

    pub fn initFromPoints(a: Vec3, b: Vec3) Aabb {
        var box = Aabb {
            .x = if (a.x <= b.x) .{ .min = a.x, .max = b.x } else .{ .min = b.x, .max = a.x },
            .y = if (a.y <= b.y) .{ .min = a.y, .max = b.y } else .{ .min = b.y, .max = a.y },
            .z = if (a.z <= b.z) .{ .min = a.z, .max = b.z } else .{ .min = b.z, .max = a.z },
        };

        box.padToMinimums(0.0001);
        return box;
    }

    pub fn initMergeTwo(box0: Aabb, box1: Aabb) Aabb {
        var box = Aabb {
            .x = IntervalFloat.initEncloseTwo(box0.x, box1.x),
            .y = IntervalFloat.initEncloseTwo(box0.y, box1.y),
            .z = IntervalFloat.initEncloseTwo(box0.z, box1.z)
        };

        box.padToMinimums(0.0001);
        return box;
    }

    /// Returns the index of the longest axis of the bounding box.\
    /// - 0 corresponds to x
    /// - 1 corresponds to y
    /// - 2 correspond to z
    pub fn longest_axis(self: Aabb) u8 {
        const x_size = self.x.size();
        const y_size = self.y.size();
        const z_size = self.z.size();

        if (x_size > y_size) {
            return if (x_size > z_size) 0 else 2;
        }
        else return if (y_size > z_size) 1 else 2;
    }

    pub fn hit(self: Aabb, ray: Ray, ray_t_range: IntervalFloat) ?IntervalFloat {
        var res_t_range = ray_t_range;

        inline for (std.meta.fields(Aabb)) |field| {
            const axis_interval = @field(self, field.name);
            const ray_orig_coord = @field(ray.origin, field.name);
            const ray_dir_coord = @field(ray.dir, field.name);
            const ray_dir_coord_inv = 1.0 / ray_dir_coord;

            var t0 = (axis_interval.min - ray_orig_coord) * ray_dir_coord_inv;
            var t1 = (axis_interval.max - ray_orig_coord) * ray_dir_coord_inv;

            // We use ray_dir_coord_inv < 0.0 to swap t0 and t1 instead of the more intuitive t0 < t1.
            // If the ray is perfectly parallel to an axis, ray_dir_coord is 0.0, making its inverse Infinity.
            // If the ray origin also lies exactly on the AABB boundary, t0 or t1 becomes 0.0 * Infinity = NaN.
            // Swapping based on the inverse direction avoids NaN propagation in conditional branches.
            if (ray_dir_coord_inv < 0.0) {
                const temp = t0;
                t0 = t1;
                t1 = temp;
            }

            // According to IEEE-754, any relational comparison with NaN evaluates to false.
            // This handles edge cases: if t0 or t1 is NaN, the assignments are naturally skipped.
            // The ray interval is effectively unaltered for this axis, delegating the cull check to the other axes.
            if (t0 > res_t_range.min) res_t_range.min = t0;
            if (t1 < res_t_range.max) res_t_range.max = t1;

            if (res_t_range.max <= res_t_range.min) {
                return null;
            }
        }

        return res_t_range;
    }

    /// Adjust the AABB so taht no side is narrower than the passed delta value, if necessary.
    fn padToMinimums(self: *Aabb, delta: Float) void {
        if (self.x.size() < delta) self.x = self.x.expand(delta);
        if (self.y.size() < delta) self.y = self.y.expand(delta);
        if (self.z.size() < delta) self.z = self.z.expand(delta);
    }
};

pub const BvhTree = struct {
    nodes: std.ArrayList(BvhNode),

    // A tagged union would be a more idiomatic way of representing leaf vs internal nodes.
    // We avoid this to grant a size of 32 bytes (2 for the BvhNode u32 fields, 6 for the AABB Interval(f32) fields) for better performance.
    // Of course, this is only true if the Float type declared in config.zig is f32.
    pub const BvhNode = struct {
        /// The number of primitives in this node. It's 0 if the node is internal, > 0 if it's a leaf.\
        /// Treat as **immutable**.
        primitive_count: u32,
        /// If the node is a leaf, this field stores the index of the first primitive in the `BvhTree` list, otherwise it stores the index of its right child.\
        /// Treat as **immutable**.
        first_or_right_index: u32,
        /// The BVH node axis-aligned bounding box.\
        /// Treat as **immutable**.
        bbox: Aabb,
    };

    const SortContext = struct {
        axis_id: u8,
        hittables: []Hittable
    };

    pub fn init(hittables: []Hittable, min_node_size: usize, allocator: Allocator) Allocator.Error!BvhTree {
        var bvh = BvhTree { .nodes = .empty };

        const indices = try allocator.alloc(usize, hittables.len);
        defer allocator.free(indices);

        for(0..hittables.len) |i| {
            indices[i] = i;
        }

        _ = try bvh.buildBvhNode(hittables, indices, 0, min_node_size, allocator);

        var temp_buf = try allocator.alloc(Hittable, hittables.len);
        defer allocator.free(temp_buf);

        // We reorder the `hittables` array in-place to match the continuous arrangement of the BVH leaves.
        // This guarantees packed, contiguous memory access sequences during tree traversal, significantly maximizing CPU cache hit rates.
        for(indices, 0..) |old_idx, new_idx| {
            temp_buf[new_idx] = hittables[old_idx];
        }

        @memcpy(hittables, temp_buf);

        return bvh;
    }

    pub fn deinit(self: *BvhTree, allocator: Allocator) void {
        self.nodes.deinit(allocator);
    }

    pub fn hit(self: *const BvhTree, hittables: []const Hittable, ray: Ray, ray_t_range: IntervalFloat, hit_record: *HitRecord) bool {
        // A fixed-size stack iterative DFS avoids recursive function call overhead and dynamic heap allocations in the hot path.
        // A capacity of 128 is virtually infinite for a binary tree (safely supporting up to 2^128 geometric primitives).
        var stack: [128]usize = undefined;
        var stack_top: usize = 0;
        var hit_anything = false;
        var current_t_range: IntervalFloat = ray_t_range;

        stack[stack_top] = 0;
        stack_top += 1;
        while (stack_top > 0) {
            stack_top -= 1;

            const node_idx = stack[stack_top];
            const node = self.nodes.items[node_idx];

            const hit_bbox = node.bbox.hit(ray, current_t_range);
            if (hit_bbox == null) {
                continue;
            }

            if (node.primitive_count > 0) {
                // Leaf
                const start = node.first_or_right_index;
                const end = start + node.primitive_count;

                for (hittables[start..end]) |hittable| {
                    if (hittable.hit(ray, current_t_range, hit_record)) {
                        current_t_range.max = hit_record.t; // Ray shrinking
                        hit_anything = true;
                    }
                }
            }
            else {
                std.debug.assert(stack_top + 2 <= stack.len);

                // Internal node
                const left_bbox = self.nodes.items[node_idx + 1].bbox;
                const right_bbox = self.nodes.items[node.first_or_right_index].bbox;
                const left_bbox_point = Vec3 { .x = left_bbox.x.min, .y = left_bbox.y.min, .z = left_bbox.z.min };
                const right_bbox_point = Vec3 { .x = right_bbox.x.min, .y = right_bbox.y.min, .z = right_bbox.z.min };

                const ray_orig_to_left_bbox = Vec3.squaredDistance(left_bbox_point, ray.origin);
                const ray_orig_to_right_bbox = Vec3.squaredDistance(right_bbox_point, ray.origin);

                // We push the furthest node to the stack first so the heuristically closest child is popped first.
                // Traversing nearer geometries earlier maximizes the chance of shrinking `current_t_range.max` quickly,
                // which aggressively culls subsequent AABB checks and speeds up the execution time.
                if (ray_orig_to_left_bbox <= ray_orig_to_right_bbox) {
                    stack[stack_top] = node.first_or_right_index; // right child
                    stack_top += 1;

                    stack[stack_top] = node_idx + 1; // left child (now on top of the stack)
                    stack_top += 1;
                }
                else {
                    stack[stack_top] = node_idx + 1; // left child
                    stack_top += 1;

                    stack[stack_top] = node.first_or_right_index; // right child (now on top of the stack)
                    stack_top += 1;
                }

            }
        }

        return hit_anything;
    }

    fn lessThanIndicesBBox(ctx: SortContext, lhs: usize, rhs: usize) bool {
        var lhs_axis_interval: IntervalFloat = undefined;
        var rhs_axis_interval: IntervalFloat = undefined;

        switch (ctx.axis_id) {
            0 => {
                lhs_axis_interval = ctx.hittables[lhs].bbox().x;
                rhs_axis_interval = ctx.hittables[rhs].bbox().x;
            },
            1 => {
                lhs_axis_interval = ctx.hittables[lhs].bbox().y;
                rhs_axis_interval = ctx.hittables[rhs].bbox().y;
            },
            2 => {
                lhs_axis_interval = ctx.hittables[lhs].bbox().z;
                rhs_axis_interval = ctx.hittables[rhs].bbox().z;
            },
            else => unreachable
        }


        return lhs_axis_interval.min < rhs_axis_interval.min;
    }

    fn buildBvhNode(self: *BvhTree, hittables: []Hittable, indices: []usize, offset: usize, min_node_size: usize, allocator: Allocator) Allocator.Error!u32 {
        _ = try self.nodes.addOne(allocator);
        const node_idx = @as(u32, @intCast(self.nodes.items.len - 1));
        const range_len = indices.len;

        // Build the bounding box of the span of source objects
        var bbox = hittables[indices[0]].bbox();
        if (range_len > 1) {
            for(indices[1..]) |idx| {
                bbox = .initMergeTwo(bbox, hittables[idx].bbox());
            }
        }

        if (range_len <= min_node_size) {
            // Leaf
            self.nodes.items[node_idx] = .{
                .primitive_count = @intCast(range_len),
                .first_or_right_index = @intCast(offset),
                .bbox = bbox
            };

            return node_idx;
        }

        // Internal Node

        // Splitting along the longest axis is a continuous computational shortcut to roughly minimize the surface area
        // of child nodes, which statistically bounds and reduces the probability of a random ray intersecting them.
        const axis_id = bbox.longest_axis();
        std.mem.sortUnstable(usize, indices, SortContext{ .axis_id = axis_id, .hittables = hittables }, lessThanIndicesBBox);

        const mid = range_len / 2;
        const left_idx = try self.buildBvhNode(hittables, indices[0..mid], offset, min_node_size, allocator);
        std.debug.assert(left_idx == node_idx + 1);
        const right_idx = try self.buildBvhNode(hittables, indices[mid..], offset + mid, min_node_size, allocator);

        self.nodes.items[node_idx] = .{
            .primitive_count = 0,
            .first_or_right_index = right_idx,
            .bbox = bbox
        };

        return node_idx;
    }
};

const absEps = std.math.floatEps(Float);
const relEps = @sqrt(std.math.floatEps(Float));

test "Sphere.init" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
    const radius: Float = 4.0;
    const sphere = Sphere.init(center, radius, test_material);

    try testing.expectApproxEqAbs(1.0, sphere.center.x, absEps);
    try testing.expectApproxEqAbs(2.0, sphere.center.y, absEps);
    try testing.expectApproxEqAbs(3.0, sphere.center.z, absEps);
    try testing.expectApproxEqAbs(4.0, sphere.radius, absEps);

    try testing.expectApproxEqAbs(-3.0, sphere.bbox.x.min, absEps);
    try testing.expectApproxEqAbs(5.0, sphere.bbox.x.max, absEps);
    try testing.expectApproxEqAbs(-2.0, sphere.bbox.y.min, absEps);
    try testing.expectApproxEqAbs(6.0, sphere.bbox.y.max, absEps);
    try testing.expectApproxEqAbs(-1.0, sphere.bbox.z.min, absEps);
    try testing.expectApproxEqAbs(7.0, sphere.bbox.z.max, absEps);
}

test "Sphere.hit - ray hits sphere" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3{ .x = 0.0, .y = 0.0, .z = -10.0 };
    const radius: Float = 2.0;
    const sphere = Sphere.init(center, radius, test_material);

    const ray = Ray { .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat { .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = sphere.hit(ray, ray_t_range, &h);
    try testing.expect(hit);

    if (hit) {
        try testing.expectApproxEqRel(@as(Float, 8.0), h.t, relEps);
        try testing.expect(h.front_face);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.y, absEps);
        try testing.expectApproxEqRel(@as(Float, 1.0), h.normal.z, relEps);

        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.y, absEps);
        try testing.expectApproxEqRel(@as(Float, -8.0), h.point.z, relEps);
    }
}

test "Sphere.hit - ray misses sphere" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3 { .x = 5.0, .y = 5.0, .z = -10.0 };
    const radius: Float = 2.0;
    const sphere = Sphere.init(center, radius, test_material);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat { .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = sphere.hit(ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "Sphere.hit - ray hits sphere from inside" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };
    const radius: Float = 5.0;
    const sphere = Sphere.init(center, radius, test_material);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat { .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = sphere.hit(ray, ray_t_range, &h);
    try testing.expect(hit);

    if (hit) {
        try testing.expectApproxEqRel(@as(Float, 5.0), h.t, relEps);
        try testing.expect(!h.front_face); // inside
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.y, absEps);
        try testing.expectApproxEqRel(@as(Float, 1.0), h.normal.z, relEps); // Normal always points AGAINST ray

        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.y, absEps);
        try testing.expectApproxEqRel(@as(Float, -5.0), h.point.z, relEps);

        try testing.expect(std.meta.activeTag(h.material) == std.meta.activeTag(test_material));
    }
}

test "Sphere.hit - hit outside range" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3{ .x = 0.0, .y = 0.0, .z = -10.0 };
    const radius: Float = 2.0;
    const sphere = Sphere.init(center, radius, test_material);

    const ray = Ray{ .origin = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = Vec3{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    // The hit occurs at t=8.0. Set max < 8.0
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 5.0 };

    var h: HitRecord = undefined;
    const hit = sphere.hit(ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "Quad.init" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const q = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const u = Vec3{ .x = 2.0, .y = 0.0, .z = 0.0 };
    const v = Vec3{ .x = 0.0, .y = 2.0, .z = 0.0 };
    const quad = Quad.init(q, u, v, test_material);

    try testing.expectApproxEqAbs(0.0, quad.q.x, absEps);
    try testing.expectApproxEqAbs(2.0, quad.u.x, absEps);
    try testing.expectApproxEqAbs(2.0, quad.v.y, absEps);

    // Normal should be Z-axis
    try testing.expectApproxEqAbs(0.0, quad.normal.x, absEps);
    try testing.expectApproxEqAbs(0.0, quad.normal.y, absEps);
    try testing.expectApproxEqRel(@as(Float, 1.0), quad.normal.z, relEps);

    // D = dot(normal, q) = 0
    try testing.expectApproxEqAbs(0.0, quad.d, absEps);
}

test "Quad.hit - ray hits quad" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const q = Vec3{ .x = -1.0, .y = -1.0, .z = -5.0 };
    const u = Vec3{ .x = 2.0, .y = 0.0, .z = 0.0 };
    const v = Vec3{ .x = 0.0, .y = 2.0, .z = 0.0 };
    const quad = Quad.init(q, u, v, test_material);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = quad.hit(ray, ray_t_range, &h);
    try testing.expect(hit);

    if (hit) {
        try testing.expectApproxEqRel(@as(Float, 5.0), h.t, relEps);
        try testing.expect(h.front_face);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.normal.y, absEps);
        try testing.expectApproxEqRel(@as(Float, 1.0), h.normal.z, relEps);

        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.x, absEps);
        try testing.expectApproxEqAbs(@as(Float, 0.0), h.point.y, absEps);
        try testing.expectApproxEqRel(@as(Float, -5.0), h.point.z, relEps);
    }
}

test "Quad.hit - ray misses quad" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const q = Vec3{ .x = 2.0, .y = 2.0, .z = -5.0 };
    const u = Vec3{ .x = 2.0, .y = 0.0, .z = 0.0 };
    const v = Vec3{ .x = 0.0, .y = 2.0, .z = 0.0 };
    const quad = Quad.init(q, u, v, test_material);

    // Ray goes straight down Z through origin, quad is shifted to x,y > 2
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = quad.hit(ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "Quad.hit - ray parallel to quad" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const q = Vec3{ .x = -1.0, .y = -1.0, .z = -5.0 };
    const u = Vec3{ .x = 2.0, .y = 0.0, .z = 0.0 };
    const v = Vec3{ .x = 0.0, .y = 2.0, .z = 0.0 };
    const quad = Quad.init(q, u, v, test_material);

    // Ray is parallel to the quad (moves along X axis)
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = -2.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = quad.hit(ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "HitRecord.determineNormalOrientation" {
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };

    // Front face: outward normal points against ray
    const norm_front = Vec3{ .x = -1.0, .y = 0.0, .z = 0.0 };
    const res_front = HitRecord.determineNormalOrientation(ray, norm_front);
    try testing.expect(res_front[0] == true);
    try testing.expectApproxEqRel(@as(Float, -1.0), res_front[1].x, relEps);
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_front[1].y, absEps);
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_front[1].z, absEps);

    // Back face: outward normal points in same direction as ray
    const norm_back = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const res_back = HitRecord.determineNormalOrientation(ray, norm_back);
    try testing.expect(res_back[0] == false);
    try testing.expectApproxEqRel(@as(Float, -1.0), res_back[1].x, relEps);
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_back[1].y, absEps);
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_back[1].z, absEps);
}

test "HitRecord.determineNormalOrientation - perpendicular" {
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const norm_perp = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
    const res_perp = HitRecord.determineNormalOrientation(ray, norm_perp);
    try testing.expect(res_perp[0] == false); // dot is 0.0
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_perp[1].x, absEps);
    try testing.expectApproxEqRel(@as(Float, -1.0), res_perp[1].y, relEps);
    try testing.expectApproxEqAbs(@as(Float, 0.0), res_perp[1].z, absEps);
}

test "AABB.initFromPoints" {
    const p1 = Vec3{ .x = 1.0, .y = 5.0, .z = -2.0 };
    const p2 = Vec3{ .x = 4.0, .y = 2.0, .z = 8.0 };

    const bbox = Aabb.initFromPoints(p1, p2);
    try testing.expectApproxEqAbs(1.0, bbox.x.min, absEps);
    try testing.expectApproxEqAbs(4.0, bbox.x.max, absEps);
    try testing.expectApproxEqAbs(2.0, bbox.y.min, absEps);
    try testing.expectApproxEqAbs(5.0, bbox.y.max, absEps);
    try testing.expectApproxEqAbs(-2.0, bbox.z.min, absEps);
    try testing.expectApproxEqAbs(8.0, bbox.z.max, absEps);
}

test "AABB.initMergeTwo" {
    const b1 = Aabb.initFromPoints(
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        Vec3{ .x = 3.0, .y = 3.0, .z = 3.0 }
    );
    const b2 = Aabb.initFromPoints(
        Vec3{ .x = 2.0, .y = 0.0, .z = 2.0 },
        Vec3{ .x = 4.0, .y = 4.0, .z = 4.0 }
    );

    const merged = Aabb.initMergeTwo(b1, b2);
    try testing.expectApproxEqAbs(1.0, merged.x.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.x.max, absEps);
    try testing.expectApproxEqAbs(0.0, merged.y.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.y.max, absEps);
    try testing.expectApproxEqAbs(1.0, merged.z.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.z.max, absEps);
}

test "AABB.hit - ray hits AABB" {
    const bbox = Aabb.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 5.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(4.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(6.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray misses AABB" {
    const bbox = Aabb.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 5.0, .z = 5.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval == null);
}

test "AABB.hit - ray originates inside AABB" {
    const bbox = Aabb.initFromPoints(
        Vec3{ .x = -2.0, .y = -2.0, .z = -2.0 },
        Vec3{ .x = 2.0, .y = 2.0, .z = 2.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(0.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(2.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray parallel to axis (intersecting)" {
    const bbox = Aabb.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    // Ray is parallel to Y and Z axes (dir.y = 0, dir.z = 0)
    const ray = Ray{ .origin = .{ .x = -5.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(4.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(6.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray parallel to axis (missing)" {
    const bbox = Aabb.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    // Ray is parallel to Y and Z axes, but misses because its origin is off
    const ray = Ray{ .origin = .{ .x = -5.0, .y = 3.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval == null);
}

test "Aabb.longest_axis" {
    const bbox_x = Aabb.initFromPoints(Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, Vec3{ .x = 10.0, .y = 2.0, .z = 1.0 });
    try testing.expectEqual(@as(u8, 0), bbox_x.longest_axis());

    const bbox_y = Aabb.initFromPoints(Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, Vec3{ .x = 2.0, .y = 10.0, .z = 1.0 });
    try testing.expectEqual(@as(u8, 1), bbox_y.longest_axis());

    const bbox_z = Aabb.initFromPoints(Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, Vec3{ .x = 2.0, .y = 1.0, .z = 10.0 });
    try testing.expectEqual(@as(u8, 2), bbox_z.longest_axis());
}

test "BvhTree.init and BvhTree.deinit" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    var hittables = [_]Hittable{
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, 1.0, test_material) },
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 10.0, .y = 0.0, .z = 0.0 }, 1.0, test_material) },
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 0.0, .y = 10.0, .z = 0.0 }, 1.0, test_material) },
    };

    var bvh = try BvhTree.init(&hittables, 1, testing.allocator);
    defer bvh.deinit(testing.allocator);

    // Number of nodes is 5 for 3 elements with min_node_size = 1 (2 inner nodes, 3 leaves).
    try testing.expectEqual(@as(usize, 5), bvh.nodes.items.len);
}

test "BvhTree.hit - hit something" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    var hittables = [_]Hittable{
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 0.0, .y = 0.0, .z = -10.0 }, 2.0, test_material) },
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 10.0, .y = 0.0, .z = 0.0 }, 1.0, test_material) },
    };

    var bvh = try BvhTree.init(&hittables, 1, testing.allocator);
    defer bvh.deinit(testing.allocator);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = bvh.hit(&hittables, ray, ray_t_range, &h);
    try testing.expect(hit);
    if (hit) {
        try testing.expectApproxEqRel(@as(Float, 8.0), h.t, relEps);
    }
}

test "BvhTree.hit - miss everything" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    var hittables = [_]Hittable{
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 10.0, .y = 0.0, .z = -10.0 }, 2.0, test_material) },
        Hittable{ .sphere = Sphere.init(Vec3{ .x = -10.0, .y = 0.0, .z = 0.0 }, 1.0, test_material) },
    };

    var bvh = try BvhTree.init(&hittables, 1, testing.allocator);
    defer bvh.deinit(testing.allocator);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 100.0 };

    var h: HitRecord = undefined;
    const hit = bvh.hit(&hittables, ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "BvhTree.hit - outside range" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    var hittables = [_]Hittable{
        Hittable{ .sphere = Sphere.init(Vec3{ .x = 0.0, .y = 0.0, .z = -10.0 }, 2.0, test_material) },
    };

    var bvh = try BvhTree.init(&hittables, 1, testing.allocator);
    defer bvh.deinit(testing.allocator);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = IntervalFloat{ .min = 0.0, .max = 5.0 };

    var h: HitRecord = undefined;
    const hit = bvh.hit(&hittables, ray, ray_t_range, &h);
    try testing.expect(!hit);
}

test "Aabb.padToMinimums" {
    var bbox = Aabb{
        .x = IntervalFloat{ .min = 0.0, .max = 0.05 },
        .y = IntervalFloat{ .min = 0.0, .max = 0.2 },
        .z = IntervalFloat{ .min = 0.0, .max = 0.05 },
    };

    bbox.padToMinimums(0.1);

    try testing.expectApproxEqAbs(@as(Float, -0.05), bbox.x.min, absEps);
    try testing.expectApproxEqAbs(@as(Float, 0.1), bbox.x.max, absEps);

    try testing.expectApproxEqAbs(@as(Float, 0.0), bbox.y.min, absEps);
    try testing.expectApproxEqAbs(@as(Float, 0.2), bbox.y.max, absEps);

    try testing.expectApproxEqAbs(@as(Float, -0.05), bbox.z.min, absEps);
    try testing.expectApproxEqAbs(@as(Float, 0.1), bbox.z.max, absEps);
}
