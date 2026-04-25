const Scene = @This();

const geometry = @import("geometry.zig");

const Camera = @import("Camera.zig");
const Hittable = geometry.Hittable;


camera: Camera,
// hittables: []const Hittable, //TODO: Possibly make this dynamically allocated so that it can be interacted with at runtime
hittable: Hittable,
