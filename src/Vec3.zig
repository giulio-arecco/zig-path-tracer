const Vec3 = @This();

const std = @import("std");
const math_utils = @import("math_utils.zig");
const Float = @import("config.zig").Float;

const rescaleFloat = math_utils.rescaleFloat;

x: Float,
y: Float,
z: Float,

pub const ones = Vec3 { .x = 1.0, .y = 1.0, .z = 1.0 };

pub const zeroes = Vec3 { .x = 0.0, .y = 0.0, .z = 0.0 };

pub fn init(x: Float, y: Float, z: Float) Vec3 {
    return .{ .x = x, .y = y, .z = z };
}

pub fn dot(a: Vec3, b: Vec3) Float {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn squaredMagnitude(self: Vec3) Float {
    return dot(self, self);
}

pub fn magnitude(self: Vec3) Float {
    return @sqrt(dot(self, self));
}

pub fn isNormalized(v: Vec3) bool {
    if (math_utils.approxEq(Float, squaredMagnitude(v), 1.0))
        return true;

    return false;
}

pub fn normalized(v: Vec3) Vec3 {
    const magnSq = v.squaredMagnitude();
    std.debug.assert(magnSq > std.math.floatMin(Float));

    if (isNormalized(v)) return v;
    return v.scalarDiv(@sqrt(magnSq));
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x =  a.y * b.z - a.z * b.y,
        .y = -a.x * b.z + a.z * b.x,
        .z =  a.x * b.y - a.y * b.x
    };
}

pub fn add(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x + b.x,
        .y = a.y + b.y,
        .z = a.z + b.z
    };
}

/// Returns a - b
pub fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z
    };
}

pub fn squaredDistance(a: Vec3, b: Vec3) Float {
    return squaredMagnitude(a.sub(b));
}

pub fn distance(a: Vec3, b: Vec3) Float {
    return magnitude(a.sub(b));
}

pub fn isApproxEq(self: Vec3, other: Vec3) bool {
    const x_equal = math_utils.approxEq(Float, self.x, other.x);
    const y_equal = math_utils.approxEq(Float, self.y, other.y);
    const z_equal = math_utils.approxEq(Float, self.z, other.z);

    return x_equal and y_equal and z_equal;
}

pub fn scalarMul(v: Vec3, t: Float) Vec3 {
    return .{
        .x = v.x * t,
        .y = v.y * t,
        .z = v.z * t
    };
}

pub fn negated(v: Vec3) Vec3 {
    return .{
        .x = -v.x,
        .y = -v.y,
        .z = -v.z
    };
}

pub fn scalarDiv (v: Vec3, t: Float) Vec3 {
    std.debug.assert(t != 0.0);

    return .{
        .x = v.x / t,
        .y = v.y / t,
        .z = v.z / t
    };
}

pub fn random(rand: std.Random) Vec3 {
    return .{
        .x = rand.float(Float),
        .y = rand.float(Float),
        .z = rand.float(Float)
    };
}

pub fn randomInRange(rand: std.Random, min: Float, max: Float) Vec3 {
    return .{
        .x = rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max }),
        .y = rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max }),
        .z = rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = min, .max = max })
    };
}

pub fn randomNormalized(rand: std.Random) Vec3 {
    while (true) {
        const p = randomInRange(rand, -1.0, 1.0);
        const magnSq = p.squaredMagnitude();

        if (magnSq <= 1.0 and magnSq >= std.math.floatMin(Float)) {
            return p.scalarDiv(@sqrt(magnSq));
        }
    }
}

pub fn randomInUnitDisk(rand: std.Random) Vec3 {
    while (true) {
        const p = Vec3 {
            .x = rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = -1.0, .max = 1.0 }),
            .y = rescaleFloat(Float, rand.float(Float), .{ .min = 0.0, .max = 1.0}, .{ .min = -1.0, .max = 1.0 }),
            .z = 0.0,
        };

        if (p.squaredMagnitude() < 1.0) {
            return p;
        }
    }
}

pub fn randomOnHemisphere(rand: std.Random, normal: Vec3) Vec3 {
    const rand_unit = randomNormalized(rand);
    if (dot(rand_unit, normal) > 0.0) {
        return rand_unit;
    }
    else {
        return rand_unit.negated();
    }
}

pub fn isNearZero(self: Vec3) bool {
    const tol = std.math.floatEps(Float);
    return (@abs(self.x) < tol) and (@abs(self.y) < tol) and (@abs(self.z) < tol);
}

pub fn reflect(v: Vec3, axis: Vec3) Vec3 {
    return v.add(axis.scalarMul(- 2.0 * dot(v, axis) / axis.squaredMagnitude()));
}

/// Asserts that `unit` is normalized.
pub fn reflectOnUnit(v: Vec3, unit: Vec3) Vec3 {
    std.debug.assert(unit.isNormalized());

    const proj = dot(v, unit);
    return v.add(unit.scalarMul(- 2.0 * proj));
}

