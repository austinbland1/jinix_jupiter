# Jinix Jupiter — MiSTer FPGA Core Architecture

<!--
 DO NOT CONFIRM THIS SECTION AS ACCURATE WITHOUT ACTUALLY READING THE SOURCE.
 These are PROPOSED elements for a core that does not yet exist in this repo.
-->

## Table of Contents

1. [Verified Facts](#verified-facts)
2. [Proposed Jinix Jupiter Architecture](#proposed-jinix-jupiter-architecture)
3. [Unresolved Questions](#unresolved-questions)

---

## Verified Facts

### Source of Truth

The repository currently contains a minimal MiSTer FPGA "empty core" template.
All verified facts below are derived from reading the actual source files:
`Template.sv`, `sys_top.v`, `emu_ports.vh`, `hps_io.sv`, `pll.v`, `files.qip`,
and `rtl/mycore.v`.

### Quartus Top-Level Entity: `sys_top`

- `sys_top` in `Template.qsf` (via `VERILOG_FILE`) is the top-level entity of the Quartus project.
- It exposes all board pins: clocks (50 MHz), HDMI, SDRAM, VGA, audio, and the HPS I/O bus that connects to the MiSTer framework.

### Core-Facing Interface: `emu` Module

- The module `emu` is DEFINED in `Template.sv` and abstracts all MiSTer-system signals from the perspective of user RTL in `rtl/`.
- It forwards clock, reset, and video/blanking/sync signals to core logic placed by the developer.
- Core writers should not directly instantiate `sys_top`; they instantiate `emu` and implement `mycore.v`-style logic.

### `hps_io`: MiSTer Framework Bridge

- `hps_io.sv` (from `sys/`) provides the MiSTer HPS/core communication interface, handling all exchange between core and MiSTer's host framework. It decodes:
 - **Digital joystick input** — six framework ports, each exposing a 32-bit state word.
 - **Analog joystick axes** — framework capability exists, but analog input is not selected for the initial Milestone 8 Jupiter interface.
 - **OSD configuration options** — user-selectable settings via a `CONF_STR` parameter passed during instantiation.
 - **Core state save / restore** — binary snapshot of internal registers to MiSTer flash storage.
- Reset to core logic is asserted when `RESET | status[0] | buttons[1]`.

### Clock: 50 MHz Input → Core PLL

- The board provides a 50 MHz reference on `FPGA_CLK1_50`.
- A PLL instantiates via `pll.v` (Altera MegaWizard, Cyclone V family) and produces `clk_sys`, the global system clock fed to both `hps_io` and the user core.
- This is the single clock domain for all MiSTer framework logic unless the core independently generates additional clocks.

### Existing Video Path (as instantiated in the template)

The template video chain flows as follows:

1. **Core output:** `mycore.v` drives an 8-bit parallel video bus (`video[7:0]`) and horizontal/vertical blanking signals (`HBlank`, `VBlank`).
2. **Video routing to SCART/RGb pins:**
 - `VGA_DE = ~(HBlank | VBlank)` — display enable goes high during active pixels.
 - `VGA_HS` driven from core `HSync`.
 - `VGA_VS` driven from core `VSync`.
3. **Color channel mapping from the 8-bit video word:**

| Color Index (`col`) | R | G | B | Visual  |
|---------------------|---|---|---|--------|
| 0 | video | video |  video | White-on-black |
| 1 | video | '0 | '0 | Red-only |
| 2 | '0 |  video | '0 | Green-only |
| 3 | '0 | '0 | video | Blue-only |

4. Color channels are 8-bit per channel (`VGA_R[7:0]`, `VGA_G[7:0]`, `VGA_B[7:0]`). Template.sv drives the full 8-bit video value into these outputs.
5. **Audio:** Both `AUDIO_L` and `AUDIO_R` are tied to `'0`. Audio is entirely disabled in the template.

### SDRAM / DDR Interfaces

- The template currently drives the primary external `SDRAM_*` pins to `'Z`
  because the Jupiter SDRAM controller has not yet reached top-level
  integration.
- `sys/emu_ports.vh` exposes the primary low-latency external SDR SDRAM
  interface, including a 16-bit `SDRAM_DQ` bus, address and bank signals,
  byte masks, clock/enable, and SDRAM command signals.
- MiSTer framework files provide the board-level primary SDRAM pin
  assignments and related I/O constraints.
- The separate `DDRAM_*` interface is the HPS DDR3 transaction path and is
  not the external-memory interface selected for Jupiter Milestone 4.
- `hps_io` exposes `sdram_sz`, which reports availability and supported
  32 MiB, 64 MiB, or 128 MiB external-SDRAM sizes.
- Milestone 4 selects a Jupiter-owned controller under `rtl/memory/` that
  will drive the primary `SDRAM_*` interface.
- The selected controller architecture is documented in
  `docs/SDRAM_ARCHITECTURE.md`.

### `files.qip`: Core HDL Source Registration

- `files.qip` is the Quartus project file list where all core-developer HDL files are registered.
- Template content:

```
rtl/lfsr.v
rtl/cos.sv
rtl/mycore.v
Template.sdc
Template.sv
```
- Core developers append Verilog/SystemVerilog files here; they are **not** automatically included.

### Framework Files in `sys/`

The `sys/` directory contains platform infrastructure provided by MiSTer:

| File  (basename) | Role |
|-----------------|------|
| `sys_top.v` | Quartus  top-level module — pin assignments, clock distribution, subsystem  interconnect. |
| `hps_io.sv` | MiSTer HPS/core  communication interface — config, joysticks, buttons, OSD menu,  state save/restore. |
| `rtl/pll.v` | Cyclone V PLL wrapper used by `Template.sv`; its `outclk_0` drives the current 20 MHz `clk_sys` from the 50 MHz `CLK_50M` reference. |
| `video_cleaner.sv` | Optional video scaling/format  correction in the sys chain. |
| `scandoubler.v` | Scan-line doubler  pass-through for CRT outputs. |
| `shadowmask.sv` | Pseudo-color  effects via shadow-mask filtering. |
| `hq2x.sv` | HQ-style 2×  upscaler for LCD outputs. |
| `osd.v` | On-screen display overlay logic  (menu rendering). |
| `i2c.v` / `alsa.sv` | I2C peripheral and ALSA  audio interface support. |
| `i2s.v` / `spdif.v` | I²S and S/PDIF  digital audio output paths. |
| `audio_out.sv` | Audio DAC output  wrapper combining multiple audio sources. |
| `f2sdram_safe_terminator.sv` | MiSTer framework support for the FPGA-to-HPS SDRAM interface; not selected as Jupiter's external SDR SDRAM controller. |

---

<!--
  ===================================================================
  PROPOSED ARCHITECTURE — NOT VERIFIED FROM SOURCE
  ===================================================================
  Everything below this marker is a DESIGN PROPOSAL for the Jinix Jupiter
 core. No RTL exists in this repository to confirm these claims.
 Performance numbers, bus widths, register counts, etc., are proposals only.
 -->

## Proposed Jinix Jupiter Architecture

### System Overview

Jinix Jupiter is proposed as a MiSTer FPGA core emulating a dedicated arcade/entertainment system built around the following blocks:

```
  ┌───────────────────────────────────────┐
  │ SYSTEM BUS │
 │ (proposed 32-bit / 16-pin address)  │
  ┌─────────────┼───────────────────────────────────────┤
  │ │ │ │
 ▼ ▼ ▼  ▼
┌───────────┐   ┌──────────┐   ┌─────────────┐   ╔═════════════╗
│  CPU (core) │ │ GPU/2D │ │ DMA Ctrl │ ║  SDRAM (ext)║
│ 32-bit │ │ Blitter │ │  ║  ╚═════════════╝
└───────────┘   └──────────┘   └──────┬──────╢  Audio Codec
 │  ╚═════════════╝
   ┌────────────────────┼───────┐
  ▼ ▼ │
  ╔══════════╗   ╔══════════╗  │
 │ GPU Reg. ║ │ Audio Reg│ │
  ╚══════════╝   ╚══════════╝  │
 ───────┘
 Controller  I/O  ◄───────────────►  hps_io (MiSTer framework)
 ←──────  emu module ──→ sys_top
```

### Custom 32-bit RISC CPU

**PROPOSED.** No functional CPU RTL exists in the current repository; Milestone 1 provides only a boundary placeholder. A custom 32-bit RISC CPU is a design target for Jupiter.

- Architecture: custom 32-bit RISC — instruction set architecture, register-file depth, and pipeline structure remain TBD.
- Pipeline: stage count and microarchitecture are TBD (not yet finalized).
- Clock domain: clock sources and frequency division remain TBD; resets routed through TBD control path.
- Registers: register-file design (capacity, access width) is TBD.

### System Bus

**MILESTONE 3 SELECTED.** Jupiter's internal transaction mechanism uses the
existing CPU `mem_valid` / `mem_ready` interface: 32-bit byte addresses,
32-bit data, four byte write strobes, and one outstanding CPU transaction
at a time.

The CPU remains the only implemented Jupiter transaction master through
Milestone 4, so no multi-master arbitration logic is required in that
milestone.

Milestone 5 adds GPU as a second external-SDRAM master, and Milestone 6 adds
DMA as a third. The current selected policy is deterministic non-preemptive
three-way round-robin CPU -> GPU -> DMA, with inactive requesters skipped and
a granted logical transaction held through completion.

SDRAM refresh is controller maintenance and may stall the selected requester
while required maintenance is serviced.

The complete transaction semantics are documented in
`docs/BUS_MEMORY_MAP.md`.

### Memory Map

**MILESTONE 4 UPDATED MAP.** The established Jupiter address assignments
are documented in `docs/BUS_MEMORY_MAP.md`:

| Address range | Region | Status |
| --- | --- | --- |
| `0x00000000`–`0x00000FFF` | Internal/test RAM | Implemented in M3 |
| `0x00001000`–`0x00001003` | MMIO scratch register | Implemented in M3 |
| `0x00001100`-`0x000011FF` | GPU control MMIO | 2D integrated in M5B-2; M10A reserves `0x1140`-`0x117F` for 3D |
| `0x00001200`–`0x000012FF` | DMA control MMIO | Integrated in M6B-2 |
| `0x00001300`–`0x000013FF` | PCM audio control MMIO | Integrated in M7 |
| `0x00001400`–`0x000014FF` | Controller input MMIO | Integrated in M8B-1 |
| `0x10000000`–`0x17FFFFFF` | External SDRAM maximum aperture | Selected for M4 |

The usable SDRAM portion depends on reported installed capacity:

- 32 MiB ends at `0x11FFFFFF`;
- 64 MiB ends at `0x13FFFFFF`;
- 128 MiB ends at `0x17FFFFFF`.

The former Milestone 3 reservation from `0x18000000` through `0x1FFFFFFF`
returns to unmapped space unless a later milestone explicitly assigns it.

Later controller, firmware, and other unselected regions remain to be
assigned without overlapping the established regions.

### DMA Engine

**MILESTONE 6 SELECTED.** Jupiter's initial DMA is one CPU-controlled channel for aligned 32-bit external-SDRAM to external-SDRAM copies. Source and destination auto-increment by four bytes, length is expressed in 32-bit words, and completion is exposed through CPU-readable BUSY/DONE state. DMA becomes the third external-SDRAM master alongside CPU and GPU. The selected architecture is documented in `docs/DMA_ARCHITECTURE.md`.

### External SDRAM

**MILESTONE 4 SELECTED.** Jupiter will use the primary MiSTer external
`SDRAM_*` interface as its external working-memory path.

The selected architecture is documented in `docs/SDRAM_ARCHITECTURE.md`.

- Jupiter owns its SDR SDRAM controller RTL under `rtl/memory/`.
- The existing 32-bit Jupiter transaction interface is preserved.
- The physical SDRAM data path is 16 bits, so aligned 32-bit Jupiter accesses
  are converted into two logical 16-bit halves.
- The maximum CPU-visible aperture is `0x10000000` through `0x17FFFFFF`.
- The usable portion depends on the reported installed size: 32 MiB,
  64 MiB, or 128 MiB.
- The CPU remains the only Jupiter transaction master in Milestone 4.
- Required SDRAM initialization and periodic refresh are controller
  responsibilities.
- Refresh may stall CPU transactions and must not be starved by sustained
  CPU activity.
- Milestone 5 adds GPU and Milestone 6 adds DMA as external-SDRAM masters;
  the selected arbiter is deterministic non-preemptive three-way round-robin
  in CPU -> GPU -> DMA cyclic order.
- Exact row/bank/column mapping, controller clocking, physical timing values,
  and CAS behavior remain implementation-stage decisions.

### 2D Graphics Subsystem

**PROPOSED.** As a fantasy console, Jinix Jupiter is designed primarily as a new system rather than an emulator of any original hardware. Strong hardware-assisted 2D graphics are a design target:

- Sprite engine: hardware sprites with per-sprite color/table lookup, size control, and flip/h mirror — exact sprite counts, maximum sprite dimensions, and simultaneous sprite limits remain TBD.
- Tilemap/background: scrollable multi-plane tile layers with palette remapping — exact layer count, VRAM organization, and palette sizes remain TBD.
- Scrolling: separate X/Y registers per layer; windowed scroll regions may be supported.
- Color modes: RGB555 / RGB565-style internal formats are provisional design targets. The core does not assume any fixed-limit output color depth.
- Blitter: bit-block transfer source/dest with alpha/color-key transparency and logical ops (AND/OR/XOR) — implementation details remain TBD.
- Tile-oriented, bandwidth-efficient rendering is an important design goal because external-memory bandwidth is limited.

### Fixed-Function 3D Graphics

**MILESTONE 10 SELECTED.** M10A selects a bounded post-transform fixed-function triangle renderer. The complete contract is documented in `docs/GPU_3D_ARCHITECTURE.md`.

- 3D uses `0x00001140`-`0x0000117F` inside the existing GPU MMIO aperture.
- The external CPU/GPU/DMA SDRAM arbiter remains unchanged.
- 2D and 3D share the existing GPU SDRAM master through deterministic internal arbitration.
- One accepted START renders one post-transform triangle.
- Coverage uses pixel-center edge functions, counter-clockwise front faces, and the top-left fill rule.
- Texture and framebuffer pixels use RGB565.
- The selected first sampler is perspective-correct nearest-neighbor; bilinear filtering is deferred.
- Depth is unsigned 16-bit with strict LESS testing.
- Optional blending is constant-alpha RGB565 source-over.
- Vertex and interpolation arithmetic is fixed-point with explicitly sized intermediates.
- FPGA DSP inference is permitted, but M10A makes no resource, frequency, or timing-closure claim.
- Transforms, lighting, geometric clipping, command FIFOs, mipmapping, anisotropic filtering, and programmable shaders are deferred.

### PCM Audio System

Milestone 7 implements and verifies the initial Jupiter PCM architecture
through deterministic simulation. The selected contract and verification
evidence are documented in `docs/AUDIO_ARCHITECTURE.md`.

- Four hardware PCM voices are implemented as the bounded initial design;
  the provisional 32–64 voice project target remains unverified and is not a
  Milestone 7 hardware-capacity claim.
- Source samples are signed 16-bit mono PCM at a logical 48 kHz rate.
- Each voice has independent 8-bit left/right volume and contributes to a
  signed stereo mixer with 16-bit saturated output.
- The initial sample store is a shared internal 4096 × 16-bit PCM RAM.
- Audio does not become a fourth external-SDRAM master; the verified
  CPU/GPU/DMA three-master arrangement remains unchanged.
- CPU-visible audio control is selected at `0x00001300–0x000013FF`.
- The engine remains in the current 20 MHz `clk_sys` domain and generates an
  exact-average 48 kHz output tick using a fractional phase accumulator.
- Jupiter drives the existing MiSTer core-facing `AUDIO_L`, `AUDIO_R`,
  `AUDIO_S`, and `AUDIO_MIX` ports. The framework-owned `audio_out` path
  remains responsible for downstream filtering, I²S, S/PDIF, and DAC output.

The exact initial behavior and register contract are documented in
`docs/AUDIO_ARCHITECTURE.md`.

### Controller Input

Milestone 8 selects Jupiter's initial controller-input architecture.

- `hps_io` exposes six digital 32-bit joystick words:
  `joystick_0` through `joystick_5`.
- Jupiter exposes all six words bit-for-bit to software through the M8B-1 controller MMIO target.
- No semantic button-name remapping is invented because the repository does
  not currently establish an authoritative name-to-bit contract.
- Controller MMIO is integrated at `0x00001400–0x000014FF`.
- The initial interface is read-only and polling-based.
- Analog sticks, keyboard, mouse, paddles, spinners, rumble, light-gun/HID
  facilities, and interrupt-on-change are not selected for the initial
  Milestone 8 implementation.
- `hps_io` and Jupiter use the existing `clk_sys` domain for the selected
  signals, so no additional controller clock domain is introduced.

The complete selected contract is documented in
`docs/CONTROLLER_ARCHITECTURE.md`.

### BIOS ROM — Boot Firmware

Boot firmware / BIOS is original Jinix Jupiter software.

M9A selects the initial boot mechanism:

- CPU reset execution begins at `0x00000000`, matching the existing CPU reset
  vector and internal-RAM aperture.
- The initial Milestone 9 boot image uses the existing 4 KiB internal RAM
  rather than adding a new ROM or MMIO target.
- `0x00000000–0x000003FF` is the initial 1 KiB BIOS region.
- `0x00000400–0x00000FFF` is the initial 3 KiB application region.
- BIOS execution begins at `0x00000000`.
- The initial application entry point is `0x00000400`.
- Host tooling generates one complete 1024-word RAM image before simulation.
- That generated image initializes internal RAM before reset is released.

This build-time mechanism is the minimum Milestone 9 path. Runtime firmware
replacement, removable-media semantics, HPS firmware loading, and
physical-hardware validation remain deferred.

See `docs/BOOT_ARCHITECTURE.md` for the normative M9 boot contract.

### Development Tools

M9A selects a minimal host toolchain under `software/devkit/` and
`software/tools/`.

The first devkit consists of:

- a dependency-light Python 3 two-pass assembler using `docs/ISA_SPEC.md` as
  the normative ISA source;
- flat textual 32-bit instruction-word output with no relocatable object
  format;
- symbolic labels and deterministic PC-relative branch/jump resolution;
- deterministic diagnostics for malformed syntax, invalid registers,
  out-of-range immediates/displacements, duplicate labels, unknown labels,
  unknown mnemonics, and other invalid source;
- a deterministic system-image builder that places BIOS words at
  `0x00000000`, application words at `0x00000400`, zero-fills unused words,
  and emits exactly 1024 words for the initial internal-RAM image.

A C compiler, relocatable linker, runtime library, debugger transport, and
general asset pipeline remain outside the minimum Milestone 9 scope.

See `docs/BOOT_ARCHITECTURE.md` for the complete selected host-tool contract.

### Optional HPS-Assisted Services

The MiSTer host ARM processor (Cortex-A9) may optionally assist Jupiter with storage, networking, media, file loading, save data, or other host-facing services.
Such HPS assistance must not become Jupiter's game CPU: core gameplay architecture must not depend on the ARM processor performing normal game logic.

- When and if implemented, the exact protocols, interfaces, and OSD options for any HPS-assisted services remain TBD.

---

## Unresolved Questions

The following items represent design decisions that remain open for later
Jinix Jupiter milestones. Decisions already selected by completed milestones
are treated as current architecture; only their future extensions remain open.

### CPU ISA and Microarchitecture

- What is the exact instruction set architecture for the proposed custom 32-bit CPU? Is it derived from an existing ISA or fully custom?
- How many pipeline stages will the CPU have at target clock frequencies? Will a multiply unit be built-in or simulated via microcode?
- Target CPU frequency is TBD.

### System Bus

- CPU/GPU/DMA external-memory arbitration is selected through Milestone 6.
  If later milestones add more masters or burst semantics, how should the
  current deterministic non-preemptive three-way round-robin policy be
  extended?

### Memory Map

- Where should later controller, firmware, and other still-unselected regions
  be assigned around the established RAM, GPU MMIO, DMA MMIO, audio MMIO,
  and external-SDRAM regions?

### SDRAM Controller and Bandwidth Scheduling

- What exact row/bank/column transformation should the controller use for
  each supported SDRAM geometry?
- What controller clock frequency and SDRAM clock phase relationship will
  be selected?
- What initialization delays, refresh interval, CAS latency, and other
  timing parameters are required by the selected physical SDRAM
  configuration?
- Which performance optimizations, if any, are justified after functional
  correctness is verified?
- If later milestones introduce memory masters beyond the current CPU, GPU,
  and DMA set, what extensions to the selected three-way arbitration policy
  are justified?

### 2D GPU Organization

- How are tilemaps, sprite engines, palettes, scroll registers, and priority logic organized in the fixed-function 2D block? Exact register counts and memory widths remain TBD.

### Fixed-Function 3D Organization

M10A resolves the initial 3D organization. A new `jupiter_gpu_3d` engine is integrated behind the existing subsystem-visible GPU interface. The M5 2D contract remains intact. The 2D and 3D engines use distinct MMIO subranges and share the single GPU SDRAM master through deterministic non-preemptive two-way transaction arbitration. The verified system-level CPU -> GPU -> DMA arbitration contract remains unchanged. Register formats, rasterization rules, memory behavior, and staged implementation checkpoints are defined in `docs/GPU_3D_ARCHITECTURE.md`.

### FPGA DSP Resource Utilization

- Where are FPGA DSP blocks used (e.g., audio mixing, fixed-point math for 3D coordinate transforms)? Scope and allocation remain TBD.

### Display Modes and Internal Pixel Formats

- What display modes does Jupiter support — resolutions, timing parameters, interlacing, crop regions?
- What internal pixel formats are used in RAM versus what the HDMI path requires? Both remain TBD.

### Audio Voice Architecture

- Milestone 7 implements and verifies four signed 16-bit PCM voices,
  shared internal sample RAM, independent left/right volume, deterministic
  saturated stereo mixing, and a 48 kHz logical output rate. Future
  voice-count expansion,
  external-memory streaming, looping, pitch control, envelopes, synthesis,
  effects, and other extensions remain open.

### DMA Organization

- Milestone 6 selects one CPU-controlled aligned 32-bit external-SDRAM copy
  channel and deterministic participation as the third SDRAM master. Future
  multi-channel operation, peripheral triggers, burst modes, descriptors,
  interrupts, alternate transfer modes, and other DMA extensions remain open.

### Controller / Peripheral Register Design

- M8B-1 implements six read-only 32-bit digital controller-state registers.
- M8B-2 connects those subsystem inputs directly to MiSTer `joystick_0`
  through `joystick_5` via `Template.sv` and `jupiter_system`.
- The controller aperture is `0x00001400–0x000014FF`; implemented registers
  occupy `0x1400` through `0x1414`.
- Reserved aligned offsets read zero and writes have no effect.
- No interrupt/status mechanism is selected for the initial implementation.
- Future analog input, semantic button aliases, rumble, keyboard/mouse, HID,
  or other peripheral extensions remain open.


### BIOS / Boot Process

- M9A selects the initial build-time internal-RAM image, memory layout, and entry protocol; runtime firmware update remains deferred.

### Development Tools

- M9A selects the minimum assembler plus system-image builder; richer compiler, debugger, linker, and asset-tool architecture remains deferred.

### HPS-Assisted Storage / Networking / Media Interfaces

- When/if implemented, which host-facing services the MiSTer HPS processor provides (file system access, save data, networking, media) over which protocols remain TBD.

---

*This architecture document is written as a living document. Sections marked "PROPOSED" may change significantly as design decisions are finalized and RTL implementation commences.*
