# Zig Path Tracer

![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-F7A41D?logo=zig&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

![Cornell Box](images/CornellBox.jpg)

## Table of Contents
- [1. Introduction](#1-introduction)
- [2. System Architecture](#2-system-architecture)
  - [2.1 High-Level Execution Flow](#21-high-level-execution-flow)
  - [2.2 Context Decoupling & Stateless Algorithms](#22-context-decoupling--stateless-algorithms)
  - [2.3 Compile-Time Type Enforcement & Zero-Cost Polymorphism](#23-compile-time-type-enforcement--zero-cost-polymorphism)
- [3. Mathematical Foundations](#3-mathematical-foundations)
  - [3.1 Floating-Point Tolerances & Approximation Verification](#31-floating-point-tolerances--approximation-verification)
  - [3.2 Stable Quadratic Discriminant Formulation](#32-stable-quadratic-discriminant-formulation)
  - [3.3 Numeric Intervals](#33-numeric-intervals)
  - [3.4 3D Vector Operations & SIMD Acceleration](#34-3d-vector-operations--simd-acceleration)
  - [3.5 Linear High-Dynamic-Range Color Transport](#35-linear-high-dynamic-range-color-transport)
- [4. Geometric System & Spatial Acceleration](#4-geometric-system--spatial-acceleration)
  - [4.1 Primitives & Object-Space Transformations](#41-primitives--object-space-transformations)
  - [4.2 Polymorphic Hittable Dispatch](#42-polymorphic-hittable-dispatch)
  - [4.3 Axis-Aligned Bounding Boxes (AABB) & Slab Testing](#43-axis-aligned-bounding-boxes-aabb--slab-testing)
  - [4.4 32-Byte Packed BVH Tree Structure](#44-32-byte-packed-bvh-tree-structure)
  - [4.5 Iterative Fixed-Stack BVH Traversal](#45-iterative-fixed-stack-bvh-traversal)
  - [4.6 Cache Locality Optimization via In-Place Reordering](#46-cache-locality-optimization-via-in-place-reordering)
- [5. Optics, Sampling & Camera Model](#5-optics-sampling--camera-model)
  - [5.1 Right-Handed Viewing Coordinate System](#51-right-handed-viewing-coordinate-system)
  - [5.2 Stratified Multi-Jitter Anti-Aliasing](#52-stratified-multi-jitter-anti-aliasing)
  - [5.3 Physical Thin-Lens Defocus Blur](#53-physical-thin-lens-defocus-blur)
- [6. Materials, Shading & Light Transport](#6-materials-shading--light-transport)
  - [6.1 Material Scattering Formulations](#61-material-scattering-formulations)
  - [6.2 Recursive Monte Carlo Path Tracing](#62-recursive-monte-carlo-path-tracing)
  - [6.3 Split Irradiance & G-Buffer Extraction](#63-split-irradiance--g-buffer-extraction)
- [7. Multithreading & Concurrency Execution](#7-multithreading--concurrency-execution)
  - [7.1 Scanline Task Decomposition](#71-scanline-task-decomposition)
  - [7.2 Statistical PRNG Decorrelation](#72-statistical-prng-decorrelation)
- [8. Image Post-Processing & Denoising Pipeline](#8-image-post-processing--denoising-pipeline)
  - [8.1 Memory Safety via Read-Only Buffer Views](#81-memory-safety-via-read-only-buffer-views)
  - [8.2 Selective Specular Denoising & Roughness Modulation](#82-selective-specular-denoising--roughness-modulation)
  - [8.3 Four-Way Joint Bilateral Spatial Filtering](#83-four-way-joint-bilateral-spatial-filtering)
  - [8.4 Multiscale À-Trous Wavelet Denoising](#84-multiscale-à-trous-wavelet-denoising)
  - [8.5 Radiance Recomposition & Tone Mapping](#85-radiance-recomposition--tone-mapping)
- [9. Memory Architecture, Lifecycle & I/O Subsystem](#9-memory-architecture-lifecycle--io-subsystem)
  - [9.1 Explicit Ownership Hierarchy & Allocation Topology](#91-explicit-ownership-hierarchy--allocation-topology)
  - [9.2 Direct Memory-Mapped PPM P6 Serialization](#92-direct-memory-mapped-ppm-p6-serialization)
  - [9.3 Collision-Free File Generation & Comptime Headers](#93-collision-free-file-generation--comptime-headers)
- [Gallery & Performance](#gallery--performance)
- [Getting Started](#getting-started)

---

## 1. Introduction

This project is a CPU-bound Monte Carlo path tracing engine engineered entirely in the Zig programming language (`0.16.0-dev`). It computes physically based global illumination solutions featuring indirect diffuse interreflection, blurred metallic reflection, dielectric refraction with Fresnel term evaluation, emissive surface lighting, and depth-of-field simulation.

Building upon the foundational concepts from the *[Ray Tracing in One Weekend](https://raytracing.github.io/)* series, the codebase shifts away from C++ object-oriented patterns to leverage Zig's procedural design, explicit memory management, and data-oriented structures. It eliminates virtual function tables (vtables), pointer indirection overhead, dynamic per-primitive allocations, and runtime inheritance hierarchies. Instead, the engine is structured around Data-Oriented Design principles, static compile-time polymorphism, explicit allocator-driven memory lifecycles, and cache-conscious memory layouts.

The engine operates with zero external dependencies, relying exclusively on the Zig standard library for mathematics, memory management, multi-threaded task scheduling, and operating-system-level I/O abstractions.

---

## 2. System Architecture

### 2.1 High-Level Execution Flow

Execution is partitioned into decoupled stages managed by the top-level pipeline orchestrator in `rendering.zig` and initialized in `main.zig`:

```
+-------------------------------------------------------------------------+
|                              main.zig                                   |
|  - CLI Argument Parsing (`parseArgs`)                                   |
|  - Output File & Direct Memory Map Setup (`fs_utils.zig`)               |
|  - Flat Buffer Allocation (Diffuse, Specular, Emission, G-Buffers)      |
|  - Scene Construction & In-Place BVH Compilation (`Scene.zig`)          |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
|                  executeRenderPipeline (rendering.zig)                  |
|                                                                         |
|  [Stage 1: Primary Ray & Path Tracing]                                  |
|   - Renderer Strategy Selection (`SerialPathTracer` / `ParallelPathTracer`)|
|   - Multi-threaded scanline dispatch via `std.Io.Group`                 |
|   - Generation of primary G-Buffers (Albedo, Normal, Depth, Roughness)  |
|   - Radiance accumulation into `SplitIrradiance` (Diffuse, Specular,    |
|     Emission channels)                                                  |
|                                                                         |
|  [Stage 2: Post-Processing & Denoising]                                 |
|   - Input sanitization via `GBuffersReadOnly`                           |
|   - Selective Denoising Pass on `diffuse_buf`                           |
|   - Roughness-modulated Denoising Pass on `specular_buf`                |
|   - Execution via `JointBilateralDenoiser` or `ATrousDenoiser`          |
|                                                                         |
|  [Stage 3: Energy Recomposition]                                        |
|   - Recomposition: Out = (Diffuse * Albedo) + Specular + Emission       |
|                                                                         |
|  [Stage 4: Display Transform & Serialization]                           |
|   - Tone Mapping: Extended Reinhard / Clamp / Reinhard / Exp / Gamma    |
|   - IEC 61966-2-1 standard sRGB transfer curve application              |
|   - Direct big-endian 24-bit integer write into kernel memory map       |
+-------------------------------------------------------------------------+
```

### 2.2 Context Decoupling & Stateless Algorithms

To prevent state contamination across execution steps and multi-threaded worker pools, persistent configuration is decoupled from execution contexts:

* **Configuration State (`AppConfig`, `UserRenderSettings`):** Captures high-level configuration specified by the user via CLI flags.
* **Compiled Parameters (`InternalRenderSettings`):** Immutable precomputed parameters derived during initialization (`sqrt_spp`, `recip_sqrt_spp`, `pixel_samples_scale`). This avoids redundant square root and division calculations inside the pixel sampling loops.
* **Execution State (`RenderContext`, `DenoiserContext`, `PipelineContext`):** Execution contexts holding standard I/O handles (`std.Io`), threading infrastructure, active frame buffer slices, progress tracking nodes (`std.Progress.Node`), and scene references. Algorithms receive contexts by value or pointer, maintaining complete computational statelessness.

### 2.3 Compile-Time Type Enforcement & Zero-Cost Polymorphism

Polymorphic dispatch is achieved through Zig tagged unions rather than runtime dynamic dispatch tables. The `Renderer` struct wraps the `RenderBackend` union:

```zig
pub const RenderBackend = union(RendererType) {
    Serial: SerialPathTracer,
    Parallel: ParallelPathTracer,
};
```

Dispatching inside `Renderer.render` utilizes Zig's `inline else` construct:

```zig
pub fn render(self: Renderer, ctx: RenderContext) !void {
    switch (self.backend) {
        inline else => |impl| return impl.render(self.settings, ctx),
    }
}
```

The compiler expands this block into static calls tailored to the specific struct type, eliminating indirect branch mispredictions. Duck-typing validity across generic types is verified at compile time in `type_utils.zig` via `assertAnytypeHasDecls`:

```zig
pub fn assertAnytypeHasDecls(val: anytype, comptime expected_decls: []const []const u8) void {
    const T = @TypeOf(val);
    const ActualType = switch (@typeInfo(T)) {
        .pointer => |ptr_info| ptr_info.child,
        else => T,
    };
    inline for (expected_decls) |decl| {
        if (!@hasDecl(ActualType, decl)) {
            @compileError("Type '" ++ @typeName(ActualType) ++ "' does not contain the required declaration '" ++ decl ++ "'.");
        }
    }
}
```

---

## 3. Mathematical Foundations

### 3.1 Floating-Point Tolerances & Approximation Verification

Floating-point equality is implemented in `math_utils.zig` via `approxEq`. Standard bitwise comparison fails when floating-point round-off occurs. The function applies a dual absolute-then-relative error threshold:

```zig
pub fn approxEq(comptime T: type, x: T, y: T) bool {
    switch (@typeInfo(T)) {
        .float, .comptime_float => {
            if (std.math.isNan(x) or std.math.isNan(y)) return false;
            if (x == y) return true;
            if (std.math.isInf(x) or std.math.isInf(y)) return false;
            if (std.math.approxEqAbs(T, x, y, 2 * floatEps(T))) return true;
            return std.math.approxEqRel(T, x, y, @sqrt(floatEps(T)));
        },
        .int, .comptime_int => return x == y,
        else => @compileError("approxEq not implemented for " ++ @typeName(T)),
    }
}
```

### 3.2 Stable Quadratic Discriminant Formulation

Ray-sphere intersections require finding real roots of quadratic equations. Direct evaluation of $b^2 - 4ac$ causes numerical cancellation errors when $b^2 \approx 4ac$.

In `math_utils.zig`, discriminant evaluation is implemented in `evaluateDiscriminant` and its reduced form `evaluateDiscriminantReduced`. When the linear coefficient is evenly divisible by 2 ($b = -2h$), substituting into $a t^2 + b t + c = 0$ yields the reduced form:

$$
\Delta = h^2 - ac, \quad t = \frac{h \pm \sqrt{\Delta}}{a}
$$

1. **Hardware Fused Multiply-Add (FMA):** Evaluates `h_sq - a * c` using `@mulAdd(T, -a, c, h_sq)` in a single instruction, preventing intermediate round-off errors.
2. **Magnitude-Scaled Dynamic Thresholding:** Computes the machine epsilon scaled by the maximum operand magnitude $\max(|h^2|, |ac|)$ via `std.math.floatEpsAt(T, max_magnitude) * 2.0`. Discriminant values within this envelope are classified as exactly zero, identifying grazing tangent hits.

### 3.3 Numeric Intervals

The generic `Interval(comptime T: type)` structure encapsulates bounded continuous domains $[t_{\min}, t_{\max}]$. It implements:
* Boundary queries: `contains(x)` ($t_{\min} \le x \le t_{\max}$) and `surrounds(x)` ($t_{\min} < x < t_{\max}$).
* Expansion: `expand(delta)` adds padding symmetrically to avoid zero-thickness degenerate bounding volumes.
* Normalization and Re-mapping: `normalizeFloat` maps a value to $[0.0, 1.0]$, while `rescaleFloat` transfers values between arbitrary source and target domains.

### 3.4 3D Vector Operations & SIMD Acceleration

Spatial mathematics are encapsulated in `Vec3.zig`:
* Basic arithmetic: Vector addition, subtraction, scalar scaling, dot product, and cross product.
* Euclidean distance: `magnitude()` alongside square root-free `squaredMagnitude()` and `squaredDistance()` to minimize computational overhead during distance comparisons.
* Monte Carlo Directional Sampling:
  * `randomNormalized`: Generates uniform points on the unit sphere via rejection sampling inside a $[-1, 1]^3$ cube.
  * `randomInUnitDisk`: Generates rejection-sampled points on the $z=0$ disk for depth-of-field aperture simulation.
  * `randomOnHemisphere`: Aligns sampled directions with the local surface normal hemisphere.
* Optical Physics:
  * `reflectOnUnit`: Computes mirrored directional reflection for incident vector $v$ and unit normal $n$: $v_{\text{refl}} = v - 2(v \cdot n)n$.
  * `refract`: Implements Snell's law in vector form for incident unit vector $v$, unit normal $n$, and refractive index ratio $\eta = \eta_i / \eta_t$, evaluating $r_{\perp} = \eta (v + \cos\theta \cdot n)$, $r_{\parallel} = -\sqrt{|1.0 - \|r_{\perp}\|^2|} \cdot n$, and $v_{\text{refr}} = r_{\perp} + r_{\parallel}$, where $\cos\theta = \min(-v \cdot n, 1.0)$. If total internal reflection occurs ($\eta \sin\theta > 1.0$), the material branches to reflection instead.
* SIMD Extensions: Alternative implementations backed by Zig's native `@Vector(3, Float)` primitive support vector hardware instruction sets for vectorized dot products (`@reduce(.Add, a * b)`), magnitudes, cross products, and normalization.

### 3.5 Linear High-Dynamic-Range Color Transport

Color handling is divided between two dedicated types:
* `LinearColor.zig`: Encapsulates an unbounded HDR radiant flux vector using an underlying `@Vector(3, Float)`. All physical light transport, scattering accumulation, and attenuation multiplications occur within this linear space. SIMD parallel multiplication (`self.v * other.v`) ensures vectorized light attenuation.
* `Color.zig`: Represents an 8-bit non-linear sRGB pixel $[0, 255]^3$. Provides `toPacked() u24` for rapid serialization into frame buffers.

---

## 4. Geometric System & Spatial Acceleration

### 4.1 Primitives & Object-Space Transformations

The engine defines three geometric primitives in `geometry.zig`:

#### Sphere <!-- omit from toc -->
Solves ray-sphere intersection by mapping ray $P(t) = O + t d$ into the implicit sphere equation $(P - C)^2 - r^2 = 0$. With eye-to-center vector $(C - O)$, the reduced quadratic coefficients are:

$$
a = d \cdot d, \quad h = d \cdot (C - O), \quad c = (C - O) \cdot (C - O) - r^2
$$

The roots are resolved via `evaluateDiscriminantReduced`. The nearest root $t$ within `ray_t_range` yields the intersection point $P$, and the outward unit normal $(P - C) / r$ is oriented against the incident ray via `HitRecord.determineNormalOrientation`.

#### Quad <!-- omit from toc -->
Represents a planar quadrilateral defined by corner point $Q$ and edge vectors $u$ and $v$. In `Quad.init`, the supporting plane normal $n = u \times v$, unit normal $\hat{n} = n / \|n\|$, plane constant $D = \hat{n} \cdot Q$, and planar basis vector $w = n / (n \cdot n)$ are precomputed. In `Quad.hit`, ray intersection with the supporting plane computes distance:

$$
t = \frac{D - \hat{n} \cdot O}{\hat{n} \cdot d}
$$

Planar coordinates within the quad's basis are evaluated as $\alpha = w \cdot ((P - Q) \times v)$ and $\beta = w \cdot (u \times (P - Q))$. The intersection is valid if both $\alpha, \beta \in [0, 1]$.

#### Box <!-- omit from toc -->
Encapsulates six internal planar `Quad` surfaces corresponding to opposing faces.

#### Transform Decorators (`Translated`, `Rotate`) <!-- omit from toc -->
* `Translated`: Offsets the incident ray origin by $-\text{offset}$ into object space, performs intersection tests against the nested hittable, and offsets the resulting collision point forward by $+\text{offset}$.
* `Rotate(comptime axis: Axis)`: Evaluates inverse rotation on ray origin and direction by $-\theta$ around the specified axis using precomputed $\sin\theta$ and $\cos\theta$. Intersection points and normal vectors are rotated forward by $+\theta$ back to world space. Bounding boxes are computed by rotating all eight AABB corners and evaluating coordinate minimums and maximums.

### 4.2 Polymorphic Hittable Dispatch

Geometry is contained within the `Hittable` tagged union:

```zig
pub const Hittable = union(enum) {
    sphere: Sphere,
    quad: Quad,
    box: *const Box,
    translated: Translated,
    rotated_x: RotatedX,
    rotated_y: RotatedY,
    rotated_z: RotatedZ,

    pub fn hit(self: Hittable, ray: Ray, ray_t_range: IntervalFloat, hit_record: *HitRecord) bool {
        switch (self) {
            inline else => |hittable| return hittable.hit(ray, ray_t_range, hit_record),
        }
    }
    pub fn bbox(self: Hittable) Aabb {
        switch (self) {
            inline else => |hittable| return hittable.bbox(),
        }
    }
};
```

Primitive hits update a mutable `HitRecord`, which captures distance $t$, hit point $P$, surface unit normal $n$, front-face orientation boolean, and an unowned pointer to the surface `Material`.

### 4.3 Axis-Aligned Bounding Boxes (AABB) & Slab Testing

The `Aabb` struct defines bounding volumes along three dimensions ($x, y, z$) via `Interval(Float)`.

Ray-box intersection implements Kay and Kajiya's slab method with IEEE-754 floating-point edge case handling:

```zig
pub fn hit(self: Aabb, ray: Ray, ray_t_range: IntervalFloat) ?IntervalFloat {
    var res_t_range = ray_t_range;
    inline for (std.meta.fields(Aabb)) |field| {
        const axis_interval = @field(self, field.name);
        const ray_orig_coord = @field(ray.origin, field.name);
        const ray_dir_coord = @field(ray.dir, field.name);
        const ray_dir_coord_inv = 1.0 / ray_dir_coord;

        var t0 = (axis_interval.min - ray_orig_coord) * ray_dir_coord_inv;
        var t1 = (axis_interval.max - ray_orig_coord) * ray_dir_coord_inv;

        if (ray_dir_coord_inv < 0.0) {
            const temp = t0;
            t0 = t1;
            t1 = temp;
        }

        if (t0 > res_t_range.min) res_t_range.min = t0;
        if (t1 < res_t_range.max) res_t_range.max = t1;

        if (res_t_range.max <= res_t_range.min) return null;
    }
    return res_t_range;
}
```

* **NaN Propagation Defense:** When a ray is parallel to an axis ($d = 0$) and its origin lies on the boundary, $t_0$ or $t_1$ evaluates to $0.0 \times \infty = \text{NaN}$. Instead of conditional swapping based on $t_0 < t_1$ (which fails under NaNs), swapping is strictly conditioned on `ray_dir_coord_inv < 0.0`. Under IEEE-754 rules, relational comparisons against NaN evaluate to false, skipping invalid interval contraction and allowing other axes to cull the ray.
* **Degenerate Plane Padding (`padToMinimums`):** To avoid infinite loop traps on completely planar quads (e.g., $z=0$), bounding box extents are expanded to maintain a minimum safe delta scaled against local coordinate machine epsilon (`floatEpsAt`).

### 4.4 32-Byte Packed BVH Tree Structure

To optimize cache locality and memory throughput, `BvhNode` avoids tagged union wrappers, enforcing an exact 32-byte memory layout (matching half a standard 64-byte CPU cache line):

```zig
pub const BvhNode = struct {
    primitive_count: u32,       // 4 bytes: 0 for internal node; > 0 for leaf
    first_or_right_index: u32,  // 4 bytes: primitive index (leaf) or right child index (internal)
    bbox: Aabb,                 // 24 bytes: 3 axes * 2 bounds * 4 bytes (f32)
};
```

Total size: $4 + 4 + 24 = 32\text{ bytes}$. If `primitive_count == 0`, the node is internal, with its left child situated implicitly at `node_index + 1` and its right child at `first_or_right_index`.

### 4.5 Iterative Fixed-Stack BVH Traversal

Traversal bypasses recursive function calls. It uses a fixed-size stack of 128 indices allocated directly on the call frame (`var stack: [128]usize = undefined;`). For binary trees, a depth of 128 safely accommodates trees indexing up to $2^{128}$ primitives, preventing stack overflows without dynamic heap allocation on the ray traversal path.

**Traversal Order Optimization:**
When descending internal nodes, the engine calculates the squared distance from the ray origin to the bounding box minimum point of both children:

```zig
if (ray_orig_to_left_bbox <= ray_orig_to_right_bbox) {
    stack[stack_top] = node.first_or_right_index; // Push right child first
    stack_top += 1;
    stack[stack_top] = node_idx + 1;              // Push left child (popped first)
    stack_top += 1;
} else {
    stack[stack_top] = node_idx + 1;
    stack_top += 1;
    stack[stack_top] = node.first_or_right_index;
    stack_top += 1;
}
```

The node closer to the ray origin is processed first. When a closer hit occurs, `current_t_range.max` is contracted to the hit distance $t$, allowing subsequent distant bounding boxes to be culled immediately.

### 4.6 Cache Locality Optimization via In-Place Reordering

During tree construction (`BvhTree.init`), the algorithm builds index spans along the longest bounding box dimension (`longest_axis`), sorting via `std.mem.sortUnstable`. Once the tree hierarchy is established, the source `hittables` array is reordered in-place:

```zig
for (indices, 0..) |old_idx, new_idx| {
    temp_buf[new_idx] = hittables[old_idx];
}
@memcpy(hittables, temp_buf);
```

Leaf nodes reference contiguous sequential index ranges (`hittables[start .. start + count]`). As a result, primitive evaluations during BVH traversal access memory sequentially, maximizing hardware L1/L2 data cache hit rates.

---

## 5. Optics, Sampling & Camera Model

### 5.1 Right-Handed Viewing Coordinate System

The `Camera` struct in `Camera.zig` implements a right-handed coordinate frame:
* Forward direction vector: Points from target to camera (right-handed convention), computed as unit vector $u_{\text{forward}} = (P_{\text{from}} - P_{\text{to}}) / \|P_{\text{from}} - P_{\text{to}}\|$.
* Singularity Guard: In `initLookAt`, a reference up vector $v_{\text{ref}} = (0, 1, 0)$ is tested against $u_{\text{forward}}$. If parallel ($|v_{\text{ref}} \cdot u_{\text{forward}}| \approx 1.0$), the reference vector switches to $(0, 0, 1)$ to prevent a degenerate zero cross product. Basis vectors are then established as $u_{\text{right}} = v_{\text{ref}} \times u_{\text{forward}}$ and $u_{\text{up}} = u_{\text{forward}} \times u_{\text{right}}$.
* Pixel Delta Grid: Computes horizontal step $\Delta u$ and vertical step $\Delta v$ (inverted to align screen-space down with world space).

### 5.2 Stratified Multi-Jitter Anti-Aliasing

Anti-aliasing divides each pixel into a stratified sub-pixel grid of dimension $\sqrt{\text{SPP}} \times \sqrt{\text{SPP}}$, precomputed in `InternalRenderSettings`:

```zig
fn sample_square_stratified(rand: std.Random, square_side_length: Float, sample_i: usize, sample_j: usize) Vec3 {
    const px = ((@as(Float, @floatFromInt(sample_i)) + rand.float(Float)) * square_side_length) - 0.5;
    const py = ((@as(Float, @floatFromInt(sample_j)) + rand.float(Float)) * square_side_length) - 0.5;
    return .init(px, py, 0.0);
}
```

Stratified sampling bounds sample dispersion across sub-pixel cells, reducing low-frequency Monte Carlo noise compared to unstratified pseudo-random sampling.

### 5.3 Physical Thin-Lens Defocus Blur

Depth of field is simulated via a physical thin-lens model. A non-zero defocus angle ($\theta_{\text{defocus}}$, configured via `defocus_angle`) defines the aperture disk radius based on focal distance ($d_{\text{focus}}$, configured via `focus_distance`):

$$
r_{\text{defocus}} = d_{\text{focus}} \cdot \tan\left(\frac{\theta_{\text{defocus}}}{2} \cdot \frac{\pi}{180}\right)
$$

Ray origins are sampled across the aperture disk by offsetting the camera position using unit disk coordinates $(p_x, p_y)$ from `Vec3.randomInUnitDisk`:

$$
P_{\text{origin}} = P_{\text{camera}} + (u_{\text{disk}} \cdot p_x) + (v_{\text{disk}} \cdot p_y)
$$

where $u_{\text{disk}} = u_{\text{right}} \cdot r_{\text{defocus}}$ and $v_{\text{disk}} = u_{\text{up}} \cdot r_{\text{defocus}}$. Rays converge at the focal plane located at `focus_distance`, producing focal sharpness at the target distance and progressive circle-of-confusion blur elsewhere.

---

## 6. Materials, Shading & Light Transport

### 6.1 Material Scattering Formulations

Surface interactions are implemented in `materials.zig` via the `Material` tagged union:

| Material | Physical Model | Implementation Equations |
| :--- | :--- | :--- |
| **Lambertian** | Ideal diffuse interreflection | $v_{\text{scatter}} = n + v_{\text{rand}}$; Attenuation = Albedo; Scattering Type = Diffuse |
| **Metal** | Specular reflection with surface roughness | $v_{\text{refl}} = \text{reflectOnUnit}(v_{\text{in}}, n) + (\text{fuzz} \cdot v_{\text{rand}})$; Absorbed if $v_{\text{refl}} \cdot n \le 0$; Attenuation = Albedo; Scattering Type = Specular |
| **Dielectric** | Snell's law refraction & Fresnel reflection | Total internal reflection if $ri \cdot \sin\theta > 1.0$ (where $ri = 1 / n_{\text{refr}}$ for front faces, $n_{\text{refr}}$ for back faces); Fresnel reflectance estimated via Schlick approximation: $R(\theta) = R_0 + (1 - R_0)(1 - \cos\theta)^5$, where $R_0 = \left(\frac{1 - n_{\text{refr}}}{1 + n_{\text{refr}}}\right)^2$; Attenuation = $(1, 1, 1)$; Scattering Type = Specular |
| **DiffuseLight**| Radiant energy emitter | Absorbs incident rays entirely (`scatter() = null`); Direct emission = $L_{\text{emit}}$ |

### 6.2 Recursive Monte Carlo Path Tracing

Radiance transport is evaluated recursively in `rendering.zig` via `rayColor`:
* Traces rays up to `max_ray_bounces`. If recursion depth reaches zero, black (`LinearColor.black`) is returned.
* Hits against non-scattering surfaces return direct emission (`hit_record.material.emit() orelse LinearColor.black`).
* Hits against scattering surfaces recurse along the scattered ray direction. The returned incoming light is multiplied component-wise by surface attenuation (`incoming_light.mul(res.attenuation)`), and any local emitted light is added to the result.

### 6.3 Split Irradiance & G-Buffer Extraction

A key architectural feature of the engine is the separation of radiance into diffuse, specular, and emissive components at the primary ray hit:

```zig
pub const SplitIrradiance = struct {
    diffuse: LinearColor,
    specular: LinearColor,
    emission: LinearColor,
};
```

1. **G-Buffer Capture (`updateFrameBuffers`):** At the primary camera ray intersection, geometric surface properties are written to flat buffers:
   * `albedo_buf`: Un-illuminated base reflectance from `getRecompositionAlbedo(material)`.
   * `normal_buf`: Surface normal vector $n$.
   * `depth_buf`: Ray hit parameter $t$ (or $\infty$ for background misses).
   * `roughness_buf`: Surface microfacet roughness (0.0 for dielectrics and smooth metals, 1.0 for Lambertian surfaces).
2. **Primary Irradiance Separation (`tracePrimaryRay`):**
   * Diffuse paths store incoming indirect radiance without multiplying by albedo. This keeps diffuse lighting smooth and untextured for spatial denoising.
   * Specular reflections multiply incoming light by attenuation immediately, baking mirror highlights and dielectric transmissions into `specular_buf``.
   * Emissive materials write directly to `emission_buf`.

---

## 7. Multithreading & Concurrency Execution

### 7.1 Scanline Task Decomposition

Parallel rendering is implemented in `ParallelPathTracer` using standard library multithreading:
* Work is split into horizontal scanlines (rows 0 to `image_height` - 1).
* Each task receives a dedicated `FrameBuffersRenderView` pointing to its corresponding row buffer slice (`start .. end`), avoiding data races across worker threads.
* Tasks are dispatched through `std.Io.Group`:

```zig
var group: std.Io.Group = .init;
defer group.cancel(ctx.io);

for (0..image_height) |y_screen| {
    const start = y_screen * image_width;
    const end = start + image_width;
    const row_buffers = FrameBuffersRenderView {
        .diffuse_buf = ctx.buffers.diffuse_buf[start..end],
        .specular_buf = ctx.buffers.specular_buf[start..end],
        .emission_buf = ctx.buffers.emission_buf[start..end],
        .g_buffers = .{
            .albedo_buf = ctx.buffers.g_buffers.albedo_buf[start..end],
            .normal_buf = ctx.buffers.g_buffers.normal_buf[start..end],
            .depth_buf = ctx.buffers.g_buffers.depth_buf[start..end],
            .roughness_buf = ctx.buffers.g_buffers.roughness_buf[start..end],
        },
    };
    var rowCtx = ctx;
    rowCtx.buffers = row_buffers;
    rowCtx.progress_node = task_node;

    try group.concurrent(ctx.io, renderRow, .{ y_screen, settings, rowCtx });
}
try group.await(ctx.io);
```

### 7.2 Statistical PRNG Decorrelation

In parallel Monte Carlo integration, shared or poorly seeded random number generators cause correlation artifacts, structural banding, and pattern repetition across adjacent image rows.

The engine resolves this in `renderRow` by hashing the camera top-left position with the scanline index using `std.hash.Wyhash`:

```zig
const base_seed: u64 = @intFromFloat(@round(camera.pixel_top_left.squaredMagnitude()));
var hasher = std.hash.Wyhash.init(0);
hasher.update(std.mem.asBytes(&base_seed));
hasher.update(std.mem.asBytes(&y_screen));

var prng: std.Random.DefaultPrng = .init(hasher.final());
const random = prng.random();
```

Wyhash produces strong bit avalanche characteristics. This guarantees that adjacent image scanlines generate completely uncorrelated pseudo-random sequences while remaining fully reproducible.

---

## 8. Image Post-Processing & Denoising Pipeline

### 8.1 Memory Safety via Read-Only Buffer Views

To guarantee that post-processing filters cannot corrupt geometric G-Buffer inputs during execution, the denoiser interface requires `GBuffersReadOnly`:

```zig
pub const GBuffersReadOnly = struct {
    albedo_buf: []const LinearColor,
    normal_buf: []const Vec3,
    depth_buf: []const Float,
    roughness_buf: []const Float,
};
```

During initialization, mutable slices (`[]T`) coerce to immutable slices (`[]const T`). Any accidental mutation attempt within a denoiser pass triggers a compile-time error.

### 8.2 Selective Specular Denoising & Roughness Modulation

Denoising smooth surfaces like mirrors or clear glass using primary surface G-Buffers causes reflection smearing. Because primary G-Buffers describe the geometry of the physical surface rather than the reflected virtual scene, standard bilateral filtering incorrectly blurs crisp reflections across the reflector.

The engine addresses this through selective post-processing in `post_processing.zig`:
* `diffuse_buf` undergoes standard spatial edge-stopping filtering.
* `specular_buf` scales its spatial and luminance variance thresholds based on local surface roughness:

```zig
if (ctx.is_specular) {
    const modulated_sigma_space = @max(ctx.sigma_space * roughness_buf[center_index], 1e-3);
    inv_two_sigma_space_sq = 1.0 / (2.0 * modulated_sigma_space * modulated_sigma_space);

    const modulated_sigma_luma = @max(ctx.specular_sigma_luma * roughness_buf[center_index], 1e-3);
    inv_two_sigma_luma_sq = 1.0 / (2.0 * modulated_sigma_luma * modulated_sigma_luma);
}
```

On specular surfaces with near-zero roughness (such as dielectrics and smooth metals), spatial filter bounds collapse to near-zero ($10^{-3}$), preserving sharp mirror-like reflections without blur.

### 8.3 Four-Way Joint Bilateral Spatial Filtering

The `JointBilateralDenoiser` filters input channels using an $N \times N$ spatial kernel (e.g., $15 \times 15$). It weights neighboring pixels by combining four continuous edge-stopping weights into $W(p, q) = w_{\text{space}} \cdot w_{\text{normal}} \cdot w_{\text{depth}} \cdot w_{\text{luma}}$:

* **Spatial Distance Weight:** Penalizes Euclidean pixel distance between center pixel $(x, y)$ and neighbor $(i, j)$: $w_{\text{space}} = \exp\left(-\frac{(x - i)^2 + (y - j)^2}{2\sigma_{\text{space}}^2}\right)$.
* **Normal Discontinuity Weight:** Penalizes surface normal deviation between center normal $n_p$ and neighbor normal $n_q$: $w_{\text{normal}} = \exp\left(-\frac{(1.0 - \text{clamp}(n_p \cdot n_q, -1.0, 1.0))^2}{2\sigma_{\text{normal}}^2}\right)$.
* **Planar Depth Weight:** Measures perpendicular distance from neighbor point $P_q$ to the tangent plane at center point $P_p$: $w_{\text{depth}} = \exp\left(-\frac{d_{\text{plane}}^2}{2\sigma_{\text{depth}}^2}\right)$, where $d_{\text{plane}} = |(P_q - P_p) \cdot n_p|$ (infinite depth background pixels yield $w_{\text{depth}} = 0.0$, preventing edge leakage).
* **Normalized Luminance Weight:** Evaluates perceived brightness difference using normalized sRGB luminance: $w_{\text{luma}} = \exp\left(-\frac{(L_{\text{norm}, p} - L_{\text{norm}, q})^2}{2\sigma_{\text{luma}}^2}\right)$, where $L_{\text{norm}} = L / (1.0 + L)$ and $L = 0.2126R + 0.7152G + 0.0722B$.

Filtered pixel radiance is evaluated as the normalized weighted sum:

$$
C_{\text{out}} = \frac{\sum_q C_q \cdot W(p, q)}{\sum_q W(p, q)}
$$

### 8.4 Multiscale À-Trous Wavelet Denoising

The `ATrousDenoiser` implements a hierarchical multiscale wavelet decomposition based on the $B_3$-spline filter kernel:

$$
h = \left[\frac{1}{16}, \frac{1}{4}, \frac{3}{8}, \frac{1}{4}, \frac{1}{16}\right]
$$

The algorithm dynamically configures iteration counts depending on channel modality: `diffuse_iterations` (configured to 5 iterations by default) for wide low-frequency indirect diffuse scattering, and `specular_iterations` (configured to 3 iterations by default) for high-frequency glossy reflections.

Across sequential iterations $k \in [0, \text{iterations}-1]$, the filter step scales dyadically ($\text{step} = 2^k$):
* Iteration 0 ($\text{step} = 1$): Filters high-frequency single-pixel noise.
* Iteration 1 ($\text{step} = 2$): Filters noise across 2-pixel strides.
* Iteration 2 ($\text{step} = 4$): Expands coverage across 4-pixel strides.

For kernel offset $(k_x, k_y) \in [0, 4]^2$, the neighbor pixel coordinates are $(x + (k_x - 2) \cdot \text{step}, y + (k_y - 2) \cdot \text{step})$, and the kernel weight is $w_{\text{kernel}} = h[k_x] \cdot h[k_y]$. The combined weight is $W = w_{\text{kernel}} \cdot w_{\text{normal}} \cdot w_{\text{depth}} \cdot w_{\text{luma}}$.

**Memory Optimization via Ping-Pong Buffers:**
The à-trous pass swaps buffer pointers using `std.mem.swap([]LinearColor, &curr_in, &curr_out)` between iterations. This reuses two pre-allocated buffers across all filter passes, avoiding heap allocations during post-processing. If the total iteration count is odd, the final result is copied back to the input buffer via `@memcpy`.

### 8.5 Radiance Recomposition & Tone Mapping

Once denoising completes, the final output image is synthesized in two stages:

#### Color Recomposition (`colorRecomposition`) <!-- omit from toc -->
Recombines separated light transport buffers by multiplying the filtered diffuse irradiance by the high-frequency albedo buffer and adding specular reflection and emission:

$$
C_{\text{HDR}} = (E_{\text{diffuse}} \odot A_{\text{albedo}}) + E_{\text{specular}} + E_{\text{emission}}
$$

This restores crisp surface textures without noise amplification.

#### Display Transform (`DisplayTransform`) <!-- omit from toc -->
* **Tone Mapping:** Compresses unbounded linear radiance values into the displayable dynamic range $[0.0, 1.0]$. Available operators include:
  * *Clamp:* $\min(C, 1.0)$
  * *Reinhard:* $C / (1.0 + C)$
  * *Extended Reinhard:* $C \cdot \left(1.0 + \frac{C}{C_{\text{white}}^2}\right) / (1.0 + C)$
  * *Exp:* $1.0 - \exp(-C \cdot \text{exposure})$
  * *Gamma Compression:* $a \cdot C^\gamma$
* **sRGB Gamma Correction:** Applies the IEC 61966-2-1 standard electro-optical transfer curve to each normalized channel $C \in [0.0, 1.0]$:

$$
C_{\text{sRGB}} = \begin{cases} 12.92 \cdot C & \text{if } C \le 0.0031308 \\\\ 1.055 \cdot C^{1 / 2.4} - 0.055 & \text{if } C > 0.0031308 \end{cases}
$$

* **Quantization:** Clamps transformed channels to $[0.0, 1.0]$, scales by 255.0, rounds to nearest integer, and writes packed 24-bit RGB values directly to kernel memory-mapped pages.

---

## 9. Memory Architecture, Lifecycle & I/O Subsystem

### 9.1 Explicit Ownership Hierarchy & Allocation Topology

The engine adheres strictly to explicit memory management via `std.mem.Allocator`:

```
+-------------------------------------------------------------------------+
|                               Scene                                     |
|  - Owns Material pool: `ArrayList(*const Material)`                     |
|  - Owns Hittable list: `ArrayList(Hittable)`                            |
|  - Owns Optional Acceleration Tree: `?BvhTree`                          |
|  - Owns Transform Decs: `*Hittable` inside `Translated`/`Rotate`        |
+-------------------------------------------------------------------------+
                                   | (Non-owning *const Material pointers)
                                   v
+-------------------------------------------------------------------------+
|                    Geometrical Primitives & Hits                        |
|  - `Sphere.material`, `Quad.material`, `HitRecord.material`             |
|  - Lifetime guaranteed by `Scene.deinit()`                              |
+-------------------------------------------------------------------------+
```

* **Single Ownership Principle:** `Scene` acts as the sole owner of all dynamic scene allocations. Primitives hold non-owning `*const Material` pointers, preventing lifetime ambiguities and double-free bugs.
* **Transformed Geometries:** Heap wrappers for `Translated` and `Rotate` objects are allocated with the scene allocator and released recursively through `Hittable.deinit`.
* **BVH Tree Compilation and Invalidation:** The scene provides `Scene.buildBvh(min_node_size: usize)` to compile the flat `hittables` array into a cache-optimized `BvhTree`. Subsequent calls to `Scene.add` invalidate and free any existing acceleration structure to ensure the spatial hierarchy remains synchronized with geometric state.

### 9.2 Direct Memory-Mapped PPM P6 Serialization

Image output in `main.zig` avoids userspace buffering and filesystem write system calls:

1. The output file size is sized upfront: `total_size = ppm_header_len + (height * width * 3)`.
2. A direct OS-level shared memory map is established via `file.createMemoryMap`:

```zig
try file.setLength(init.io, total_size);
const stat = try file.stat(init.io);
var memory_map = try file.createMemoryMap(init.io, .{ .len = stat.size });
defer memory_map.destroy(init.io);
```

3. The PPM header is written to the initial mapped slice (`memory_map.memory[0..ppm_header_len]`).
4. The frame buffer output pointer points directly to the memory-mapped pixel region:
   ```zig
   .out_buf = memory_map.memory[ppm_header_len..]
   ```
5. Tone mapping and sRGB quantization write packed 24-bit RGB pixels (`std.mem.writeInt(u24, ..., .big)`) directly into kernel-mapped memory pages. Calling `memory_map.write` flushes the mapped pages to disk with zero userland memory copies.

### 9.3 Collision-Free File Generation & Comptime Headers

The filesystem layer in `fs_utils.zig` incorporates two compile-time optimizations:

* **Static PPM Header Calculation:** `computePpmP6HeaderSize` evaluates the exact header length at compile time using `std.fmt.count`:
  ```zig
  pub fn computePpmP6HeaderSize(max_size: u16, img_width: usize, img_height: usize) usize {
      return std.fmt.count("P6\n{d} {d}\n{d}\n", .{ img_width, img_height, max_size });
  }
  ```
* **Collision-Free File Incrementation (`createImgFile`):** When creating an image, if the target path already exists (`error.PathAlreadyExists`), `createFileWithSuffix` scans existing directory entries, extracts numerical suffixes, and assigns the next available integer suffix (`output1.ppm`, `output2.ppm`). Buffer capacities for formatted path strings are determined at compile time based on maximum integer bounds, preventing dynamic heap allocations during file creation.

---

## Gallery & Performance

*Hardware Note: All benchmarks were executed on an i7-12700KF, compiled in `ReleaseFast` mode.*

### Procedural Spheres Scene <!-- omit from toc -->
![Procedural Spheres](images/ProceduralSpheres.jpg)
- **Resolution**: 1280x720
- **Samples per Pixel**: 1000
- **Max Bounces**: 50
- **Denoising**: Off
- **Render Time (Parallel)**: 99s

### Cornell Box Scene <!-- omit from toc -->
![Cornell Box](images/CornellBox.jpg)
- **Resolution**: 800x800
- **Samples per Pixel**: 1000
- **Max Bounces**: 50
- **Denoising**: Off
- **Render Time (Parallel)**: 112s

### Denoising Comparison (Low Sample Count) <!-- omit from toc -->

To demonstrate the efficiency of the post-processing pipeline, the following renders are generated at extremely low sample counts, where Monte Carlo noise is heavily present.

| 50 Samples (No Filter) | 50 Samples (Joint Bilateral) | 50 Samples (A-Trous) |
| :---: | :---: | :---: |
| ![Raw](images/CornellBox-LowSamples.jpg) | ![Joint Bilateral](images/CornellBox-LowSamples-JointBilateral.jpg) | ![ATrous](images/CornellBox-LowSamples-ATrous.jpg) |
| **Render Time**: 5892ms | **Total Time**: 6481ms | **Total Time**: 6175ms |

### Final Scene <!-- omit from toc -->
![Final Scene](images/Final.jpg)
- **Resolution**: 800x800
- **Samples per Pixel**: 1000
- **Max Bounces**: 50
- **Denoising**: Off
- **Render Time (Parallel)**: 855s

## Getting Started

### Prerequisites
Ensure you have [Zig](https://ziglang.org/download/) installed (built and tested on **Zig `0.16.0-dev`**).

### Clone the Repository
```bash
git clone https://github.com/giulio-arecco/zig-path-tracer.git
cd zig-path-tracer
```

### Build & Run

The project uses the standard Zig build system. By default, it optimizes for execution speed (`ReleaseFast`).

You can explicitly change the compilation mode by appending the `-Doptimize` flag. For example, to build with safety checks enabled (`ReleaseSafe`):

```bash
zig build -Doptimize=ReleaseSafe
```

To build and run directly while passing arguments to the executable:

```bash
zig build run --scene CornellBox --samples 100 --track-progress
```

*(Note: Renders are automatically saved to the `renders/` directory as `output.ppm` by default).*

### Command Line Arguments

Whenever an argument expects a value, it can be provided either with the syntax `--<argument>=<value>` or `--<argument> <value>`.

| Argument | Description | Default | Available Values |
| --- | --- | --- | --- |
| `--help` | Print the help message and exit. | N/A | N/A |
| `--renderer` | Choose the rendering algorithm. | `Parallel` (if supported), else `Serial` | `Serial`, `Parallel` |
| `--scene` | Choose the scene to render. | `CornellBox` | `ProceduralSpheres`, `CornellBox`, `Quads`, `Final` |
| `--img-height` | Choose the output image height. | `600` | 0 to 65535 |
| `--img-width` | Choose the output image width. | `600` | 0 to 65535 |
| `--max-bounces` | Choose the max number of ray bounces. | `50` | 0 to 65535 |
| `--samples` | Choose how many times each pixel is sampled. | `200` | 0 to 65535 |
| `--denoiser` | Choose a post-processing denoiser. | `None` | `None`, `JointBilateral`, `ATrous` |
| `--track-progress` | Track the rendering progress. *(Toggle flag)* | `false` | N/A |
| `--time-report` | Log the total rendering time. *(Toggle flag)* | `false` | N/A |