/// Asserts that `v` and `n` are normalized.
pub fn refract(unit_v: Vec3, n: Vec3, etai_over_etat: Float) Vec3 {
    std.debug.assert(unit_v.isNormalized());
    std.debug.assert(n.isNormalized());

    const cos_theta = @min(-dot(unit_v, n), 1.0);

    const r_out_perp = (unit_v.add(n.scalarMul(cos_theta))).scalarMul(etai_over_etat);
    const r_out_parallel = n.scalarMul(-@sqrt(@abs(1.0 - r_out_perp.squaredMagnitude())));

    return r_out_perp.add(r_out_parallel);
}

// ====================================================================================
// THE FOLLOWING VECTOR FUNCTIONS ARE CURRENTLY NOT UP TO DATE, MEANING
//  THEY DON'T REFLECT ALL THE FUNCTIONALITY PROVIDED BY THE PREVIOUS FUNCTIONS
// ====================================================================================

pub fn vectorDot(a: @Vector(3, Float), b: @Vector(3, Float)) Float {
    return @reduce(.Add, a * b);
}

pub fn vectorSquaredMagnitude(v: @Vector(3, Float)) Float {
    return vectorDot(v, v);
}

pub fn vectorMagnitude(v: @Vector(3, Float)) Float {
    return std.math.sqrt(vectorDot(v, v));
}

pub fn vectorIsNormalized(v: @Vector(3, Float)) bool {
    if (math_utils.approxEq(Float, vectorSquaredMagnitude(v), 1.0))
        return true;

    return false;
}

pub fn vectorNormalized(v: @Vector(3, Float)) @Vector(3, Float) {
    const magnSq = vectorSquaredMagnitude(v);
    std.debug.assert(magnSq > std.math.floatMin(Float));

    if (vectorIsNormalized(v)) return v;

    const mv: @Vector(3, Float) = @splat(@sqrt(magnSq));
    return v / mv;
}

pub fn vectorSquaredDistance(a: @Vector(3, Float), b: @Vector(3, Float)) Float {
    return vectorSquaredMagnitude(a - b);
}

pub fn vectorDistance(a: @Vector(3, Float), b: @Vector(3, Float)) Float {
    return vectorMagnitude(a - b);
}

pub fn vectorCross(a: @Vector(3, Float), b: @Vector(3, Float)) @Vector(3, Float) {
    return @Vector(3, Float) {
         a[1] * b[2] - a[2] * b[1],
        -a[0] * b[2] + a[2] * b[0],
         a[0] * b[1] - a[1] * b[0]
    };
}

pub fn toVector(self: Vec3) @Vector(3, Float) {
    return @Vector(3, Float) {self.x, self.y, self.z};
}

pub fn fromVector(v: @Vector(3, Float)) Vec3 {
    return Vec3.init(v[0], v[1], v[2]);
}

// ======================================================================
//                                 TESTS
// ======================================================================


const eps = 2 * std.math.floatEps(Float);
const inf = std.math.inf(Float);
const nan = std.math.nan(Float);
const isPositiveInf = std.math.isPositiveInf;
const isNegativeInf = std.math.isNegativeInf;
const isNan = std.math.isNan;

test "add" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var b = Vec3.init(2.0, -8.0, 6.0);
    var c = a.add(b);
    try std.testing.expectApproxEqAbs(-3.0, c.x, eps);
    try std.testing.expectApproxEqAbs(2.0, c.y, eps);
    try std.testing.expectApproxEqAbs(9.0, c.z, eps);

    a = .init(0.0, 0.0, 0.0);
    c = a.add(b);
    try std.testing.expectApproxEqAbs(b.x, c.x, eps);
    try std.testing.expectApproxEqAbs(b.y, c.y, eps);
    try std.testing.expectApproxEqAbs(b.z, c.z, eps);

    b = .init(0.0, 0.0, 0.0);
    c = a.add(b);
    try std.testing.expectApproxEqAbs(0.0, c.x, eps);
    try std.testing.expectApproxEqAbs(0.0, c.y, eps);
    try std.testing.expectApproxEqAbs(0.0, c.z, eps);

    a = .init(inf, inf, inf);
    b = .init(1.0, -1.0, 1.0);
    c = a.add(b);
    try std.testing.expect(isPositiveInf(c.x));
    try std.testing.expect(isPositiveInf(c.y));
    try std.testing.expect(isPositiveInf(c.z));

    b = .init(inf, inf, inf);
    c = a.add(b);
    try std.testing.expect(isPositiveInf(c.x));
    try std.testing.expect(isPositiveInf(c.y));
    try std.testing.expect(isPositiveInf(c.z));

    b = .init(-inf, -inf, -inf);
    c = a.add(b);
    try std.testing.expect(isNan(c.x));
    try std.testing.expect(isNan(c.y));
    try std.testing.expect(isNan(c.z));

    a = .init(-inf, -inf, -inf);
    b = .init(1.0, -1.0, 1.0);
    c = a.add(b);
    try std.testing.expect(isNegativeInf(c.x));
    try std.testing.expect(isNegativeInf(c.y));
    try std.testing.expect(isNegativeInf(c.z));
}

