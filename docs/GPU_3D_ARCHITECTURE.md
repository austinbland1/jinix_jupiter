# Jinix Jupiter Fixed-Function 3D Architecture

## Status

Selected by Milestone 10A.

This document is the source of truth for the first bounded Jupiter fixed-function 3D implementation.

## Compatibility Boundary

The existing CPU-visible GPU aperture remains `0x00001100`-`0x000011FF`.

The existing Milestone 5 2D renderer remains a compatibility requirement.

The verified external SDRAM arbiter remains the existing non-preemptive three-master design:

`CPU -> GPU -> DMA -> CPU`

M10 does not add a fourth external-memory master.

A new `jupiter_gpu_3d` child engine will be integrated behind the existing subsystem-visible GPU interface. The 2D renderer and 3D engine share the single GPU SDRAM master through deterministic internal arbitration.

## CPU-Visible Register Map

M10 reserves `0x00001140`-`0x0000117F` for fixed-function 3D control.

| Address | Register | Selected behavior |
| --- | --- | --- |
| `0x1140` | CONTROL | write bit 0 = START; reads zero |
| `0x1144` | STATUS | bit 0 BUSY, bit 1 DONE, bit 2 ERROR |
| `0x1148` | VERTEX_BASE | external-SDRAM address of one triangle record |
| `0x114C` | TEXTURE_BASE | RGB565 texture base |
| `0x1150` | FRAMEBUFFER_BASE | RGB565 framebuffer base |
| `0x1154` | DEPTH_BASE | unsigned 16-bit depth-buffer base |
| `0x1158` | TARGET_SIZE | width bits 15:0; height bits 31:16 |
| `0x115C` | TEXTURE_SIZE | width bits 15:0; height bits 31:16 |
| `0x1160` | MODE | bit 0 texture; bit 1 depth; bit 2 blend |
| `0x1164` | BLEND_ALPHA | integer alpha from 0 through 16 |
| `0x1168` | FLAT_COLOR | RGB565 source color when texture is disabled |

Reserved aligned offsets in the selected 3D subrange read zero and ignore writes.

An accepted START clears DONE and ERROR, snapshots all live configuration, and asserts BUSY.

START while BUSY is ignored.

Live configuration writes while BUSY affect only the next command.

DONE remains sticky until reset or the next accepted START.

An invalid command sets ERROR and DONE and issues no rendering writes.

## Command Scope

One accepted START processes exactly one triangle.

The first implementation does not include a command FIFO or triangle-list walker.

Vertex, texture, framebuffer, and depth resources reside in external SDRAM.

The existing DMA engine remains unchanged and may be used by software to prepare or copy 3D resources.

## Vertex Record

VERTEX_BASE is four-byte aligned.

One triangle contains three consecutive 24-byte post-transform vertices for a total record size of 72 bytes.

Each vertex contains six 32-bit words:

| Word | Attribute | Format |
| --- | --- | --- |
| 0 | screen X | signed Q16.16 pixels |
| 1 | screen Y | signed Q16.16 pixels |
| 2 | depth Z | unsigned U0.16 in bits 15:0 |
| 3 | U over W | signed Q16.16 texel-space value |
| 4 | V over W | signed Q16.16 texel-space value |
| 5 | 1 over W | unsigned nonzero Q16.16 |

Software performs model, view, projection, viewport transformation, and geometric clipping.

The hardware begins with already projected screen-space vertices.

## Triangle Coverage

Counter-clockwise nondegenerate triangles are front-facing.

Clockwise and zero-area triangles generate no pixels and complete normally.

Rasterization walks the integer bounding box clipped to `[0,width)` and `[0,height)`.

Coverage is evaluated at pixel centers `(x + 0.5, y + 0.5)` using signed edge functions.

Shared edges use the top-left rule. Samples exactly on an edge are included only for top or left edges.

The selected rule provides deterministic adjacent-triangle coverage without double filling a shared edge.

No geometric clipping stage exists beyond clipping the raster bounding box to the selected target.

Target width and height are each limited to 1 through 1024.

## Fixed-Point Interpolation

Triangle setup and interpolation use explicitly sized integer and fixed-point arithmetic.

Edge products and weighted interpolation accumulators use at least 64-bit intermediates.

Depth is linearly interpolated in screen space from U0.16 vertex depth.

Perspective texture coordinates are reconstructed from linearly interpolated U/W, V/W, and 1/W.

Perspective division truncates deterministically toward zero.

An interpolated nonpositive 1/W rejects the fragment.

Multiplication operators may infer FPGA DSP resources where synthesis chooses to do so.

M10A makes no DSP-count, utilization, frequency, or timing-closure claim.

## Texture Mapping

Textures are linear row-major RGB565 with two bytes per texel.

Texture width and height are each 1 through 1024 when texture mapping is enabled.

The selected first sampling mode is perspective-correct nearest-neighbor.

