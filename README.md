# Zig Path Tracer

![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-F7A41D?logo=zig&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

![Cornell Box](images/CornellBox.jpg)

## Introduction & Motivation

This project is a CPU-based Monte Carlo path tracer written in the Zig programming language. It was developed with a dual focus: implementing a global illumination engine from scratch and exploring Zig's capabilities.

Building upon the foundational concepts from the *[Ray Tracing in One Weekend](https://raytracing.github.io/)* series, the codebase shifts away from C++ object-oriented patterns to leverage Zig's procedural design, explicit memory management, and data-oriented structures.

## Features

### Computer Graphics & Rendering
- **Monte Carlo Path Tracing**: Global illumination engine supporting multi-bounce light transport.
- **Geometrical Primitives & Instancing**: Support for spheres, quads, boxes, and spatial transformations (translation and rotation).
- **Bounding Volume Hierarchy (BVH)**: Spatial acceleration structures optimizing ray-geometry intersection queries.
- **Materials**: Physically based light interaction models, including `Lambertian` (diffuse), `Metal` (reflective with fuzziness), `Dielectric` (refractive), and `DiffuseLight` (emissive).
- **Camera Model**: Depth of field and pixel-stratified sampling for anti-aliasing.
- **G-Buffers & Edge-aware Denoising**: Extraction of intermediate surface features (albedo, normals, depth, roughness) for custom Joint Bilateral and À-Trous spatial filters, mitigating Monte Carlo noise at low sample counts.
- **HDR Tone Mapping**: Multiple HDR-to-LDR conversion algorithms (*Reinhard*, *Extended Reinhard*, *Exposure*, and *Gamma Compression*).

### Technical Details
The engine is built around Data-Oriented Design principles and adheres to the *Zen of Zig*, prioritizing explicit control flow, lack of hidden allocations, and optimal memory layouts.

*   **Zero-Cost Polymorphism:** The rendering backend utilizes a Strategy Pattern implemented via tagged unions (`RenderBackend`). By leveraging Zig's `inline else` prongs in the `Renderer.render` orchestrator, dispatching is resolved entirely at compile-time.
*   **Data-Oriented Contexts & State Isolation:** The architecture decouples persistent configuration (`InternalRenderSettings`) from execution state. The execution infrastructure (such as thread pools via `std.Io` and progress tracking via `std.Progress.Node`) and memory buffers (`FrameBuffersRenderView`) are injected into the core algorithms as transient context structs (`RenderContext`, `DenoiserContext`). This isolation makes the renderers stateless and testable.
*   **Explicit Memory Management & Ownership Model:** The engine explicitly manages memory through `std.mem.Allocator`. The `Scene` struct acts as the sole owner of all dynamically allocated entities (like `Material` definitions on the heap), ensuring deterministic cleanup. Geometrical primitives hold non-owning `*const` pointers to these materials, preventing lifetime and double-free issues.
*   **Memory Safety & Views:** The post-processing pipeline exploits Zig's strict mutability rules. Denoisers receive G-Buffer data through a dedicated `GBuffersReadOnly` view, an approach that leverages compile-time type coercion (`[]T` to `[]const T`) to guarantee that complex spatial filters cannot accidentally corrupt G-Buffers during execution.
*   **Split Irradiance & Selective Denoising**: The path tracer inherently separates light transport into diffuse, specular and emission components (`SplitIrradiance` struct). This allows the engine to selectively bypass the spatial denoising passes (Joint Bilateral / A-Trous) for perfectly glossy materials (dielectrics and metals with `fuzz = 0.0`). Since primary G-Buffers represent the physical surface rather than the reflected virtual environment, filtering these pixels would incorrectly blur sharp reflections. Preserving mirror-like finishes while denoising requires more advanced techniques that are not covered in the current implementation.
*   **Comptime Metaprogramming:** Compile-time execution is used to eliminate runtime overhead. For instance, the file system utilities (`fs_utils.zig`) resolve maximum buffer capacities and precisely evaluate PPM header lengths during compilation (`computePpmP6HeaderSize`), bypassing dynamic heap allocations for string formatting in the I/O pipeline.
*   **Zero External Dependencies:** The project relies solely on the Zig standard library.

## Gallery & Performance

*Hardware Note: All benchmarks were executed on an i7-12700KF, compiled in `ReleaseFast` mode.*

### Procedural Spheres Scene
![Procedural Spheres](images/ProceduralSpheres.jpg)
- **Resolution**: 1280x720
- **Samples per Pixel**: 1000
- **Max Bounces**: 50
- **Denoising**: Off
- **Render Time (Parallel)**: 99s

### Cornell Box Scene
![Cornell Box](images/CornellBox.jpg)
- **Resolution**: 800x800
- **Samples per Pixel**: 1000
- **Max Bounces**: 50
- **Denoising**: Off
- **Render Time (Parallel)**: 112s

### Denoising Comparison (Low Sample Count)

To demonstrate the efficiency of the post-processing pipeline, the following renders are generated at extremely low sample counts, where Monte Carlo noise is heavily present.

| 50 Samples (No Filter) | 50 Samples (Joint Bilateral) | 50 Samples (A-Trous) |
| :---: | :---: | :---: |
| ![Raw](images/CornellBox-LowSamples.jpg) | ![Joint Bilateral](images/CornellBox-LowSamples-JointBilateral.jpg) | ![ATrous](images/CornellBox-LowSamples-ATrous.jpg) |
| **Render Time**: 5892ms | **Total Time**: 6481ms | **Total Time**: 6175ms |

### Final Scene
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