test "sub" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var b = Vec3.init(2.0, -8.0, 6.0);
    var c = a.sub(b);
    try std.testing.expectApproxEqAbs(-7.0, c.x, eps);
    try std.testing.expectApproxEqAbs(18.0, c.y, eps);
    try std.testing.expectApproxEqAbs(-3.0, c.z, eps);

    a = .init(0.0, 0.0, 0.0);
    c = a.sub(b);
    try std.testing.expectApproxEqAbs(-b.x, c.x, eps);
    try std.testing.expectApproxEqAbs(-b.y, c.y, eps);
    try std.testing.expectApproxEqAbs(-b.z, c.z, eps);

    b = .init(0.0, 0.0, 0.0);
    c = a.sub(b);
    try std.testing.expectApproxEqAbs(0.0, c.x, eps);
    try std.testing.expectApproxEqAbs(0.0, c.y, eps);
    try std.testing.expectApproxEqAbs(0.0, c.z, eps);

    a = .init(inf, inf, inf);
    b = .init(1.0, -1.0, 1.0);
    c = a.sub(b);
    try std.testing.expect(isPositiveInf(c.x));
    try std.testing.expect(isPositiveInf(c.y));
    try std.testing.expect(isPositiveInf(c.z));

    b = .init(inf, inf, inf);
    c = a.sub(b);
    try std.testing.expect(isNan(c.x));
    try std.testing.expect(isNan(c.y));
    try std.testing.expect(isNan(c.z));

    b = .init(-inf, -inf, -inf);
    c = a.sub(b);
    try std.testing.expect(isPositiveInf(c.x));
    try std.testing.expect(isPositiveInf(c.y));
    try std.testing.expect(isPositiveInf(c.z));

    a = .init(-inf, -inf, -inf);
    b = .init(1.0, -1.0, 1.0);
    c = a.sub(b);
    try std.testing.expect(isNegativeInf(c.x));
    try std.testing.expect(isNegativeInf(c.y));
    try std.testing.expect(isNegativeInf(c.z));

    b = .init(inf, inf, inf);
    c = a.sub(b);
    try std.testing.expect(isNegativeInf(c.x));
    try std.testing.expect(isNegativeInf(c.y));
    try std.testing.expect(isNegativeInf(c.z));
}

test "isEqual" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var b = Vec3.init(-5.0, 10.0, 3.0);
    try std.testing.expect(isApproxEq(a, b));

    a = Vec3.zeroes;
    b = Vec3.zeroes;
    try std.testing.expect(isApproxEq(a, b));

    a = Vec3.zeroes;
    b = Vec3.init(-0.0, 0.0, -0.0);
    try std.testing.expect(isApproxEq(a, b));

    a = Vec3.zeroes;
    b = Vec3.init(-1.0, 0.0, 0.0);
    try std.testing.expect(!isApproxEq(a, b));

    a = Vec3.zeroes;
    b = Vec3.init(0.0, 5.0, 0.0);
    try std.testing.expect(!isApproxEq(a, b));

    a = Vec3.zeroes;
    b = Vec3.init(0.0, 0.0, -12.0);
    try std.testing.expect(!isApproxEq(a, b));

    a = Vec3.init(inf, inf, inf);
    b = Vec3.init(inf, inf, inf);
    try std.testing.expect(isApproxEq(a, b));

    a = Vec3.init(-inf, -inf, -inf);
    b = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(isApproxEq(a, b));

    a = Vec3.init(inf, inf, inf);
    b = Vec3.init(-inf, inf, inf);
    try std.testing.expect(!isApproxEq(a, b));

    a = Vec3.init(nan, nan, nan);
    b = Vec3.init(nan, nan, nan);
    try std.testing.expect(!isApproxEq(a, b));
}

test "scalarMul" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var t: Float = 2.0;
    var b = a.scalarMul(t);
    try std.testing.expectApproxEqAbs(-10.0, b.x, eps);
    try std.testing.expectApproxEqAbs(20.0, b.y, eps);
    try std.testing.expectApproxEqAbs(6.0, b.z, eps);

    a = Vec3.zeroes;
    b = a.scalarMul(t);
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);

    a = Vec3.init(-5.0, 10.0, 3.0);
    t = 0.0;
    b = a.scalarMul(t);
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);

    a = Vec3.init(inf, inf, -inf);
    t = 1.0;
    b = a.scalarMul(t);
    try std.testing.expect(isPositiveInf(b.x));
    try std.testing.expect(isPositiveInf(b.y));
    try std.testing.expect(isNegativeInf(b.z));

    t = 0.0;
    b = a.scalarMul(t);
    try std.testing.expect(isNan(b.x));
    try std.testing.expect(isNan(b.y));
    try std.testing.expect(isNan(b.z));

    t = -inf;
    b = a.scalarMul(t);
    try std.testing.expect(isNegativeInf(b.x));
    try std.testing.expect(isNegativeInf(b.y));
    try std.testing.expect(isPositiveInf(b.z));

    a = Vec3.ones;
    t = inf;
    b = a.scalarMul(t);
    try std.testing.expect(isPositiveInf(b.x));
    try std.testing.expect(isPositiveInf(b.y));
    try std.testing.expect(isPositiveInf(b.z));

    a = Vec3.ones;
    t = -inf;
    b = a.scalarMul(t);
    try std.testing.expect(isNegativeInf(b.x));
    try std.testing.expect(isNegativeInf(b.y));
    try std.testing.expect(isNegativeInf(b.z));
}

