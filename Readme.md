# Jinix Jupiter

Jinix Jupiter is an experimental **32-bit FPGA fantasy console** being developed as a custom core for the MiSTer-compatible ecosystem, including the SuperStation One.

Jupiter is not an emulator for an existing console. It is a new hardware platform being designed from the ground up, with its own CPU instruction set, memory architecture, graphics hardware, audio system, BIOS, and software development tools.

The project is built incrementally on top of the MiSTer framework, with simulation-first verification at each development milestone.

> **Current status:** Milestone 3 development is in progress.
> Milestones 1 and 2 have verified checkpoints. The current Milestone 3 work includes an internal bus/interconnect, 4 KiB test RAM, a memory-mapped scratch register, and CPU/system integration. Full Milestone 3 regression/documentation verification is the next step before an `m3-verified` checkpoint.

---

## Project goals

Jupiter is intended to become a late-1990s / early-2000s-style fantasy console implemented primarily in FPGA logic.

The long-term design direction includes:

- a custom 32-bit RISC CPU
- FPGA-based 2D graphics hardware
- fixed-function 3D acceleration
- external SDRAM for game memory
- DMA
- PCM audio with FPGA DSP assistance
- memory-mapped peripherals
- a BIOS/runtime environment
- host-side development tools
- optional HPS services for storage, networking, and media
- MiSTer / SuperStation One video, audio, controller, and platform integration

Performance targets, resource usage, clock speeds, memory capacities, and graphics capabilities remain provisional until they are implemented and measured on the target FPGA.

Jupiter development deliberately avoids claiming synthesis results, timing closure, FPGA resource usage, or hardware performance until those measurements have actually been obtained.

---

## Development status

### Milestone 0 — Architecture and repository foundation

Repository structure and architectural planning were established, including:

- `docs/ARCHITECTURE.md`
- `docs/MILESTONES.md`
- `docs/DEVELOPMENT_RULES.md`
- subsystem directories for CPU, GPU, audio, memory, DMA, and peripherals
- software directories for BIOS, development tools, and utilities

The project retains the MiSTer framework and template structure while placing Jupiter-specific implementation beneath it.

### Milestone 1 — Simulation and system skeleton

**Verified: `m1-verified`**

Milestone 1 established:

- Jupiter-specific RTL hierarchy
- MiSTer template integration
- subsystem boundary stubs
- deterministic simulation infrastructure
- clock/reset expectations
- automated PASS/FAIL smoke tests
- preservation of the existing known-good demonstration video path

This milestone established the integration skeleton without implementing the major console subsystems.

### Milestone 2 — CPU ISA and minimal CPU

**Verified: `m2-verified`**

Jupiter now contains a functional minimal custom **32-bit RISC CPU**.

The Milestone 2 ISA includes:

| Opcode | Instruction | Function |
|---|---|---|
| `0x00` | `NOP` | No operation |
| `0x01` | `ADD` | Register addition |
| `0x02` | `SUB` | Register subtraction |
| `0x03` | `AND` | Bitwise AND |
| `0x04` | `OR` | Bitwise OR |
| `0x05` | `XOR` | Bitwise XOR |
| `0x10` | `ADDI` | Add signed immediate |
| `0x20` | `LDW` | Load 32-bit word |
| `0x21` | `STW` | Store 32-bit word |
| `0x30` | `BEQ` | Branch if equal |
| `0x31` | `BNE` | Branch if not equal |
| `0x32` | `J` | PC-relative jump |
| `0xFF` | `HALT` | Stop execution |

The current CPU architecture provides:

- 32 general-purpose 32-bit registers (`r0`–`r31`)
- `r0` permanently hardwired to zero
- 32-bit byte-addressed address space
- 32-bit fixed-width instructions
- little-endian memory
- aligned 32-bit loads and stores
- PC-relative conditional branches and jumps
- synchronous active-high reset
- deterministic HALT state
- valid/ready memory transactions
- one outstanding memory transaction at a time

See [`docs/ISA_SPEC.md`](docs/ISA_SPEC.md) for the architectural definition.

### Milestone 3 — Internal bus, memory map, and basic memory

**In progress**

Milestone 3 connects the CPU to actual Jupiter system targets rather than the standalone memory model used for CPU development.

Implemented so far:

- CPU-to-system transaction interconnect
- 32-bit address and data paths
- valid/ready transaction handshake
- byte write strobes
- deterministic target decoding
- 4 KiB internal/test RAM
- memory-mapped scratch register
- deterministic behavior for unmapped accesses
- CPU subsystem integrating the CPU, interconnect, RAM, and MMIO target
- simulation of instruction fetches through the integrated memory path
- integrated CPU-driven RAM and MMIO testing

The current initial memory map is:

| Address range | Size | Function | Status |
|---|---:|---|---|
| `0x00000000–0x00000FFF` | 4 KiB | Internal/test RAM | Implemented |
| `0x00001000–0x00001003` | 4 bytes | MMIO scratch register | Implemented |
| `0x10000000–0x1FFFFFFF` | 256 MiB address window | External SDRAM reservation | Reserved for Milestone 4 |
| all other addresses | — | Unmapped | Deterministic response |

The 256 MiB SDRAM region is currently only an **address-space reservation**. It is not a claim that Jupiter currently implements or will necessarily contain 256 MiB of physical SDRAM.

For Milestone 3, invalid, unmapped, and misaligned accesses complete deterministically rather than hanging the CPU:

- unmapped reads return `0x00000000`
- unmapped writes complete without modifying state

See [`docs/BUS_MEMORY_MAP.md`](docs/BUS_MEMORY_MAP.md) for the complete transaction and memory-map specification.

---

## CPU memory interface

The current CPU and interconnect use the following transaction interface:

| Signal | Width | Description |
|---|---:|---|
| `mem_valid` | 1 | Request is active |
| `mem_write` | 1 | Write when asserted, read otherwise |
| `mem_addr` | 32 | Byte address |
| `mem_wdata` | 32 | Write data |
| `mem_wstrb` | 4 | Byte write enables |
| `mem_rdata` | 32 | Read response |
| `mem_ready` | 1 | Transaction completes |

A request remains active until `mem_ready` is asserted. The master keeps its request signals stable while waiting.

The CPU is currently the only implemented bus master, so Milestone 3 does not yet require arbitration. DMA and additional bus masters are planned for later milestones.

---

## Simulation

Simulation is currently the primary verification method for Jupiter.

The test suite uses **Icarus Verilog** with SystemVerilog support.

From the repository root:

```bash
make -C sim test