Reconstructed U and V are clamped to the valid texture rectangle.

The logical texel address is:

`TEXTURE_BASE + 2 * (v * texture_width + u)`

The external GPU interface remains aligned 32-bit. The required RGB565 texel is selected from the low or high halfword of the aligned read.

Bilinear filtering is deliberately deferred.

## Depth Buffer

The selected depth buffer is linear row-major unsigned 16-bit depth with the same dimensions as the framebuffer.

Zero is nearest and `0xFFFF` is farthest.

When depth testing is enabled, a fragment passes only when:

`new_depth < stored_depth`

Equal depth fails.

A passing fragment writes the interpolated depth.

A failing fragment changes neither framebuffer nor depth.

Depth halfword writes use the corresponding byte lanes of an aligned 32-bit SDRAM transaction.

## Framebuffer and Blending

The framebuffer is linear row-major RGB565.

When texture mapping is disabled, FLAT_COLOR supplies the source fragment color.

When blending is disabled, a passing fragment writes the source RGB565 value directly.

When blending is enabled, the destination RGB565 pixel is read before the write.

BLEND_ALPHA is integer A from 0 through 16.

Each unpacked color channel computes:

`(source*A + destination*(16-A) + 8) >> 4`

The result is clipped to the channel width and repacked as RGB565.

A = 0 preserves the destination.

A = 16 selects the source.

## GPU-Internal SDRAM Arbitration

The verified system-level CPU/GPU/DMA arbiter is unchanged.

2D and 3D may be BUSY simultaneously.

The two graphics engines share the existing GPU SDRAM master through non-preemptive two-way round-robin arbitration.

A granted logical 32-bit transaction remains owned by that engine until `sdram_ready`.

Arbitration changes only between completed transactions.

If only one graphics engine requests, it proceeds without waiting for an artificial turn.

After a contested completion, priority rotates to the other graphics engine.

## Validation

START performs deterministic validation before rendering begins.

Selected command requirements are:

- all used base addresses are four-byte aligned;
- target width and height are each 1 through 1024;
- texture width and height are each 1 through 1024 when texturing is enabled;
- BLEND_ALPHA is from 0 through 16;
- fixed vertex fetch and computed graphics addresses stay within `0x10000000`-`0x17FFFFFF`;
- all three fetched vertex 1/W values are nonzero.

Installed SDRAM may be smaller than the maximum aperture. Software remains responsible for allocating resources within installed capacity. The existing SDRAM frontend keeps its deterministic unavailable-access behavior.

## Memory Safety

The renderer generates aligned 32-bit SDRAM requests.

RGB565 framebuffer and 16-bit depth writes use byte strobes rather than misaligned transactions.

Vertex and texture traffic is read-only.

Framebuffer and depth are the only selected 3D write destinations.

M10 simulation must place sentinels around selected resources and prove unrelated memory remains unchanged.

## Implementation Sequence

### M10B-1 - Integration shell

Add `jupiter_gpu_3d`, 3D MMIO/configuration state, deterministic command errors, and internal 2D/3D SDRAM arbitration. Rendering remains idle. All M5 2D regressions must remain green.

### M10B-2 - Triangle coverage and flat rendering

**Implementation status: complete and fully regressed.**

M10B-2 now implements the first deterministic rendering path selected by
this architecture:

- each accepted command fetches the complete 72-byte triangle record as
  eighteen aligned 32-bit SDRAM reads;
- all three fetched `1/W` values are validated before rasterization;
- signed Q16.16 X/Y coordinates feed a deterministic CCW rasterizer using
  pixel-center sampling, a top-left shared-edge rule, and a target-clipped
  integer bounding box;
- clockwise and degenerate triangles complete normally without covered
  pixels;
- flat RGB565 fragments use aligned 32-bit SDRAM transactions with `0011`
  or `1100` byte strobes for the selected halfword;
- covered fragments are held under backpressure until SDRAM completion, so
  coordinates, address, data, and byte strobes remain stable while stalled;
- the existing external CPU -> GPU -> DMA SDRAM-master contract and M5 2D
  behavior remain unchanged.

The deterministic M10B-2 references cover vertex fetch, shared-edge
ownership without cracks or double fill, clipping, fetch-to-raster
integration, and six-pixel flat framebuffer output. `m10b2-test` is part of
the normal simulation regression, and the complete `make -C sim test`
repository suite passes with M10B-2 registered.

M10C implements the selected 16-bit strict-LESS depth-buffer path described below.


Add vertex fetch, top-left rasterization, target clipping, and flat RGB565 framebuffer writes with deterministic reference coverage.

### M10C - Depth

**Implementation status: complete and fully regressed.**

M10C implements the selected depth-buffer path while preserving the
depth-disabled M10B-2 rendering behavior:

- the raster child screen-linearly interpolates unsigned U0.16 Z from the
  three fetched vertex depths and exports the resulting depth with each
  covered X/Y fragment;