test "negated" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var b = a.negated();
    try std.testing.expectApproxEqAbs(5.0, b.x, eps);
    try std.testing.expectApproxEqAbs(-10.0, b.y, eps);
    try std.testing.expectApproxEqAbs(-3.0, b.z, eps);

    a = Vec3.init(0.0, 0.0, 0.0);
    b = a.negated();
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);

    a = Vec3.init(inf, -inf, nan);
    b = a.negated();
    try std.testing.expect(isNegativeInf(b.x));
    try std.testing.expect(isPositiveInf(b.y));
    try std.testing.expect(isNan(b.z));
}

test "scalarDiv" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var t: f32 = 2.0;
    var b = a.scalarDiv(t);
    try std.testing.expectApproxEqAbs(-2.5, b.x, eps);
    try std.testing.expectApproxEqAbs(5.0, b.y, eps);
    try std.testing.expectApproxEqAbs(1.5, b.z, eps);

    a = Vec3.zeroes;
    b = a.scalarDiv(t);
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);

    a = Vec3.init(inf, inf, -inf);
    t = 1.0;
    b = a.scalarDiv(t);
    try std.testing.expect(isPositiveInf(b.x));
    try std.testing.expect(isPositiveInf(b.y));
    try std.testing.expect(isNegativeInf(b.z));

    t = -inf;
    b = a.scalarDiv(t);
    try std.testing.expect(isNan(b.x));
    try std.testing.expect(isNan(b.y));
    try std.testing.expect(isNan(b.z));

    a = Vec3.ones;
    t = inf;
    b = a.scalarDiv(t);
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);

    a = Vec3.ones;
    t = -inf;
    b = a.scalarDiv(t);
    try std.testing.expectApproxEqAbs(0.0, b.x, eps);
    try std.testing.expectApproxEqAbs(0.0, b.y, eps);
    try std.testing.expectApproxEqAbs(0.0, b.z, eps);
}

test "dot" {
    var a = Vec3.init(-5.0, 10.0, 3.0);
    var b = Vec3.init(2.0, -8.0, 6.0);
    try std.testing.expectApproxEqAbs(-72.0, dot(a, b), eps);

    a = .init(0.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(0.0, dot(a, b), eps);

    b = .init(0.0, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(0.0, dot(a, b), eps);

    a = .init(inf, inf, inf);
    b = .init(2.27, 3.56, 12.92);
    try std.testing.expect(isPositiveInf(dot(a, b)));

    b = .init(inf, inf, inf);
    try std.testing.expect(isPositiveInf(dot(a, b)));

    b = .init(-1.0, -1.0, -1.0);
    try std.testing.expect(isNegativeInf(dot(a, b)));

    b = .init(0.0, 1.0, 1.0);
    try std.testing.expect(isNan(dot(a, b)));

    b = .init(1.0, -1.0, 1.0);
    try std.testing.expect(isNan(dot(a, b)));
}

test "squaredMagnitude" {
    try std.testing.expectApproxEqAbs(134.0, (Vec3.init(5.0, -10.0, -3.0)).squaredMagnitude(), eps);
    try std.testing.expectApproxEqAbs(134.0, (Vec3.init(-5.0, 10.0, 3.0)).squaredMagnitude(), eps);
    try std.testing.expectApproxEqAbs(0.0, (Vec3.zeroes).squaredMagnitude(), eps);
    try std.testing.expect(isPositiveInf((Vec3.init(inf, 10.0, -3.0)).squaredMagnitude()));
    try std.testing.expect(isPositiveInf((Vec3.init(-inf, inf, -3.0)).squaredMagnitude()));
    try std.testing.expect(isPositiveInf((Vec3.init(-inf, 10.0, -3.0)).squaredMagnitude()));
}

test "magnitude" {
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), (Vec3.init(-5.0, 10.0, 3.0)).magnitude(), eps);
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), (Vec3.init(5.0, -10.0, -3.0)).magnitude(), eps);
    try std.testing.expectApproxEqAbs(0.0, (Vec3.zeroes).magnitude(), eps);
    try std.testing.expect(isPositiveInf((Vec3.init(inf, 10.0, -3.0)).magnitude()));
    try std.testing.expect(isPositiveInf((Vec3.init(-inf, inf, -3.0)).magnitude()));
    try std.testing.expect(isPositiveInf((Vec3.init(-inf, 10.0, -3.0)).magnitude()));
}

