# Jinix Jupiter

Jinix Jupiter is a new fantasy-console FPGA platform being developed for MiSTer-compatible hardware, including the SuperStation One.

Jupiter is **not an emulator of an existing console**. It is being designed as its own machine with a custom CPU, memory architecture, graphics hardware, DMA engine, audio subsystem, firmware, and development tools.

> **Current branch:** `milestone-10`
> **Current checkpoint:** M10A fixed-function 3D architecture is selected and documented; M10B-1 GPU integration shell and MMIO are next.
> **Verified predecessor:** `m9-verified` = `c989b080071be8336211f21dda52cdb91d266ee7`
---

## Project Status

| Milestone | Area | Status |
|---|---|---|
| 0 | Architecture / repository scaffold | Complete |
| 1 | Simulation skeleton / system integration baseline | Verified |
| 2 | Custom 32-bit CPU and ISA | Verified |
| 3 | Internal memory / MMIO / system transaction path | Verified |
| 4 | External SDR SDRAM | Verified |
| 5 | Hardware 2D graphics | Verified |
| 6 | DMA and three-master SDRAM arbitration | **Verified — `m6-verified`** |
| 7 | PCM audio | **Verified in simulation — `m7-verified`** |
| 8 | Controllers and core peripherals | **Verified in simulation — `m8-verified`** |
| 9 | BIOS and host development tools | **Complete — M9D acceptance verified** |
| 10+ | 3D, HPS services, later platform work | Not yet implemented |
Milestones are developed incrementally with deterministic simulation coverage. Synthesis, timing closure, resource usage, and physical-hardware operation are not claimed unless they are actually measured or tested.

---

## What Jupiter Can Do Today

The verified design currently contains:

- a custom **32-bit Jupiter CPU** with a documented fixed-width ISA;
- 32 general-purpose 32-bit registers with `r0` hardwired to zero;
- deterministic valid/ready memory transactions;
- internal/test RAM and CPU-visible MMIO;
- direct support for the MiSTer primary external SDR SDRAM;
- a 32-bit logical SDRAM frontend over the physical 16-bit SDRAM interface;
- a hardware 2D tile/background renderer;
- CPU-visible GPU control registers;
- a functional DMA engine;
- deterministic CPU/GPU/DMA shared-SDRAM arbitration;
- four hardware signed 16-bit PCM voices with independent left/right volume;
- deterministic 48 kHz stereo PCM mixing with signed 16-bit saturation;
- internal 4096 × 16-bit PCM sample RAM and CPU-visible audio MMIO;
- signed stereo audio integrated through the MiSTer-facing `AUDIO_L`, `AUDIO_R`, `AUDIO_S`, and `AUDIO_MIX` ports;
- automated Icarus Verilog simulation regressions covering the implemented CPU, memory, SDRAM, GPU, DMA, audio, contention, and production audio-integration paths.

The existing template/demo video path is still preserved as the live MiSTer-facing video producer. The Milestone 5 GPU is currently verified by rendering into an SDRAM framebuffer; presenting that framebuffer as the final live display is a later integration step.

---

## CPU and ISA

Milestone 2 established Jupiter's first functional CPU architecture.

Current ISA properties include:

- fixed 32-bit instructions;
- 32 × 32-bit registers;
- `r0` permanently reads as zero;
- 32-bit byte-addressed program counter;
- little-endian memory organization;
- aligned 32-bit `LDW` / `STW`;
- one outstanding CPU memory transaction at a time;
- valid/ready transaction semantics.

Implemented instructions include:

`NOP`, `ADD`, `SUB`, `AND`, `OR`, `XOR`, `ADDI`, `LDW`, `STW`, `BEQ`, `BNE`, `J`, and `HALT`.

See `docs/ISA_SPEC.md` for the architectural contract.

---

## Memory Architecture

### Internal / MMIO map

Current established regions include:

| Address range | Function |
|---|---|
| `0x00000000–0x00000FFF` | Internal/test RAM |
| `0x00001000–0x00001003` | Scratch MMIO |
| `0x00001100–0x000011FF` | GPU 2D control MMIO |
| `0x00001200–0x000012FF` | DMA control MMIO |
| `0x00001300–0x000013FF` | PCM audio control MMIO |
| `0x00001400–0x000014FF` | Controller input MMIO |
| `0x10000000–0x17FFFFFF` | Maximum external-SDRAM aperture |

The usable SDRAM range depends on the MiSTer-reported installed capacity.

See `docs/BUS_MEMORY_MAP.md` for the current authoritative memory map.

### External SDRAM

Milestone 4 added a Jupiter-owned controller for the MiSTer primary SDR SDRAM interface.

