//! Defines the material models used for rendering and how they interact with light.

const std = @import("std");

const LinearColor = @import("../LinearColor.zig");
const Vec3 = @import("../../Vec3.zig");
const Ray = @import("Ray.zig");
const HitRecord = @import("geometry.zig").HitRecord;
const Float = @import("../../global_config.zig").Float;

const dot = Vec3.dot;

/// A polymorphic dispatch type encompassing all distinct material models available.
pub const Material = union(enum) {
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,
    diffuse_light: DiffuseLight,

    /// Computes how a material scatters an incoming ray.
    /// Returns an `Optional` containing the scattered ray and attenuation.
    /// Light sources, which absorb rays entirely, return `null`.
    pub fn scatter(self: Material, ray: Ray, hit: HitRecord, rand: std.Random) ?ScatterResult {
        return switch (self) {
            .diffuse_light => null,
            inline else => |mat| mat.scatter(ray, hit, rand)
        };
    }

    /// Returns the color data emitted directly by the material.
    /// Non-emissive materials return null, while light sources return their emission color.
    pub fn emit(self: Material) ?LinearColor {
        return switch(self) {
            .diffuse_light => |light| light.emit(),
            inline else => null
        };
    }

    pub fn getRoughness(self: Material) Float {
        return switch(self) {
            .lambertian => 1.0,
            .metal => |m| m.fuzz,
            .dielectric => 0.0,
            .diffuse_light => 1.0,
        };
    }
};

pub const ScatterType = enum { diffuse, specular };

/// Represents the result of a ray scattering off a surface.
/// Contains the newly scattered ray direction and the attenuation color factor
/// that indicates how much light is absorbed during the bounce.
pub const ScatterResult = struct {
    scattered_ray: Ray,
    scatter_type: ScatterType,
    attenuation: LinearColor,
};

/// Simulates a matte material.
/// It models light by creating diffuse reflection, scattering incoming rays
/// in random directions across the hemisphere defined by the surface normal.
pub const Lambertian = struct {
    albedo: LinearColor,

    pub fn scatter(self: Lambertian, ray: Ray, hit: HitRecord, rand: std.Random) ScatterResult {
        _ = ray;

        // Ideal Lambertian reflection
        const tmp = hit.normal.add(Vec3.randomNormalized(rand));
        const scatter_dir = if (tmp.isNearZero()) hit.normal else tmp;

        const scattered_ray = Ray { .origin = hit.point, .dir = scatter_dir };

        return .{
            .scattered_ray = scattered_ray,
            .attenuation = self.albedo,
            .scatter_type = .diffuse
        };
    }
};

/// Simulates a shiny or metallic surface.
/// It models light through pure specular reflection by mirroring the incoming ray
/// against the surface normal, optionally perturbing the result to simulate fuzzy reflections.
pub const Metal = struct {
    albedo: LinearColor,
    /// The fuzziness factor must be in range `[0.0, 1.0]`
    fuzz: Float,

    pub fn scatter(self: Metal, ray: Ray, hit: HitRecord, rand: std.Random) ?ScatterResult {
        std.debug.assert(self.fuzz >= 0.0 and self.fuzz <= 1.0);

        const reflected_dir = ray.dir.reflectOnUnit(hit.normal).normalized();
        const fuzz_dir = Vec3.randomNormalized(rand).scalarMul(self.fuzz);
        const scatter_dir = reflected_dir.add(fuzz_dir);
        const scattered_ray = Ray { .origin = hit.point, .dir = scatter_dir };

        return if (dot(scatter_dir, hit.normal) <= 0) null else .{
            .scattered_ray = scattered_ray,
            .attenuation = self.albedo,
            .scatter_type = .specular
        };
    }
};

/// Simulates clear materials such as water or glass.
/// It models light by using Snell's law to compute refraction and reflection
/// directions based on the material's index of refraction, probabilistically choosing
/// between them based on the viewing angle.
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
            return .{
                .scattered_ray = reflected_ray,
                .attenuation = attenuation,
                .scatter_type = .specular
            };
        }
        else {
            const refracted_dir = Vec3.refract(unit_dir, hit.normal, ri);
            const refracted_ray = Ray { .origin = hit.point, .dir = refracted_dir };
            return .{
                .scattered_ray = refracted_ray,
                .attenuation = attenuation,
                .scatter_type = .specular
            };
        }
    }

    /// This function uses Schlick's approximation for reflectance.
    fn reflectance(cosine: Float, refractive_index: Float) Float {
        // Approximates Fresnel equations representing how reflection increases at grazing angles,
        // dynamically shifting probability between reflection and refraction based on the view angle.
        const r0 = (1.0 - refractive_index) / (1.0 + refractive_index);
        const r0_sq = r0 * r0;
        return r0_sq + (1 - r0_sq) * std.math.pow(Float, (1.0 - cosine), 5.0);
    }
};

/// Simulates a light-emitting surface.
/// It models light by directly emitting color values when hit by a ray.
/// Incoming rays are fully absorbed and not scattered.
pub const DiffuseLight = struct {
    color: LinearColor,

    pub fn emit(self: DiffuseLight) LinearColor {
        return self.color;
    }
};