test "isNormalized" {
    try std.testing.expect(isNormalized(.init(std.math.sqrt1_2, std.math.sqrt1_2, 0.0)));
    try std.testing.expect(isNormalized(.init(1.0/std.math.sqrt(3.0), 1.0/std.math.sqrt(3.0), 1.0/std.math.sqrt(3.0))));
    try std.testing.expect(!isNormalized(.init(0.0, 0.0, 0.0)));
    try std.testing.expect(!isNormalized(.init(1.0, 1.0, 1.0)));
    try std.testing.expect(!isNormalized(.init(inf, inf, inf)));
    try std.testing.expect(!isNormalized(.init(-inf, -inf, -inf)));
}

test "normalized" {
    var v = Vec3.init(-5.0, 10.0, 3.0);
    var n = v.normalized();
    try std.testing.expectApproxEqAbs(v.x / std.math.sqrt(134.0), n.x, eps);
    try std.testing.expectApproxEqAbs(v.y / std.math.sqrt(134.0), n.y, eps);
    try std.testing.expectApproxEqAbs(v.z / std.math.sqrt(134.0), n.z, eps);
    try std.testing.expectApproxEqAbs(1.0, std.math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z), eps);

    v = Vec3.init(inf, inf, -inf);
    n = v.normalized();
    try std.testing.expect(isNan(n.x));
    try std.testing.expect(isNan(n.y));
    try std.testing.expect(isNan(n.z));
}

test "squaredDistance" {
    var a = Vec3.init(-2.0, -15.0, 17.0);
    var b = Vec3.init(5.0, -10.0, -3.0);
    try std.testing.expectApproxEqAbs(474.0, a.squaredDistance(b), eps);

    a = Vec3.init(5.0, -10.0, -3.0);
    b = Vec3.init(-2.0, -15.0, 17.0);
    try std.testing.expectApproxEqAbs(474.0, a.squaredDistance(b), eps);

    b = Vec3.zeroes;
    try std.testing.expectApproxEqAbs(134.0, a.squaredDistance(b), eps);

    b = Vec3.init(inf, inf, inf);
    try std.testing.expect(isPositiveInf(a.squaredDistance(b)));

    b = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(isPositiveInf(a.squaredDistance(b)));

    a = Vec3.init(inf, inf, inf);
    b = Vec3.init(inf, inf, inf);
    try std.testing.expect(isNan(a.squaredDistance(b)));

    b = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(isPositiveInf(a.squaredDistance(b)));
}

test "distance" {
    var a = Vec3.init(-2.0, -15.0, 17.0);
    var b = Vec3.init(5.0, -10.0, -3.0);
    try std.testing.expectApproxEqAbs(std.math.sqrt(474.0), a.distance(b), eps);

    a = Vec3.init(5.0, -10.0, -3.0);
    b = Vec3.init(-2.0, -15.0, 17.0);
    try std.testing.expectApproxEqAbs(std.math.sqrt(474.0), a.distance(b), eps);

    b = Vec3.zeroes;
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), a.distance(b), eps);

    b = Vec3.init(inf, inf, inf);
    try std.testing.expect(isPositiveInf(a.distance(b)));

    b = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(isPositiveInf(a.distance(b)));

    a = Vec3.init(inf, inf, inf);
    b = Vec3.init(inf, inf, inf);
    try std.testing.expect(isNan(a.distance(b)));

    b = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(isPositiveInf(a.distance(b)));
}

test "cross" {
    var a = Vec3.init(-5.0, -10.0, 3.0);
    var b = Vec3.init(2.0, -8.0, 6.0);
    var c = cross(a, b);
    try std.testing.expectApproxEqAbs(-36.0, c.x, eps);
    try std.testing.expectApproxEqAbs(36.0, c.y, eps);
    try std.testing.expectApproxEqAbs(60.0, c.z, eps);

    a = .init(0.0, 0.0, 0.0);
    c = cross(a, b);
    try std.testing.expectApproxEqAbs(0.0, c.x, eps);
    try std.testing.expectApproxEqAbs(0.0, c.y, eps);
    try std.testing.expectApproxEqAbs(0.0, c.z, eps);

    b = .init(0.0, 0.0, 0.0);
    c = cross(a, b);
    try std.testing.expectApproxEqAbs(0.0, c.x, eps);
    try std.testing.expectApproxEqAbs(0.0, c.y, eps);
    try std.testing.expectApproxEqAbs(0.0, c.z, eps);

    a = .init(inf, inf, 0.0);
    b = .init(1.0, 1.0, 1.0);
    c = cross(a, b);
    try std.testing.expect(isPositiveInf(c.x));
    try std.testing.expect(isNegativeInf(c.y));
    try std.testing.expect(isNan(c.z));
}

