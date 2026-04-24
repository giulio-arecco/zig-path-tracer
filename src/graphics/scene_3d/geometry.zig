const std = @import("std");
const config = @import("../../config.zig");
const math_utils = @import("../../math_utils.zig");

const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const Float = config.Float;

const dot = Vec3.dot;
const evaluateDiscriminantReduced = math_utils.evaluateDiscriminantReduced;


pub const Sphere = struct {
    center: Vec3,
    radius: Float,

    pub fn hit(self: Sphere, ray: Ray, ray_tmin: Float, ray_tmax: Float) ?HitRecord {
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

        const discr_sqrt = @sqrt(discr);

        // Find the nearest root that lies in the acceptable range
        var root = (h - discr_sqrt) / a; // Remember, we use h and not -h in the reduced formula because it's defined as -b/2.0, so b = -2.0*h
        if (root <= ray_tmin or root >= ray_tmax) {
            root = (h + discr_sqrt) / a;
            if (root <= ray_tmin or root >= ray_tmax) {
                return null;
            }
        }

        const point = ray.at(root);
        const outward_normal = (point.sub(self.center)).scalarDiv(self.radius);
        const front_face, const normal = HitRecord.determineNormalOrientation(ray, outward_normal);

        return HitRecord {
          .t = root,
          .point = point,
          .normal = normal,
          .front_face = front_face
        };
    }
};

pub const HitRecord = struct {
    t: Float,
    point: Vec3,
    normal: Vec3,
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

    pub fn hit(self: Hittable, ray: Ray, ray_tmin: Float, ray_tmax: Float) ?HitRecord {
        switch (self) {
            inline else => |hittable| return hittable.hit(ray, ray_tmin, ray_tmax)
        }
    }
};
