# Jupiter M11B Framebuffer Scanout Architecture

## 1. Scope and Status

This document selects the initial live framebuffer-scanout architecture for
Milestone 11B.

**Architecture status: selected; RTL implementation pending.**

Milestones 5 and 10 already provide deterministic 2D and 3D rendering into
linear RGB565 framebuffers in external SDRAM. M11B connects a selected
framebuffer to the live MiSTer-facing video path.

The design prioritizes:

- deterministic behavior;
- preservation of already verified CPU/GPU/DMA arbitration;
- a bounded and testable initial display mode;
- clean separation between rendering and display ownership;
- deterministic failure behavior when display data misses its deadline; and
- no unsupported claim of physical SDRAM/video throughput before hardware
  validation.

## 2. Existing Integration Boundary

Before M11B, `jupiter_system` obtains its visible timing and pixel data from
the inherited `mycore video_demo`.

`Template.sv` forwards that boundary to MiSTer using:

- `CLK_VIDEO = clk_sys`;
- `CE_PIXEL = ce_pix`;
- H/V sync and blanking from `jupiter_system`; and
- 8-bit video intensity expanded into the MiSTer RGB outputs.

The rendered Jupiter framebuffer is therefore not yet the live display.

M11B replaces the demo producer while preserving the existing MiSTer-facing
clock/timing style.

## 3. Selected Display Surface

The initial live Jupiter display surface is:

- RGB565;
- linear row-major storage;
- external SDRAM;
- maximum displayed width: 320 pixels;
- maximum displayed height: 240 pixels;
- one 16-bit source pixel per logical display pixel.

The selected source width must be even so each SDRAM fetch supplies exactly
two complete RGB565 pixels.

Valid programmed dimensions are therefore:

- width: 2 through 320 pixels, even only;
- height: 1 through 240 pixels.

Pixels within the 320 x 240 active display area but outside the programmed
source width or height are black.

No scaling, filtering, rotation, palette conversion, or arbitrary stride is
selected for the initial scanout engine.

## 4. CPU-Visible Display Registers

The existing GPU aperture is `0x00001100-0x000011FF`.

M11B selects the previously unused range:

`0x00001180-0x000011BF`

for display/scanout control.

Selected registers are:

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| `0x1180` | `DISPLAY_CONTROL` | R/W | bit 0 ENABLE; bit 1 write-one CLEAR_UNDERFLOW |
| `0x1184` | `DISPLAY_STATUS` | R | bit 0 ACTIVE; bit 1 UNDERFLOW |
| `0x1188` | `DISPLAY_BASE` | R/W | external-SDRAM RGB565 framebuffer base |
| `0x118C` | `DISPLAY_SIZE` | R/W | width bits 15:0; height bits 31:16 |

Aligned addresses from `0x1190` through `0x11BC` are reserved.

Reserved reads return zero and reserved writes are ignored.

`DISPLAY_BASE` must be 4-byte aligned.

The complete selected framebuffer range must fit inside installed,
CPU-visible Jupiter external SDRAM.

Invalid enabled configuration does not issue scanout SDRAM traffic and
produces black active video.

## 5. Shadow and Active Display Configuration

CPU writes update shadow display configuration.

The scanout engine snapshots the shadow configuration at the beginning of
vertical blank for use by the following visible frame.

Therefore:

- writes during an active frame do not alter the frame already being shown;
- framebuffer-base changes may be used for software-controlled page flipping;
- writes after the vertical-blank snapshot take effect one frame later; and
- reset clears both shadow and active configuration.

`DISPLAY_STATUS.ACTIVE` reports that the currently snapshotted configuration
is enabled and valid.

## 6. Video Timing

The scanout engine remains synchronous to the existing 20 MHz `clk_sys`.

`CLK_VIDEO` remains `clk_sys`.

For the normal non-scandoubled mode, `CE_PIXEL` alternates so the raster
advances at an effective 10 MHz pixel rate.

For scandoubled mode, `CE_PIXEL` is asserted every `clk_sys` cycle and each
source framebuffer row is presented twice vertically.

M11B keeps the existing 638-position horizontal raster period and existing
MiSTer-compatible sync placement:

- horizontal count: 0 through 637;
- HSync asserts at horizontal count 544;
- HSync deasserts at horizontal count 590.

The selected visible horizontal region is 320 pixels:

- active horizontal counts: 0 through 319;
- HBlank begins at count 320.

The initial Jupiter framebuffer source is always at most 240 lines high.

For non-PAL timing:

- vertical total is 262 raster lines;
- the 240-line Jupiter active region occupies source lines 0 through 239;
- VBlank begins after the 240-line active region;
- the existing non-PAL VSync placement is retained.