test "isNearZero" {
    const tol = std.math.floatEps(Float);

    var v = Vec3.zeroes;
    try std.testing.expect(v.isNearZero());

    v = Vec3.init(tol / 2.0, -tol / 2.0, 0.0);
    try std.testing.expect(v.isNearZero());

    v = Vec3.init(tol, 0.0, 0.0);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(0.0, -tol, 0.0);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(0.0, 0.0, 1.0);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(inf, inf, inf);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(-inf, -inf, -inf);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(nan, nan, nan);
    try std.testing.expect(!v.isNearZero());

    v = Vec3.init(0.0, 2.0 * tol, 0.0);
    try std.testing.expect(!v.isNearZero());
}

test "reflect" {
    const v = Vec3.init(1.0, -1.0, 0.0);
    var axis = Vec3.init(0.0, 1.0, 0.0);
    var r = reflect(v, axis);
    try std.testing.expectApproxEqAbs(1.0, r.x, eps);
    try std.testing.expectApproxEqAbs(1.0, r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    axis = Vec3.init(0.0, 2.0, 0.0);
    r = reflect(v, axis);
    try std.testing.expectApproxEqAbs(1.0, r.x, eps);
    try std.testing.expectApproxEqAbs(1.0, r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);
}

test "reflectOnUnit" {
    var v = Vec3.init(1.0, -1.0, 0.0);
    var unit = Vec3.init(0.0, 1.0, 0.0);
    var r = reflectOnUnit(v, unit);
    try std.testing.expectApproxEqAbs(1.0, r.x, eps);
    try std.testing.expectApproxEqAbs(1.0, r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    v = Vec3.init(-5.0, 10.0, 3.0);
    unit = Vec3.init(0.0, 0.0, 1.0);
    r = reflectOnUnit(v, unit);
    try std.testing.expectApproxEqAbs(-5.0, r.x, eps);
    try std.testing.expectApproxEqAbs(10.0, r.y, eps);
    try std.testing.expectApproxEqAbs(-3.0, r.z, eps);
}

test "vectorDot" {
    var a = @Vector(3, Float) { -5.0, 10.0, 3.0};
    var b = @Vector(3, Float) { 2.0, -8.0, 6.0};
    try std.testing.expectApproxEqAbs(-72.0, vectorDot(a, b), eps);

    a = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    try std.testing.expectApproxEqAbs(0.0, vectorDot(a, b), eps);

    b = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    try std.testing.expectApproxEqAbs(0.0, vectorDot(a, b), eps);

    a = @Vector(3, Float) { inf, inf, inf };
    b = @Vector(3, Float) { 2.27, 3.56, 12.92};
    try std.testing.expect(isPositiveInf(vectorDot(a, b)));

    b = @Vector(3, Float) { inf, inf, inf };
    try std.testing.expect(isPositiveInf(vectorDot(a, b)));

    b = @Vector(3, Float) { -1.0, -1.0, -1.0 };
    try std.testing.expect(isNegativeInf(vectorDot(a, b)));

    b = @Vector(3, Float) { 0.0, 1.0, 1.0 };
    try std.testing.expect(isNan(vectorDot(a, b)));

    b = @Vector(3, Float) { 1.0, -1.0, 1.0};
    try std.testing.expect(isNan(vectorDot(a, b)));
}

test "vectorSquaredMagnitude" {
    try std.testing.expectApproxEqAbs(134.0, vectorSquaredMagnitude(@Vector(3, Float) { 5.0, -10.0, -3.0 }), eps);
    try std.testing.expectApproxEqAbs(134.0, vectorSquaredMagnitude(@Vector(3, Float) { -5.0, 10.0, 3.0 }), eps);
    try std.testing.expectApproxEqAbs(0.0, vectorSquaredMagnitude(@Vector(3, Float) { 0.0, 0.0, 0.0 }), eps);
    try std.testing.expect(isPositiveInf(vectorSquaredMagnitude(@Vector(3, Float) { inf, 10.0, -3.0 })));
    try std.testing.expect(isPositiveInf(vectorSquaredMagnitude(@Vector(3, Float) { -inf, inf, -3.0 })));
    try std.testing.expect(isPositiveInf(vectorSquaredMagnitude(@Vector(3, Float) { -inf, 10.0, -3.0 })));
}

test "vectorMagnitude" {
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), vectorMagnitude(@Vector(3, Float) { -5.0, 10.0, 3.0 }), eps);
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), vectorMagnitude(@Vector(3, Float) { 5.0, -10.0, -3.0 }), eps);
    try std.testing.expectApproxEqAbs(0.0, vectorMagnitude(@Vector(3, Float) { 0.0, 0.0, 0.0 }), eps);
    try std.testing.expect(isPositiveInf(vectorMagnitude(@Vector(3, Float) { inf, 10.0, -3.0 })));
    try std.testing.expect(isPositiveInf(vectorMagnitude(@Vector(3, Float) { -inf, inf, -3.0 })));
    try std.testing.expect(isPositiveInf(vectorMagnitude(@Vector(3, Float) { -inf, 10.0, -3.0 })));
}

