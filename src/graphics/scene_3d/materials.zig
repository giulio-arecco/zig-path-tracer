const std = @import("std");

const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const HitRecord = @import("geometry.zig").HitRecord;
const Float = @import("../../config.zig").Float;

const dot = Vec3.dot;

pub const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,

    pub fn scatter(self: Material, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        return switch (self) {
            inline else => |mat| mat.scatter(ray, hit, rand)
        };
    }
};

pub const ScatterResult = struct {
    scattered_ray: ?Ray,
    attenuation: LinearColor
};

pub const Lambertian = struct {
    albedo: LinearColor,

    pub fn scatter(self: Lambertian, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        _ = ray;

        const tmp = hit.normal.add(Vec3.randomNormalized(rand));
        const scatter_dir = if (tmp.isNearZero()) hit.normal else tmp;

        const scattered_ray = Ray { .origin = hit.point, .dir = scatter_dir };

        return .{
            .scattered_ray = scattered_ray,
            .attenuation = self.albedo
        };
    }
};

pub const Metal = struct {
    albedo: LinearColor,
    /// This should be in range `[0.0, 1.0]`
    fuzz: Float,

    pub fn scatter(self: Metal, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        std.debug.assert(self.fuzz >= 0.0 and self.fuzz <= 1.0);

        const reflected_dir = ray.dir.reflectOnUnit(hit.normal).normalized();
        const fuzz_dir = Vec3.randomNormalized(rand).scalarMul(self.fuzz);
        const scatter_dir = reflected_dir.add(fuzz_dir);
        const scattered_ray = Ray { .origin = hit.point, .dir = scatter_dir };

        return .{ .scattered_ray = if (dot(scatter_dir, hit.normal) > 0) scattered_ray else null, .attenuation = self.albedo } ;
    }
};
