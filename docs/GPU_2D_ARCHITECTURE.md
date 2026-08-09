# Jupiter Milestone 5 2D Graphics Architecture

## 1. Scope and Status

This document selects the initial hardware-assisted 2D graphics architecture
for Milestone 5.

It defines the functional design to be implemented and verified in simulation.
It does not establish Quartus synthesis results, timing closure, FPGA resource
usage, memory-bandwidth performance, or successful operation on physical
hardware.

Milestone 5 builds on the CPU transaction architecture from Milestones 2 and 3
and the external-SDRAM path established in Milestone 4.

## 2. Selected Initial 2D Feature Subset

Milestone 5 selects the following initial graphics features:

- one hardware tile/background renderer;
- 8 x 8 pixel tiles;
- direct-color RGB565 tile pixels;
- one tilemap layer;
- row-major tilemap organization;
- programmable tilemap base address;
- programmable tile-data base address;
- programmable framebuffer base address;
- programmable width and height in tiles;
- CPU-controlled render start;
- CPU-readable busy/completion state;
- rendering into a linear RGB565 framebuffer in external SDRAM.

The first implementation is intentionally bounded.

The following architectural targets are not selected for the initial
Milestone 5 implementation:

- sprites;
- scrolling;
- palette or palette-RAM rendering;
- blending;
- affine effects;
- general-purpose blitter operations;
- color-keying;
- logical raster operations;
- DMA;
- fixed-function 3D graphics.

Their omission does not prevent Milestone 5 completion.

## 3. Display Boundary

Milestone 5 does not replace the existing `mycore` live-video path.

`mycore` remains the active producer of the current template pixel-enable,
blanking, synchronization, and video outputs while the first Jupiter 2D
renderer is developed and verified.

The Milestone 5 GPU produces a rendered RGB565 framebuffer in external SDRAM.
Simulation compares that framebuffer with deterministic expected image data.

This separates verification of Jupiter rendering and graphics-memory behavior
from later live-display timing, scanout-bandwidth, and physical-video concerns.

No live-video throughput or hardware-display performance is claimed by this
milestone.

## 4. CPU-Visible Graphics Register Region

Milestone 5 selects the following GPU MMIO aperture:

    0x00001100 - 0x000011FF

This region does not overlap the existing internal RAM, MMIO scratch register,
or external-SDRAM aperture.

The base address `0x00001100` is also directly constructible with the current
signed 14-bit `ADDI` immediate.

Only the registers explicitly defined below have state in the first
implementation. Other aligned addresses within the GPU MMIO aperture return
zero on reads and ignore writes while completing deterministically.

### 4.1 Register Map

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `CONTROL` | W | Bit 0 starts one render operation when idle |
| `0x04` | `STATUS` | R | Bit 0 = busy, bit 1 = done |
| `0x08` | `TILEMAP_BASE` | R/W | External-SDRAM tilemap base address |
| `0x0C` | `TILEDATA_BASE` | R/W | External-SDRAM tile-data base address |
| `0x10` | `FRAMEBUFFER_BASE` | R/W | External-SDRAM framebuffer base address |
| `0x14` | `MAP_SIZE` | R/W | Bits 7:0 = width in tiles; bits 15:8 = height in tiles |

All reserved bits read as zero.

Base addresses used by the renderer are 4-byte aligned system byte addresses.

A write of one to `CONTROL.START` while the renderer is idle snapshots the
configuration registers and begins one render operation.

A start request while the renderer is already busy is ignored.

`STATUS.BUSY` remains asserted while the operation is active.

`STATUS.DONE` is cleared when a new operation begins and is asserted when that
operation completes. Reset clears both status bits.

A width or height of zero completes without issuing a graphics-memory
transaction.

## 5. Graphics Memory Organization

Graphics buffers reside in the installed and available portion of the
Milestone 4 external-SDRAM aperture:

    0x10000000 - 0x17FFFFFF

The register interface does not impose a permanent partition of SDRAM into
graphics and non-graphics regions.

Software selects the tilemap, tile-data, and framebuffer locations.

The existing SDRAM frontend remains the final installed-capacity and
availability gate.

### 5.1 Tilemap Entries

The tilemap is row-major.

Each tilemap entry occupies one aligned 32-bit word.

For the initial implementation:

- bits 15:0 contain an unsigned tile index;
- bits 31:16 are reserved and ignored.

Tilemap entry address:

    TILEMAP_BASE + ((tile_y * width_tiles + tile_x) * 4)

### 5.2 Tile Data

Each tile is 8 x 8 pixels.

Each pixel is RGB565 and occupies 16 bits.

A tile therefore occupies:

    8 * 8 * 2 = 128 bytes

Tiles are packed consecutively beginning at `TILEDATA_BASE`.

Tile address:

    TILEDATA_BASE + (tile_index * 128)

Each tile row occupies 16 bytes, represented as four aligned 32-bit words.

Within each 32-bit tile-data word:

- bits 15:0 contain the left RGB565 pixel;
- bits 31:16 contain the right RGB565 pixel.

This organization allows the renderer to copy two adjacent RGB565 pixels per
32-bit graphics-memory transaction.

### 5.3 Framebuffer

The framebuffer is linear, tightly packed RGB565.

Two horizontally adjacent pixels occupy each aligned 32-bit framebuffer word.

For a map width of `width_tiles`, one rendered pixel row occupies:

    width_tiles * 8 * 2 bytes

or equivalently:

    width_tiles * 16 bytes

The rendered image dimensions are:

    width_pixels  = width_tiles  * 8
    height_pixels = height_tiles * 8

No display resolution or throughput guarantee is implied by these programmable
dimensions.

## 6. Rendering Operation

The renderer processes the tilemap in row-major tile order.

For each tile:

