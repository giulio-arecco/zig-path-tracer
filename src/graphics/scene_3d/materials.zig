const std = @import("std");

const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const HitRecord = @import("geometry.zig").HitRecord;

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

    pub fn scatter(self: Metal, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        _ = rand;

        const scatter_dir = ray.dir.reflectOnUnit(hit.normal);
        const scattered_ray = Ray { .origin = hit.point, .dir = scatter_dir };

        return .{
            .scattered_ray = scattered_ray,
            .attenuation = self.albedo
        };
    }
};
