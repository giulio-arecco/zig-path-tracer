const std = @import("std");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");
const testing = std.testing;

const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const Float = config.Float;
const Material = @import("materials.zig").Material;
const Interval = math_utils.Interval(Float);
const LinearColor = @import("../LinearColor.zig");

const dot = Vec3.dot;
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
    bbox: AABB,

    pub fn init(center: Vec3, radius: Float, mat: Material) Sphere {
        const radius_vec = Vec3 { .x = radius, .y = radius, .z = radius };
        const bbox = AABB.initFromPoints(center.sub(radius_vec), center.add(radius_vec));

        return .{
            .center = center,
            .radius = radius,
            .material = mat,
            .bbox = bbox
        };
    }

    pub fn hit(self: Sphere, ray: Ray, ray_t_range: Interval) ?HitRecord {
        // Intersection between a ray and a sphere (implicit eq: (x - x_c)^2 + (y - y_c)^2 + (z - z_c)^2 = r^2, parametric eq: (P - C)^2 - r^2 = 0)\
        const eye_to_center = self.center.sub(ray.origin);

        // To find the t parameter we must solve a second-grade linear equation with the following coefficients:
        const a = ray.dir.squaredMagnitude();
        // h == -b/2, where b = dot(ray.dir, eye_to_center) * (-2.0)
        const h = dot(ray.dir, eye_to_center);
        const c = eye_to_center.squaredMagnitude() - self.radius * self.radius;

        const n_sols, const discr = evaluateDiscriminantReduced(Float, a, h, c);
        if (n_sols == 0) {
            return null;
        }

        const discr_sqrt = if (discr == 0.0) 0.0 else @sqrt(discr);

        // Find the nearest root that lies in the acceptable range
        var root = (h - discr_sqrt) / a; // Remember, we use h and not -h in the reduced formula because it's defined as -b/2.0, so b = -2.0*h
        if (root <= ray_t_range.min or root >= ray_t_range.max) {
            root = (h + discr_sqrt) / a;
            if (root <= ray_t_range.min or root >= ray_t_range.max) {
                return null;
            }
        }

        const point = ray.at(root);
        const outward_normal = (point.sub(self.center)).normalized();

        const front_face, const normal = HitRecord.determineNormalOrientation(ray, outward_normal);

        return HitRecord {
          .t = root,
          .point = point,
          .normal = normal,
          .material = self.material,
          .front_face = front_face
        };
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

    pub fn hit(self: Hittable, ray: Ray, ray_t_range: Interval) ?HitRecord {
        switch (self) {
            inline else => |hittable| return hittable.hit(ray, ray_t_range)
        }
    }

    pub fn bbox(self: Hittable) AABB {
        switch (self) {
            inline else => |hittable| return hittable.bbox
        }
    }
};