- covered X/Y/Z remain stable under fragment backpressure until the
  fragment transaction is accepted;
- depth-enabled fragments issue one aligned 32-bit read from the selected
  linear 16-bit depth buffer;
- the fragment passes only when `new_depth < stored_depth`; equal and
  farther depth values are rejected;
- a passing fragment updates the selected depth halfword first and then
  writes the RGB565 framebuffer halfword;
- a rejected fragment updates neither depth nor framebuffer;
- halfword depth and framebuffer writes use only `0011` or `1100` byte
  strobes on aligned 32-bit SDRAM transactions;
- two overlapping-triangle draw orders deterministically resolve to the
  nearer triangle;
- the stateful overlap reference observes no accesses outside the selected
  vertex, depth, and framebuffer resources, with framebuffer/depth boundary
  sentinels and an unrelated SDRAM sentinel remaining unchanged.

The deterministic M10C references verify six exact interpolated Z values,
strict-LESS pass/reject behavior including equal-depth rejection, stalled
depth transactions, overlapping geometry in both draw orders, and graphics
memory safety. `m10c-test` is part of the normal simulation regression, the
Milestone 5 compatibility suite passes, and the complete `make -C sim test`
repository regression passes with M10C registered.

### M10D - Perspective Texture Mapping and Blending

**Implementation status: complete and fully regressed.**

M10D implements the selected texture-mapping and blending paths while
preserving the previously verified flat-color and strict-LESS depth
behavior:

- the raster child linearly interpolates signed Q16.16 `U/W` and `V/W`
  plus unsigned Q16.16 `1/W` from the three fetched vertex records;
- the complete X/Y/Z, `U/W`, `V/W`, and `1/W` fragment payload remains
  stable under valid/ready backpressure;
- perspective reconstruction computes Q16.16 U and V by dividing the
  interpolated value-over-W by interpolated `1/W`, with signed division
  truncating toward zero;
- texture-enabled fragments reject a zero interpolated `1/W` before any
  depth or framebuffer state is modified;
- nearest-neighbor texture selection uses the integer portion of the
  reconstructed coordinates and clamps each coordinate to the selected
  texture rectangle;
- RGB565 textures remain linear row-major resources accessed only through
  aligned 32-bit read-only SDRAM transactions with the selected 16-bit
  texel extracted from the appropriate halfword;
- texture-disabled rendering continues to use the snapshotted flat RGB565
  color;
- blend-enabled fragments read the selected framebuffer halfword and apply
  the documented per-channel formula
  `(src*A + dst*(16-A) + 8) >> 4` for R5, G6, and B5 independently;
- blend alpha zero preserves the destination, alpha sixteen selects the
  source, and alpha eight matches the deterministic rounded half-blend
  references;
- depth, texture, and blending compose in deterministic transaction order:
  depth read, strict-LESS decision, depth write on pass, optional texture
  read, optional framebuffer destination read/blend, then framebuffer
  write;
- depth rejection suppresses all later texture, blend, and framebuffer
  traffic for that fragment;
- texture memory is never written, framebuffer/depth halfword writes retain
  their aligned `0011`/`1100` byte strobes, and accesses remain restricted
  to the selected vertex, texture, framebuffer, and depth resources.

The deterministic M10D references verify six exact perspective-correct
fragments, nearest texture selection including a case that differs from
affine interpolation, exact RGB565 blend results, alpha endpoints,
backpressured texture/framebuffer transactions, and a stateful
texture+depth+blend command with exact transaction ordering.

The composed reference performs 18 vertex reads, six depth reads, three
strict-LESS depth writes, three texture reads, three framebuffer reads,
and three framebuffer writes. Three depth-rejected fragments produce no
texture or framebuffer traffic. It reports zero transaction-sequence
errors, zero illegal accesses, zero boundary-sentinel accesses, legal
alignment/strobes throughout, and all nine graphics-memory sentinels
intact.

`m10d-test` is registered in the normal simulation regression and runs the
perspective, texture, blending, and composed references. The complete
Milestone 5 compatibility suite passes, and the full `make -C sim test`
repository regression passes with the real M10D Icarus Verilog commands
registered.

M10E performs final Milestone 10 acceptance, shared-memory contention
coverage, and full milestone closeout.

### M10D - Perspective texture and blending

Add perspective-correct nearest RGB565 texture sampling and constant-alpha source-over blending with exact reference pixels.

### M10E - Integrated acceptance

Exercise simultaneous 2D/3D operation, GPU/DMA contention, reference rendering, M5 regression, the full repository suite, and Milestone 10 closeout.

## Explicit Non-Goals

The first M10 implementation does not include a transform engine, lighting, geometric clipping, triangle lists, command FIFOs, bilinear or anisotropic filtering, mipmapping, texture compression, stencil buffering, multisampling, programmable shaders, floating-point rasterization, or real-hardware throughput guarantees.