1. read the 32-bit tilemap entry;
2. extract the tile index;
3. for tile rows 0 through 7:
   - read four 32-bit RGB565 words from the selected tile row;
   - write those four words to the corresponding framebuffer location.

The initial renderer performs no pixel blending, palette lookup, scrolling,
affine transformation, sprite composition, or other per-pixel operation.

Its first useful operation is deterministic expansion of a tilemap and tile
set into a linear RGB565 image.

Only framebuffer addresses are written by the renderer.

Tilemap and tile-data accesses are read-only.

## 7. SDRAM Master Architecture

Milestone 4 has one Jupiter transaction master using external SDRAM: the CPU.

Milestone 5 adds the 2D GPU as a second external-SDRAM transaction master.

This does not implement the Milestone 6 DMA engine.

Both CPU and GPU use the established 32-bit Jupiter transaction shape:

- valid;
- write;
- 32-bit byte address;
- 32-bit write data;
- four write strobes;
- 32-bit read data;
- ready.

The two masters are arbitrated before the existing
`jupiter_sdram_frontend`.

The frontend and physical SDRAM controller remain shared.

The halfword interface between the frontend and controller is not a
multi-master arbitration point because one logical Jupiter 32-bit transaction
is translated into an ordered pair of 16-bit controller transactions.

## 8. SDRAM Arbitration Policy

Milestone 5 selects a two-master, non-preemptive round-robin SDRAM arbiter.

The masters are:

1. CPU SDRAM requests;
2. GPU SDRAM requests.

Arbitration occurs only at Jupiter 32-bit transaction boundaries.

Once a master is granted:

- its request remains selected until the shared SDRAM frontend asserts ready;
- the other master cannot interrupt the in-progress transaction;
- request address, direction, write data, and write strobes remain associated
  with the granted master until completion.

When both masters request while the arbiter is free, the master that did not
win the previous contested completed transaction receives the next grant.

After reset, the first contested grant goes to the CPU. Thereafter only a
completed transaction that began as a contested grant changes the contested
round-robin history. Uncontested transactions do not change which master wins
the next contested grant.

When only one master requests, that master is granted without waiting for the
other master.

This policy provides deterministic progress for both current masters without
introducing DMA functionality.

Any future change to the master set or arbitration policy requires updated
documentation and deterministic arbitration tests.

## 9. CPU MMIO versus Graphics-Memory Traffic

CPU writes to GPU control registers remain ordinary CPU interconnect target
transactions.

They do not pass through the SDRAM arbiter.

Only CPU accesses to the external-SDRAM aperture compete with GPU
graphics-memory transactions.

A render command snapshots its configuration registers before issuing GPU
memory requests, so subsequent CPU writes to configuration registers do not
alter an operation already in progress.

Software should not intentionally modify graphics buffers that are actively
being consumed or produced by the renderer unless later architecture defines
such synchronization behavior.

## 10. Memory Safety Requirements

The renderer must never write tilemap or tile-data memory.

Its only graphics-memory writes are framebuffer writes derived from the
snapshotted framebuffer base and current render coordinates.

Automated tests must place known guard data around graphics buffers and verify
that rendering leaves unrelated memory unchanged.

The existing SDRAM frontend remains responsible for deterministic handling of
unavailable, misaligned, or out-of-installed-capacity SDRAM transactions.

No graphics operation may bypass that frontend.

## 11. Initial RTL Organization

The selected organization is:

- `rtl/gpu/jupiter_gpu_2d.sv`
  - CPU-visible GPU registers;
  - render-control state;
  - tile renderer;
  - GPU 32-bit SDRAM-master interface.

- `rtl/memory/jupiter_sdram_arbiter.sv`
  - CPU/GPU two-master transaction arbitration;
  - one shared 32-bit target interface toward `jupiter_sdram_frontend`.

Existing Milestone 4 SDRAM frontend and controller modules remain responsible
for logical-width conversion, installed-memory validation, initialization,
refresh, and physical SDRAM commands.

The existing `jupiter_gpu_stub` remains only until the functional GPU module
supersedes its placeholder role.

## 12. Deterministic Verification Plan

Milestone 5 verification will include focused automated tests for:

1. GPU register reset values;
2. CPU-visible register reads and writes;
3. start, busy, and done behavior;
4. deterministic handling of unused GPU MMIO offsets;
5. GPU MMIO interconnect routing without target overlap;
6. CPU/GPU SDRAM arbitration;
7. request stability while the shared SDRAM path is stalled;
8. non-preemptive completion of granted 32-bit transactions;
9. round-robin behavior for simultaneous CPU/GPU requests;
10. tilemap address generation;
11. tile-data address generation;
12. framebuffer address generation;
13. deterministic rendering of a small known tile image;
14. complete expected-framebuffer comparison;
15. tilemap and tile-data preservation;
16. guard-memory preservation around the framebuffer;
17. CPU configuration followed by end-to-end GPU rendering through the
    Milestone 4 SDRAM frontend and controller;
18. regression of previously verified CPU, memory, SDRAM, and wrapper behavior.

The primary deterministic image regression may use a deliberately small map
such as 2 x 2 tiles so every resulting RGB565 framebuffer word can be checked
without making a performance claim.

## 13. Explicit Milestone 5 Non-Claims

Completion of the selected initial 2D implementation will not by itself claim:

- Quartus synthesis success unless Quartus is actually run;
- timing closure;
- FPGA resource utilization;
- a guaranteed renderer throughput;
- a guaranteed maximum image size;
- sufficient external-memory bandwidth for live scanout;
- successful physical SDRAM operation;
- successful SuperStation One video output;
- completion of sprites, scrolling, palettes, blending, affine effects,
  general blitting, DMA, or 3D rendering.

Those claims or features require their own evidence or later milestone work.
