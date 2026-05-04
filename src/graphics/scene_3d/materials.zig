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
    dielectic: Dielectric,

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
    /// The fuzziness factor must be in range `[0.0, 1.0]`
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

pub const Dielectric = struct {
    /// Refractive index in vacuum or air, or the ratio of the material's refractive index over
    /// the refractive index of the enclosing media
    refractive_index: Float,

    pub fn scatter(self: Dielectric, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        const attenuation = LinearColor.init(1.0, 1.0, 1.0);
        const ri = if (hit.front_face) 1.0 / self.refractive_index else self.refractive_index;

        const unit_dir = ray.dir.normalized();

        const cos_theta = -dot(unit_dir, hit.normal);
        const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);

        const cannot_refract = ri * sin_theta > 1.0;

        // Randomly choose between reflection and refraction, if refraction is possibile
        if (cannot_refract or reflectance(cos_theta, self.refractive_index) > rand.float(Float)) {
            // Total internal (or external) reflection
            const reflected_dir = Vec3.reflectOnUnit(unit_dir, hit.normal);
            const reflected_ray = Ray { .origin = hit.point, .dir = reflected_dir };
            return .{ .scattered_ray = reflected_ray, .attenuation = attenuation };
        }
        else {
            const refracted_dir = Vec3.refract(unit_dir, hit.normal, ri);
            const refracted_ray = Ray { .origin = hit.point, .dir = refracted_dir };
            return .{ .scattered_ray = refracted_ray, .attenuation = attenuation } ;
        }
    }

    /// This function uses Schlick's approximation for reflectance.
    fn reflectance(cosine: Float, refractive_index: Float) Float {
        const r0 = (1.0 - refractive_index) / (1.0 + refractive_index);
        const r0_sq = r0 * r0;
        return r0_sq + (1 - r0_sq) * std.math.pow(Float, (1.0 - cosine), 5.0);
    }
};