test "vectorIsNormalized" {
    try std.testing.expect(vectorIsNormalized(@Vector(3, Float) { std.math.sqrt1_2, std.math.sqrt1_2, 0.0 }));
    try std.testing.expect(vectorIsNormalized(@Vector(3, Float) { 1.0/std.math.sqrt(3.0), 1.0/std.math.sqrt(3.0), 1.0/std.math.sqrt(3.0) }));
    try std.testing.expect(!vectorIsNormalized(@Vector(3, Float) { 0.0, 0.0,  0.0 }));
    try std.testing.expect(!vectorIsNormalized(@Vector(3, Float) { 1.0, 1.0, 1.0 }));
    try std.testing.expect(!vectorIsNormalized(@Vector(3, Float) { inf, inf, inf }));
    try std.testing.expect(!vectorIsNormalized(@Vector(3, Float) { -inf, -inf, -inf }));
}

test "vectorNormalized" {
    var v = @Vector(3, Float) { -5.0, 10.0, 3.0};
    var n = vectorNormalized(v);
    try std.testing.expectApproxEqAbs(v[0] / std.math.sqrt(134.0), n[0], eps);
    try std.testing.expectApproxEqAbs(v[1] / std.math.sqrt(134.0), n[1], eps);
    try std.testing.expectApproxEqAbs(v[2] / std.math.sqrt(134.0), n[2], eps);
    try std.testing.expectApproxEqAbs(1.0, std.math.sqrt(@reduce(.Add, n*n)), eps);

    v = @Vector(3, Float) { inf, inf, -inf};
    n = vectorNormalized(v);
    try std.testing.expect(isNan(n[0]));
    try std.testing.expect(isNan(n[1]));
    try std.testing.expect(isNan(n[2]));
}

test "vectorSquaredDistance" {
    var a = @Vector(3, Float) { -2.0, -15.0, 17.0 };
    var b = @Vector(3, Float) { 5.0, -10.0, -3.0 };
    try std.testing.expectApproxEqAbs(474.0, vectorSquaredDistance(a, b), eps);

    a = @Vector(3, Float) { 5.0, -10.0, -3.0 };
    b = @Vector(3, Float) { -2.0, -15.0, 17.0 };
    try std.testing.expectApproxEqAbs(474.0, vectorSquaredDistance(a, b), eps);

    b = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    try std.testing.expectApproxEqAbs(134.0, vectorSquaredDistance(a, b), eps);

    b = @Vector(3, Float) { inf, inf, inf };
    try std.testing.expect(isPositiveInf(vectorSquaredDistance(a, b)));

    b = @Vector(3, Float) { -inf, -inf, -inf };
    try std.testing.expect(isPositiveInf(vectorSquaredDistance(a, b)));

    a = @Vector(3, Float) { inf, inf, inf };
    b = @Vector(3, Float) { inf, inf, inf };
    try std.testing.expect(isNan(vectorSquaredDistance(a, b)));

    b = @Vector(3, Float) { -inf, -inf, -inf };
    try std.testing.expect(isPositiveInf(vectorSquaredDistance(a, b)));
}

test "vectorDistance" {
    var a = @Vector(3, Float) { -2.0, -15.0, 17.0 };
    var b = @Vector(3, Float) { 5.0, -10.0, -3.0 };
    try std.testing.expectApproxEqAbs(std.math.sqrt(474.0), vectorDistance(a, b), eps);

    a = @Vector(3, Float) { 5.0, -10.0, -3.0 };
    b = @Vector(3, Float) { -2.0, -15.0, 17.0 };
    try std.testing.expectApproxEqAbs(std.math.sqrt(474.0), vectorDistance(a, b), eps);

    b = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    try std.testing.expectApproxEqAbs(std.math.sqrt(134.0), vectorDistance(a, b), eps);

    b = @Vector(3, Float) { inf, inf, inf };
    try std.testing.expect(isPositiveInf(vectorDistance(a, b)));

    b = @Vector(3, Float) { -inf, -inf, -inf };
    try std.testing.expect(isPositiveInf(vectorDistance(a, b)));

    a = @Vector(3, Float) { inf, inf, inf };
    b = @Vector(3, Float) { inf, inf, inf };
    try std.testing.expect(isNan(vectorDistance(a, b)));

    b = @Vector(3, Float) { -inf, -inf, -inf };
    try std.testing.expect(isPositiveInf(vectorDistance(a, b)));
}

