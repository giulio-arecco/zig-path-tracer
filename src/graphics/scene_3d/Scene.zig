const Scene = @This();

const geometry = @import("geometry.zig");
const config = @import("../../config.zig");

const Ray = @import("Ray.zig");
const HitRecord = geometry.HitRecord;
const Float = config.Float;

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;


camera: Camera,
hittables: []const Hittable, //TODO: Possibly make this dynamically allocated so that it can be interacted with at runtime

pub fn hit(self: Scene, ray: Ray, ray_tmin: Float, ray_tmax: Float) ?HitRecord {
    var closest_t = ray_tmax;
    var closest_hit: ?HitRecord = null;

    for (self.hittables) |hittable| {
        const h = hittable.hit(ray, ray_tmin, ray_tmax);
        if (h) |record| {
            if (record.t < closest_t) {
                closest_t = record.t;
                closest_hit = record;
            }
        }
    }

    return closest_hit;
}