The design exposes a 32-bit logical Jupiter memory transaction while the frontend/controller performs the two required physical 16-bit SDRAM operations. Initialization, refresh, address mapping, byte masks, and transaction integrity are covered by deterministic simulation tests.

The currently generated Jupiter system clock is **20 MHz** from the existing 50 MHz reference PLL. This is an implemented clock configuration, not a maximum-frequency or timing-closure claim.

---

## 2D Graphics

Milestone 5 introduced the first functional Jupiter graphics hardware.

The current renderer supports:

- 8×8 tiles;
- RGB565 pixel data;
- one row-major tilemap;
- CPU-programmable tilemap, tile-data, and framebuffer bases;
- CPU-programmable map dimensions;
- CPU `START`, `BUSY`, and `DONE` control;
- rendering into a linear RGB565 framebuffer in external SDRAM.

For each tile, the renderer reads the tilemap and tile data and writes the resulting framebuffer pixels through the production SDRAM path.

The current Milestone 5 renderer deliberately does **not** yet imply a complete final GPU. Sprites, scrolling, affine effects, blending, general blitting, and the later 3D subsystem remain future work unless selected by later milestones.

---

## DMA

Milestone 6 is complete and tagged **`m6-verified`**.

The selected initial DMA architecture provides:

- one DMA channel;
- aligned 32-bit external-SDRAM → external-SDRAM copies;
- source and destination auto-increment by four bytes;
- transfer length in 32-bit words;
- CPU-controlled start;
- CPU-readable `BUSY` / `DONE`;
- one outstanding DMA transaction at a time;
- deterministic completion behavior;
- no descriptor chains, scatter/gather, interrupts, bursts, audio triggers, or overlapping-copy semantics in the initial implementation.

### Shared SDRAM arbitration

CPU, GPU, and DMA are the three current external-SDRAM masters.

They use deterministic, non-preemptive three-way round-robin arbitration:

`CPU → GPU → DMA → CPU`

Inactive masters are skipped. Once a logical transaction is granted, that master remains selected through completion.

Milestone 6 verification includes:

- standalone DMA control and transfer sequencing;
- integrated multiword DMA copies through the real SDRAM path;
- CPU/DMA contention;
- GPU/DMA contention;
- simultaneous CPU/GPU/DMA contention;
- forward progress by all three masters;
- source/destination and unrelated-memory integrity;
- regression coverage of the previously verified system.

The final Milestone 6 full regression passed before `m6-verified` was created.

---

## Milestone 7 — PCM Audio

Milestone 7 is complete in simulation on branch **`milestone-7`**.

The selected PCM architecture is now implemented end-to-end. CPU-visible audio MMIO, internal PCM sample RAM, four-voice playback sequencing, deterministic stereo mixing, saturation, shared sample-RAM arbitration, and production MiSTer-facing audio output integration are all covered by automated regressions.

The detailed architectural contract and verification closeout are documented in `docs/AUDIO_ARCHITECTURE.md`.

### Verified MiSTer audio interface facts

The repository inspection established the actual core-facing MiSTer audio contract:

- `CLK_AUDIO` is supplied to the `emu` core at **24.576 MHz**;
- `AUDIO_L` is a 16-bit core sample;
- `AUDIO_R` is a 16-bit core sample;
- `AUDIO_S = 1` tells the MiSTer framework that the samples are signed;
- `AUDIO_MIX` selects the framework's mono-mixing behavior;
- `sys_top` already owns the MiSTer `audio_out` block;
- `audio_out` already handles the downstream filtering/mixing path and produces I²S, S/PDIF, and sigma-delta DAC outputs;
- the core therefore does **not** need to instantiate its own MiSTer `audio_out`, `i2s`, or `spdif` blocks.

The production `Template.sv` now connects Jupiter's mixed samples through `jupiter_system` to `AUDIO_L` and `AUDIO_R`, asserts `AUDIO_S = 1` for signed samples, and selects native stereo with `AUDIO_MIX = 0`.

The framework audio PLL converts a 50 MHz reference to **24.576 MHz**. MiSTer's `audio_out` is built around 48 kHz / 96 kHz audio handling internally.

### Selected initial M7 architecture

The initial PCM architecture is now frozen in `docs/AUDIO_ARCHITECTURE.md`.

The selected implementation provides:

- **4 hardware PCM voices**;
- signed 16-bit mono PCM source samples;
- a logical 48 kHz output rate;
- independent 8-bit left/right volume per voice;
- deterministic signed stereo mixing with 16-bit saturation;
- shared internal **4096 × 16-bit** PCM sample RAM;
- CPU-visible audio MMIO at `0x00001300–0x000013FF`;
- operation in the existing 20 MHz `clk_sys` domain;
- an exact-average 48 kHz sample tick generated by a fractional phase accumulator;
- signed 16-bit stereo output through the existing MiSTer-facing audio ports;
- no fourth external-SDRAM master;
- no change to the verified Milestone 6 DMA or CPU/GPU/DMA SDRAM arbiter.