pub const AABB = struct {
    x: Interval,
    y: Interval,
    z: Interval,

    pub fn initFromPoints(a: Vec3, b: Vec3) AABB {
        return .{
            .x = if (a.x <= b.x) .{ .min = a.x, .max = b.x } else .{ .min = b.x, .max = a.x },
            .y = if (a.y <= b.y) .{ .min = a.y, .max = b.y } else .{ .min = b.y, .max = a.y },
            .z = if (a.z <= b.z) .{ .min = a.z, .max = b.z } else .{ .min = b.z, .max = a.z },
        };
    }

    pub fn initMergeTwo(box0: AABB, box1: AABB) AABB {
        return .{
            .x = Interval.initEncloseTwo(box0.x, box1.x),
            .y = Interval.initEncloseTwo(box0.y, box1.y),
            .z = Interval.initEncloseTwo(box0.z, box1.z)
        };
    }

    pub fn hit(self: AABB, ray: Ray, ray_t_range: Interval) ?Interval {
        var res_t_range = ray_t_range;

        inline for (std.meta.fields(AABB)) |field| {
            const axis_interval = @field(self, field.name);
            const ray_orig_coord = @field(ray.origin, field.name);
            const ray_dir_coord = @field(ray.dir, field.name);
            const ray_dir_coord_inv = 1.0 / ray_dir_coord;

            const t0 = (axis_interval.min - ray_orig_coord) * ray_dir_coord_inv;
            const t1 = (axis_interval.max - ray_orig_coord) * ray_dir_coord_inv;

            if (t0 < t1) {
                if (t0 > res_t_range.min) res_t_range.min = t0;
                if (t1 < res_t_range.max) res_t_range.max = t1;
            }
            else {
                if (t1 > res_t_range.min) res_t_range.min = t1;
                if (t0 < res_t_range.max) res_t_range.max = t0;
            }

            if (res_t_range.max <= res_t_range.min) {
                return null;
            }
        }

        return res_t_range;
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
    const ray_t_range = Interval { .min = 0.0, .max = 100.0 };

    const hit = sphere.hit(ray, ray_t_range);
    try testing.expect(hit != null);

    if (hit) |h| {
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
    const ray_t_range = Interval { .min = 0.0, .max = 100.0 };

    const hit = sphere.hit(ray, ray_t_range);
    try testing.expect(hit == null);
}

test "Sphere.hit - ray hits sphere from inside" {
    const test_material = Material{ .lambertian = .{ .albedo = .{ .v = .{ 0.5, 0.5, 0.5 } } } };
    const center = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };
    const radius: Float = 5.0;
    const sphere = Sphere.init(center, radius, test_material);

    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = Interval { .min = 0.0, .max = 100.0 };

    const hit = sphere.hit(ray, ray_t_range);
    try testing.expect(hit != null);

    if (hit) |h| {
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
    const ray_t_range = Interval{ .min = 0.0, .max = 5.0 };

    const hit = sphere.hit(ray, ray_t_range);
    try testing.expect(hit == null);
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

    const bbox = AABB.initFromPoints(p1, p2);
    try testing.expectApproxEqAbs(1.0, bbox.x.min, absEps);
    try testing.expectApproxEqAbs(4.0, bbox.x.max, absEps);
    try testing.expectApproxEqAbs(2.0, bbox.y.min, absEps);
    try testing.expectApproxEqAbs(5.0, bbox.y.max, absEps);
    try testing.expectApproxEqAbs(-2.0, bbox.z.min, absEps);
    try testing.expectApproxEqAbs(8.0, bbox.z.max, absEps);
}

test "AABB.initMergeTwo" {
    const b1 = AABB.initFromPoints(
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        Vec3{ .x = 3.0, .y = 3.0, .z = 3.0 }
    );
    const b2 = AABB.initFromPoints(
        Vec3{ .x = 2.0, .y = 0.0, .z = 2.0 },
        Vec3{ .x = 4.0, .y = 4.0, .z = 4.0 }
    );

    const merged = AABB.initMergeTwo(b1, b2);
    try testing.expectApproxEqAbs(1.0, merged.x.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.x.max, absEps);
    try testing.expectApproxEqAbs(0.0, merged.y.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.y.max, absEps);
    try testing.expectApproxEqAbs(1.0, merged.z.min, absEps);
    try testing.expectApproxEqAbs(4.0, merged.z.max, absEps);
}

test "AABB.hit - ray hits AABB" {
    const bbox = AABB.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 5.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(4.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(6.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray misses AABB" {
    const bbox = AABB.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 5.0, .z = 5.0 }, .dir = .{ .x = 0.0, .y = 0.0, .z = -1.0 } };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval == null);
}

test "AABB.hit - ray originates inside AABB" {
    const bbox = AABB.initFromPoints(
        Vec3{ .x = -2.0, .y = -2.0, .z = -2.0 },
        Vec3{ .x = 2.0, .y = 2.0, .z = 2.0 }
    );
    const ray = Ray{ .origin = .{ .x = 0.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(0.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(2.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray parallel to axis (intersecting)" {
    const bbox = AABB.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    // Ray is parallel to Y and Z axes (dir.y = 0, dir.z = 0)
    const ray = Ray{ .origin = .{ .x = -5.0, .y = 0.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval != null);
    if (hit_interval) |intvl| {
        try testing.expectApproxEqAbs(4.0, intvl.min, absEps);
        try testing.expectApproxEqAbs(6.0, intvl.max, absEps);
    }
}

test "AABB.hit - ray parallel to axis (missing)" {
    const bbox = AABB.initFromPoints(
        Vec3{ .x = -1.0, .y = -1.0, .z = -1.0 },
        Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }
    );
    // Ray is parallel to Y and Z axes, but misses because its origin is off
    const ray = Ray{ .origin = .{ .x = -5.0, .y = 3.0, .z = 0.0 }, .dir = .{ .x = 1.0, .y = 0.0, .z = 0.0 } };
    const ray_t_range = Interval{ .min = 0.0, .max = 100.0 };

    const hit_interval = bbox.hit(ray, ray_t_range);
    try testing.expect(hit_interval == null);
}