For PAL timing:

- the inherited PAL total/sync cadence is retained;
- only the first 240 source lines form the selected Jupiter active image;
- remaining PAL raster time is blank;
- no separate 300-line Jupiter framebuffer format is selected.

In scandoubled mode, each logical Jupiter source row is emitted on two raster
rows before advancing to the next source row.

## 7. RGB565 Expansion

The scanout engine converts each RGB565 source pixel to 8-bit MiSTer color
channels using deterministic bit replication.

For source components:

- `R5 = pixel[15:11]`;
- `G6 = pixel[10:5]`;
- `B5 = pixel[4:0]`.

Output conversion is:

- `R8 = {R5, R5[4:2]}`;
- `G8 = {G6, G6[5:4]}`;
- `B8 = {B5, B5[4:2]}`.

Blanked or unavailable pixels output RGB zero.

The inherited demo-only color-selection behavior is not part of the Jupiter
framebuffer format.

## 8. Line-Buffer Architecture

The initial scanout engine uses two internal 320-pixel RGB565 line buffers.

One buffer is displayed while the other buffer is available for SDRAM
prefetch.

For a full 320-pixel source line, one prefetch requires exactly:

- 160 aligned 32-bit SDRAM reads;
- two RGB565 pixels captured from each read; and
- no SDRAM writes.

For a narrower valid source line, the read count is exactly `width / 2`.

The next required source line is prefetched before it is selected for active
display.

Scandoubled output reuses the same completed source-line buffer for the second
physical raster row and does not reread that source line merely because it is
displayed twice.

## 9. Underflow Behavior

If the required source line is not completely available when that line must
begin display:

- the affected source line is output as black;
- no partially fetched line is displayed;
- `DISPLAY_STATUS.UNDERFLOW` becomes sticky; and
- scanout continues deterministically rather than stalling video timing.

Writing one to `DISPLAY_CONTROL.CLEAR_UNDERFLOW` clears the sticky underflow
flag without changing ENABLE or the programmed framebuffer configuration.

Reset also clears UNDERFLOW.

This provides a deterministic simulation-visible indication of insufficient
memory service without claiming that the selected physical hardware has
already demonstrated the required bandwidth.

## 10. Selected SDRAM Integration

M11B does **not** extend or rewrite the verified Milestone 6
`jupiter_sdram_arbiter` CPU/GPU/DMA policy.

The existing arbiter remains the first arbitration stage and continues to
combine:

- CPU;
- GPU; and
- DMA

into one aggregate normal-memory master.

M11B adds a second module:

`rtl/memory/jupiter_sdram_scanout_arbiter.sv`

between that aggregate normal master and `jupiter_sdram_frontend`.

The second-stage arbiter has exactly two requesters:

1. aggregate normal CPU/GPU/DMA traffic; and
2. framebuffer scanout.

This preserves the existing CPU/GPU/DMA arbiter implementation and its
hierarchically inspected grant encodings.

## 11. Second-Stage Arbitration Policy

The normal/scanout arbiter is deterministic, non-preemptive, two-way
round-robin arbitration.

A selected logical 32-bit transaction remains selected until the SDRAM target
asserts `ready`.

No requester can replace an in-flight transaction.

When both requesters remain continuously active, completed contested
transactions alternate:

`SCANOUT -> NORMAL -> SCANOUT -> NORMAL -> ...`

Reset initializes contested preference so scanout wins the first contested
free arbitration point.

When scanout is idle, normal CPU/GPU/DMA traffic passes through the
second-stage arbiter without changing the existing first-stage winner policy.

When normal traffic is idle, scanout may issue consecutive reads.

This policy gives both sides deterministic forward progress under sustained
contention instead of allowing either side to starve the other.

## 12. Scanout SDRAM Transaction Rules

The scanout master is read-only.

Every scanout transaction uses:

- aligned 32-bit address;
- `write = 0`;
- `wdata = 0`;
- `wstrb = 0000`.

For source coordinate `(x,y)` where `x` is even, the aligned read address is:

`DISPLAY_BASE + 2 * (y * width + x)`

The low RGB565 halfword contains pixel `x`.

The high RGB565 halfword contains pixel `x + 1`.

The scanout engine must not issue a read outside the validated active
framebuffer allocation.

## 13. Integration Placement

`jupiter_video_scanout` is selected as an independent subsystem rather than a
modification of either renderer.

The planned RTL path is:

`rtl/video/jupiter_video_scanout.sv`

The existing Jupiter GPU target aperture remains routed by the production
interconnect.

Inside `jupiter_cpu_subsystem`, addresses in `0x1180-0x11BF` are subdecoded to
the scanout module.

