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
 - **Joystick / button input** — up to 32 buttons across multiple ports.
 - **Analog joystick axes** — 16-bit per-port values (Y[15:8], X[7:0]).
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
Milestone 4, so no multi-master arbitration logic is required yet.

SDRAM refresh is controller maintenance and may stall CPU requests while
required maintenance is serviced.

Arbitration must be explicitly extended when another Jupiter master, such
as DMA, is introduced.

The complete transaction semantics are documented in
`docs/BUS_MEMORY_MAP.md`.

### Memory Map

**MILESTONE 4 UPDATED MAP.** The established Jupiter address assignments
are documented in `docs/BUS_MEMORY_MAP.md`:

| Address range | Region | Status |
| --- | --- | --- |
| `0x00000000`–`0x00000FFF` | Internal/test RAM | Implemented in M3 |
| `0x00001000`–`0x00001003` | MMIO scratch register | Implemented in M3 |
| `0x10000000`–`0x17FFFFFF` | External SDRAM maximum aperture | Selected for M4 |

The usable SDRAM portion depends on reported installed capacity:

- 32 MiB ends at `0x11FFFFFF`;
- 64 MiB ends at `0x13FFFFFF`;
- 128 MiB ends at `0x17FFFFFF`.

The former Milestone 3 reservation from `0x18000000` through `0x1FFFFFFF`
returns to unmapped space unless a later milestone explicitly assigns it.

Later GPU, DMA, audio, controller, firmware, and other regions remain to be
assigned without overlapping the established regions.

### DMA Engine

**PROPOSED.** A dedicated DMA controller block that supports high-bandwidth movement for graphics, audio, and general memory operations is a design target. Exact channels, transfer modes, arbitration, scheduling, and supported transfer operations remain TBD.

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
- Multi-master arbitration remains deferred until another Jupiter master
  such as DMA is implemented.
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

**PROPOSED.** Fixed-function 3D is a later Jinix Jupiter design target, not part of Milestone 0 or the immediate development roadmap. Provisional targets include:

- Triangle rasterizer, texture mapping, depth buffering (Z-buffer), perspective-correct interpolation, blending — all TBD as to implementation details and exact precision.
- Nearest / bilinear texture sampling may be supported; exact sampling behavior remains TBD.
- FPGA DSP blocks should be used where advantageous for fixed-point math operations (coordinate transformation, interpolation).
- Tile-oriented, bandwidth-efficient rendering is an important design goal because external-memory bandwidth is limited. — exact polygon throughput target, texture-cache size, Z-buffer layout, and clock rates remain TBD.

### PCM Audio System

**PROPOSED.** PCM audio is a Jinix Jupiter design target. Provisional targets include:

- Multiple hardware voices and hardware mixing are intended; exact voice count is provisionally estimated at roughly 32–64 channels, but remains TBD.
- FPGA DSP resources may be used for mixing and filtering as a design goal.
- Output pathways through the MiSTer framework (e.g., `audio_out.sv`, I²S/S/PDIF) are to-be-designed integration points; how Jupiter directly drives audio modules is not yet determined.
- Sample rate, bit depth, FIFO structure, register map, voice count, and buffering remain TBD.

### Controller Input

**PROPOSED.** Joystick/button handling may be partially available through the MiSTer framework. Provisional targets include:

- `hps_io` provides up to 32 buttons and analog joystick axes via its output ports — verified from existing template source.
- Controller register block location (address range) and feature set are TBD; an interrupt-on-state-change capability is a tentative design target only.
- If implemented, analog mode support for the Y/X axes would forward data from `hps_io.joystick_l_analog_*` (verified available ports in `hps_io.sv`). Whether additional controller types or raw ADC paths are needed remains TBD.

### BIOS ROM — Boot Firmware

Boot firmware / BIOS is a Jinix Jupiter design target.
Jinix Jupiter is a new fantasy console and does not reproduce firmware from an existing historical machine.