Pitch control, hardware looping, waveform synthesis, ADSR, interrupts,
external-SDRAM audio streaming, and other unselected features are not part of
the initial Milestone 7 implementation.

The provisional 32–64 voice figure remains a future target only. No FPGA
voice capacity, DSP usage, timing closure, or resource usage is claimed
without synthesis or hardware evidence.

---

## Milestone 7 Verified Result

Milestone 7 is verified by deterministic automated evidence that:

- each implemented PCM voice behaves as documented;
- multiple voices mix as documented;
- CPU-visible audio registers behave deterministically;
- any selected addressing, looping, volume, or pitch behavior matches reference results;
- output samples match deterministic reference results;
- audio operation does not corrupt unrelated state or memory;
- tests automatically report pass/fail;
- the resulting samples integrate with the verified MiSTer-facing audio port contract without interface mismatches.

---

## Simulation

The project uses Icarus Verilog for deterministic host-side simulation.

From the repository root:

```bash
make -C sim test
```

Individual milestone/focused tests are also exposed through `sim/Makefile`.

Some inherited template modules require simulation-only compatibility stubs under `sim/`. Those stubs are not included in the synthesis QIP.

Known inherited warnings in the template demo-video path are intentionally not treated as Jupiter functional failures.

---

## Repository Layout

```text
jinix_jupiter/
├── docs/                  Architecture, milestone, ISA, bus, GPU, DMA and audio docs
├── rtl/
│   ├── audio/             PCM sample RAM, voice playback and stereo mixer
│   ├── cpu/               Jupiter CPU
│   ├── dma/               DMA engine
│   ├── gpu/               2D GPU
│   ├── memory/            RAM, interconnect, SDRAM frontend/controller/arbiter
│   └── peripherals/       MMIO and controller/core-peripheral RTL
├── sim/                   Deterministic simulation tests and models
├── software/
│   ├── bios/              Future Jupiter firmware
│   ├── devkit/            Future development kit
│   └── tools/             Future host-side tools
├── sys/                   MiSTer framework/platform support
├── Template.sv            Current MiSTer-facing top-level core
├── files.qip              Quartus source list
└── Readme.md
```

---

## Development Rules

Jupiter follows a simulation-first, milestone-by-milestone workflow.

Important project rules include:

- document architecture decisions before large implementation work;
- preserve verified behavior while adding the next subsystem;
- keep changes bounded to the active milestone;
- prefer small deterministic tests over broad unverified rewrites;
- do not discard unrelated uncommitted work to obtain a clean tree;
- do not silently reset, clean, restore, checkout, or delete unrelated work;
- do not claim synthesis success, timing closure, resource counts, performance, or hardware operation without actual evidence;
- treat provisional targets as provisional until measurement justifies fixing them.

See `docs/DEVELOPMENT_RULES.md`.

---

## Verified Milestone Tags

The repository uses annotated verification tags to preserve known-good milestone checkpoints.

The important recent checkpoints are:

- `m4-verified` — external SDRAM integration;
- `m5-verified` — hardware 2D graphics and CPU/GPU contention;
- `m6-verified` — DMA and CPU/GPU/DMA shared-SDRAM integration;
- `m7-verified` — PCM playback, stereo mixing, audio MMIO, and MiSTer-facing audio integration.

The `milestone-7` branch starts directly from `m6-verified`.

---

## Current Next Step

**M10B-1 — integrate the selected 3D shell without changing the external SDRAM-master contract.**

M10A selects a bounded fixed-function 3D path using the existing GPU MMIO aperture and GPU SDRAM master. The 3D engine shares that master with the verified 2D renderer through deterministic internal transaction arbitration, preserving the existing CPU → GPU → DMA system arbiter.

The initial renderer accepts one post-transform triangle per START and selects top-left coverage, RGB565 rendering, 16-bit depth, perspective-correct nearest texture mapping, and constant-alpha blending.

---

## Project Scope

Jinix Jupiter's broader goal is a late-1990s / early-2000s-inspired fantasy console implemented as new FPGA hardware, with:

- a custom 32-bit CPU;
- hardware-assisted 2D graphics;
- later fixed-function 3D graphics;
- PCM audio;
- DMA;
- controllers/peripherals;
- boot firmware / BIOS;
- host-side development tools;
- optional HPS-assisted storage/network/media services where useful.

The HPS is intended for host-facing services, not as a substitute for Jupiter's game CPU.

The project remains under active development.