test "vectorCross" {
    var a = @Vector(3, Float) { -5.0, -10.0, 3.0};
    var b = @Vector(3, Float) { 2.0, -8.0, 6.0};
    var c = vectorCross(a, b);
    try std.testing.expectApproxEqAbs(-36.0, c[0], eps);
    try std.testing.expectApproxEqAbs(36.0, c[1], eps);
    try std.testing.expectApproxEqAbs(60.0, c[2], eps);

    a = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    c = vectorCross(a, b);
    try std.testing.expectApproxEqAbs(0.0, c[0], eps);
    try std.testing.expectApproxEqAbs(0.0, c[1], eps);
    try std.testing.expectApproxEqAbs(0.0, c[2], eps);

    b = @Vector(3, Float) { 0.0, 0.0, 0.0 };
    c = vectorCross(a, b);
    try std.testing.expectApproxEqAbs(0.0, c[0], eps);
    try std.testing.expectApproxEqAbs(0.0, c[1], eps);
    try std.testing.expectApproxEqAbs(0.0, c[2], eps);

    a = @Vector(3, Float) { inf, inf, 0.0 };
    b = @Vector(3, Float) { 1.0, 1.0, 1.0};
    c = vectorCross(a, b);
    try std.testing.expect(isPositiveInf(c[0]));
    try std.testing.expect(isNegativeInf(c[1]));
    try std.testing.expect(isNan(c[2]));
}

test "toVector" {
    var a = Vec3 { .x = -5.0, .y = 0.0, .z = 3.0 };
    var b = a.toVector();
    try std.testing.expectEqual(a.x, b[0]);
    try std.testing.expectEqual(a.y, b[1]);
    try std.testing.expectEqual(a.z, b[2]);

    a = Vec3 { .x = inf, .y = -inf, .z = nan };
    b = a.toVector();
    try std.testing.expect(isPositiveInf(b[0]));
    try std.testing.expect(isNegativeInf(b[1]));
    try std.testing.expect(isNan(b[2]));
}

test "fromVector" {
    var a = @Vector(3, Float) { -5.0, 0.0, 3.0 };
    var b = fromVector(a);
    try std.testing.expectEqual(a[0], b.x);
    try std.testing.expectEqual(a[1], b.y);
    try std.testing.expectEqual(a[2], b.z);

    a = @Vector(3, Float) { inf, -inf, nan};
    b = fromVector(a);
    try std.testing.expect(isPositiveInf(b.x));
    try std.testing.expect(isNegativeInf(b.y));
    try std.testing.expect(isNan(b.z));
}

test "refract" {
    const v = Vec3.init(std.math.sqrt1_2, -std.math.sqrt1_2, 0.0);
    const n = Vec3.init(0.0, 1.0, 0.0);

    // Air (1.0) to Glass (1.5)
    var etai_over_etat: Float = 1.0 / 1.5;
    var r = refract(v, n, etai_over_etat);
    var sin_theta_t: Float = @as(Float, std.math.sqrt1_2) * etai_over_etat;
    try std.testing.expectApproxEqAbs(sin_theta_t, r.x, eps);
    try std.testing.expectApproxEqAbs(-std.math.sqrt(1.0 - sin_theta_t * sin_theta_t), r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    // Air (1.0) to Water (1.333)
    etai_over_etat = 1.0 / 1.333;
    r = refract(v, n, etai_over_etat);
    sin_theta_t = @as(Float, std.math.sqrt1_2) * etai_over_etat;
    try std.testing.expectApproxEqAbs(sin_theta_t, r.x, eps);
    try std.testing.expectApproxEqAbs(-std.math.sqrt(1.0 - sin_theta_t * sin_theta_t), r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    // Air (1.0) to Diamond (2.42)
    etai_over_etat = 1.0 / 2.42;
    r = refract(v, n, etai_over_etat);
    sin_theta_t = @as(Float, std.math.sqrt1_2) * etai_over_etat;
    try std.testing.expectApproxEqAbs(sin_theta_t, r.x, eps);
    try std.testing.expectApproxEqAbs(-std.math.sqrt(1.0 - sin_theta_t * sin_theta_t), r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    // Water (1.333) to Glass (1.5)
    etai_over_etat = 1.333 / 1.5;
    r = refract(v, n, etai_over_etat);
    sin_theta_t = @as(Float, std.math.sqrt1_2) * etai_over_etat;
    try std.testing.expectApproxEqAbs(sin_theta_t, r.x, eps);
    try std.testing.expectApproxEqAbs(-std.math.sqrt(1.0 - sin_theta_t * sin_theta_t), r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);

    // Glass (1.5) to Air (1.0)
    // For 45 degrees, angle is greater than critical angle. sin_theta_t = 1.5 * sqrt(2)/2 = 1.06 > 1.0
    // Total internal reflection would occur in reality, but for test logic, let's test a valid angle like 30 degrees (sqrt(3)/2, -0.5, 0).
    const v2 = Vec3.init(-0.5, -std.math.sqrt(@as(Float, 3.0)) / 2.0, 0.0); // 30 deg to normal
    etai_over_etat = 1.5 / 1.0;
    r = refract(v2, n, etai_over_etat);
    sin_theta_t = -0.5 * etai_over_etat; // moving left
    try std.testing.expectApproxEqAbs(sin_theta_t, r.x, eps);
    // Use abs to avoid NaN on total internal reflection
    try std.testing.expectApproxEqAbs(-std.math.sqrt(@abs(1.0 - sin_theta_t * sin_theta_t)), r.y, eps);
    try std.testing.expectApproxEqAbs(0.0, r.z, eps);
}