- Firmware storage, loading method, in-memory location, boot protocol, and update mechanism remain TBD.
- It is not assumed that the firmware must be synthesized into block RAM or distributed RAM.
- No particular file format for firmware content is assumed at this time.
- `software/bios/` is the intended source directory for Jupiter boot-firmware development.

### Development Tools

Host-side development tools are a Jinix Jupiter design target, intended under `software/devkit/` and `software/tools/`.

- A future custom assembler, linker, compiler support, asset-conversion tools, debugger support, and graphics/audio asset tools may be listed as development goals.
- Exact CPU ISA, the target object format, the executable format, the debugging protocol, and implementation of each tool all remain TBD.

### Optional HPS-Assisted Services

The MiSTer host ARM processor (Cortex-A9) may optionally assist Jupiter with storage, networking, media, file loading, save data, or other host-facing services.
Such HPS assistance must not become Jupiter's game CPU: core gameplay architecture must not depend on the ARM processor performing normal game logic.

- When and if implemented, the exact protocols, interfaces, and OSD options for any HPS-assisted services remain TBD.

---

## Unresolved Questions

The following items represent genuine open Jinix Jupiter design decisions that must be finalized before RTL implementation can proceed.

### CPU ISA and Microarchitecture

- What is the exact instruction set architecture for the proposed custom 32-bit CPU? Is it derived from an existing ISA or fully custom?
- How many pipeline stages will the CPU have at target clock frequencies? Will a multiply unit be built-in or simulated via microcode?
- Target CPU frequency is TBD.

### System Bus

- When additional masters such as DMA are introduced, what arbitration,
  priority, and any optional burst semantics should extend the established
  Milestone 3 transaction mechanism?

### Memory Map

- Where should later GPU, DMA, audio, controller, firmware, and other regions
  be assigned around the established internal-memory/MMIO regions and the
  Milestone 4 external-SDRAM aperture?

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
- If later milestones introduce additional memory masters, what arbitration
  and scheduling policy should replace the current CPU-only arrangement?

### 2D GPU Organization

- How are tilemaps, sprite engines, palettes, scroll registers, and priority logic organized in the fixed-function 2D block? Exact register counts and memory widths remain TBD.

### Fixed-Function 3D Organization

- When 3D is implemented later, how will triangle setup, rasterization, texture mapping, Z-buffer, and blending be organized in fixed-function hardware? Design remains TBD.

### FPGA DSP Resource Utilization

- Where are FPGA DSP blocks used (e.g., audio mixing, fixed-point math for 3D coordinate transforms)? Scope and allocation remain TBD.

### Display Modes and Internal Pixel Formats

- What display modes does Jupiter support — resolutions, timing parameters, interlacing, crop regions?
- What internal pixel formats are used in RAM versus what the HDMI path requires? Both remain TBD.

### Audio Voice Architecture

- How many PCM voices, what sample formats (rate, bit depth), buffering strategy, and mixing architecture will be implemented? The exact voice count, channel configuration, envelope/FM support, and mixing approach all remain TBD.

### DMA Organization

- How are DMA channels organized — peripheries they serve, bus-grant latency, burst sizes, priority arbitration, overlap with CPU execution, and self-modifying write-back capabilities? All TBD.

### Controller / Peripheral Register Design

- Which controller types (standard joysticks, buttons) are supported? What about analog axes or other peripheral interfaces?
- How many controller ports, input formats, and register maps are planned? All remain TBD.

### BIOS / Boot Process

- Firmware storage, loading method, in-memory location, boot protocol, and update mechanism for Jupiter custom boot firmware remain TBD.

### Development Tools

- What host-side tools (assembler, linker, compiler support, debugger, asset converters, sprite/tile editors) will the devkit include? The exact toolchain architecture, object/executable formats, and debugging protocol all remain TBD.

### HPS-Assisted Storage / Networking / Media Interfaces

- When/if implemented, which host-facing services the MiSTer HPS processor provides (file system access, save data, networking, media) over which protocols remain TBD.

---

*This architecture document is written as a living document. Sections marked "PROPOSED" may change significantly as design decisions are finalized and RTL implementation commences.*