Other GPU-aperture accesses continue to the existing `jupiter_gpu_2d`
wrapper, including its child 3D engine.

The scanout module provides:

- its own read-only SDRAM master;
- `ce_pix`;
- HBlank/HSync;
- VBlank/VSync; and
- 8-bit R/G/B output channels.

`jupiter_system` propagates those outputs instead of instantiating
`mycore video_demo`.

`Template.sv` maps the three Jupiter color channels directly to MiSTer
`VGA_R`, `VGA_G`, and `VGA_B`.

## 14. Reset Behavior

Reset:

- disables active scanout;
- clears shadow and active display configuration;
- clears UNDERFLOW;
- clears both line-buffer validity states;
- cancels any not-yet-issued scanout fetch progression;
- returns raster counters to their deterministic initial state; and
- produces black active video until a valid enabled configuration is
  snapshotted.

The SDRAM arbitration hierarchy must also return to its documented reset
preference.

## 15. Deterministic Verification Requirements

M11B verification must include at least:

1. reset produces deterministic black video and no scanout SDRAM traffic;
2. display MMIO implements the exact selected register behavior;
3. reserved display MMIO reads zero and writes are ignored;
4. invalid display dimensions generate no scanout traffic;
5. invalid or out-of-installed-SDRAM framebuffer ranges generate no scanout
   traffic;
6. shadow display configuration changes only at the selected vertical-blank
   snapshot boundary;
7. one known RGB565 line produces exact aligned SDRAM reads;
8. one known RGB565 line produces exact RGB888-expanded pixels;
9. full-width scanout performs exactly 160 reads per source line;
10. narrower valid lines perform exactly `width / 2` reads;
11. SDRAM requests remain stable under backpressure;
12. scandoubled output reuses each source line without duplicate line fetches;
13. incomplete line fetch causes deterministic black-line underflow;
14. UNDERFLOW is sticky until reset or explicit clear;
15. normal/scanout arbitration holds an in-flight transaction until ready;
16. sustained normal/scanout contention alternates completed contested wins;
17. scanout never writes SDRAM;
18. scanout never accesses outside its validated framebuffer;
19. existing CPU/GPU/DMA arbitration behavior remains unchanged when scanout
    is idle;
20. CPU-visible display MMIO works through the production interconnect;
21. `jupiter_system` obtains live timing/color from Jupiter scanout rather
    than `mycore video_demo`;
22. known framebuffer pixels propagate through the production system video
    boundary; and
23. all previously passing milestone regressions remain passing.

All tests must report deterministic PASS/FAIL status automatically.

## 16. Planned RTL and Test Files

Selected new production RTL:

- `rtl/video/jupiter_video_scanout.sv`;
- `rtl/memory/jupiter_sdram_scanout_arbiter.sv`.

Selected new primary simulation files:

- `sim/jupiter_video_scanout_tb.sv`;
- `sim/jupiter_sdram_scanout_arbiter_tb.sv`.

Additional integration tests may be added as required by implementation.

`files.qip` must register both new production RTL files before M11B is
considered integrated.

## 17. Compatibility Requirements

M11B must preserve all previously verified behavior when the new scanout
engine is disabled or idle.

In particular:

- the Milestone 6 CPU/GPU/DMA arbiter remains source-compatible and
  behaviorally unchanged;
- 2D rendering remains unchanged;
- 3D rendering remains unchanged;
- DMA remains unchanged;
- CPU-visible existing addresses retain their meanings;
- audio/controller behavior remains unchanged; and
- the M11A rule that normal Jupiter game logic remains FPGA-side is unchanged.

## 18. Explicit Non-Claims

Selection or simulation completion of M11B does not by itself establish:

- Quartus synthesis success;
- fitter success;
- timing closure;
- FPGA resource usage;
- physical SDRAM bandwidth sufficiency;
- absence of real-hardware scanout underflow;
- physical PAL/NTSC display compatibility; or
- successful operation on SuperStation One / MiSTer-compatible hardware.

Those claims require the real validation evidence defined by Milestone 11.

## 19. M11B Implementation Boundary

M11B implementation is complete only when:

- the demo-video producer has been replaced by Jupiter framebuffer scanout;
- the selected display MMIO is reachable through the production CPU path;
- the line-buffer fetch path operates through the selected second-stage SDRAM
  arbiter;
- deterministic standalone and integrated simulation tests pass;
- prior regressions remain green; and
- release/known-limitations documentation is updated to accurately describe
  the resulting implemented state.

Milestone 11 acceptance checkboxes remain unchanged until later closeout
demonstrates their exact criteria.
