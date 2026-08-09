# Jinix Jupiter — Simulation Regression Suite

## Quick start

```sh
make -C sim test
```

This command runs the complete host-side Milestone 1, Milestone 2,
and Milestone 3 regression with Icarus Verilog.

The suites may also be run separately with `make -C sim m1-test`,
`make -C sim cpu-test`, and `make -C sim m3-test`.

## Simulator / tool selected

**Icarus Verilog (`iverilog` + `vvp`) is the simulator used by the current host-side regression.**

The Milestone 1 regression has been compiled and executed successfully with host-installed Icarus Verilog (`iverilog` + `vvp`). The host-side simulation flow does not depend on simulator availability inside OpenHands.

## Jupiter skeleton module / file

| Item            | Value                                           |
| --------------- | ----------------------------------------------- |
| Module name     | `jupiter_core`                                  |
| RTL source      | `rtl/jupiter_core.sv`                           |
| Testbench file  | `sim/jupiter_core_tb.sv`                        |

### Why this skeleton?

Milestone 1 establishes a Jupiter-owned hierarchy alongside the existing MiSTer template path. The exact Jupiter architecture (data paths, registers, bus fabric) is a Milestone 1 design decision; the initial hierarchy (`jupiter_core`) is intentionally minimal and may evolve through controlled architectural revisions documented in later milestones.

## Clock used by the testbench

| Name       | Period | Frequency | Purpose                            |
| ---------- | ------ | --------- | --------------------------------- |
| `TESTCLK`  | 10 ns  | 100 MHz   | Testbench clock (deterministic)   |

**Important:** This simulation clock is a **testbench value only**. It does **not** represent a final Jupiter hardware clock frequency. Hardware clocks will be specified in later milestones through the PLL configuration. The testbench clock is an arbitrary deterministic value chosen for simulation speed and clarity.

## Reset behavior used by the testbench

1. `RESET` is asserted (`1'b1`) for at least 3 positive edges of `TESTCLK`.
2. `RESET` is released on a negative edge of `TESTCLK`.
3. The DUT must return to its documented initial state within those 3 cycles.
4. Checks occur after the DUT nonblocking assignments have settled via `#1` delay before sampling.

## Observable behavior checked by the smoke test

The testbench checks the following at deterministic clock cycles (all values sampled after `#1` so the DUT nonblocking assignments have settled):

| Cycle (post-reset) | Expected `heartbeat` | Expected `tick_cnt`  | Other check       |
| -------------------- | -------------------- | -------------------- | ----------------- |
| 1                    | `8'hFF`              | `4'd1`               | —                 |
| 3                    | `8'hFF`              | `4'd3`               | —                 |
| 15                   | (any toggling)       | `4'd15`              | —                 |
| 16                 | —                    | `4'd0`               | `done_pulse == 1'b1` |

Each check is verified at its clock cycle; summary prints `RESULT: PASS` (exit 0) or `RESULT: FAIL` (exit 1).

## What this milestone does NOT implement

The following are **not** implemented by Milestone 1A and must not be assumed present in `jupiter_core`:

- CPU implementation
- GPU / video engine implementation
- DMA controller implementation
- Audio subsystem implementation
- SDRAM controller implementation
- Any controller or bus fabric implementation

## Milestone 1B Integration Test

`make -C sim test` includes the original `jupiter_core` smoke test and
the `jupiter_system` integration test.

The integration test instantiates `jupiter_system` alongside a direct
`mycore` reference and compares the video, pixel-enable, blanking, and sync
outputs cycle-for-cycle for 320000 clock cycles. It also verifies that the
Milestone 1A Jupiter skeleton remains active inside the wrapper.

`template_compat_stubs.sv` contains simulation-only models for the template
`lfsr` and `cos` helpers because the current Icarus Verilog environment does
not directly support all syntax/vendor primitives used by those original RTL
files. These compatibility models are testbench infrastructure only and must
not be added to `files.qip` or used as synthesizable replacements.

## Milestone 1C Subsystem Boundary Test

`make -C sim test` also runs `jupiter_stubs_tb`.

This test instantiates the CPU, memory/bus, DMA, graphics, audio, and
peripheral placeholder modules together. The placeholders expose only `clk`
and `reset` during Milestone 1; their functional interfaces remain TBD.

The test verifies that the complete placeholder set elaborates and executes
without unresolved module/interface errors. It does not test subsystem
functionality because no functional CPU, GPU, DMA, audio, SDRAM, or
peripheral implementation exists yet.

The established skeleton hierarchy, clock/reset behavior, subsystem
boundaries, and verification limits are documented in
`docs/SKELETON_INTERFACES.md`.

## Milestone 2 CPU Regression

Milestone 2 adds the real CPU implementation at
`rtl/cpu/jupiter_cpu.sv`. Its architectural contract is defined by
`docs/ISA_SPEC.md`.

The implemented Milestone 2 instruction subset is:

- `NOP`
- `ADD`
- `SUB`
- `AND`
- `OR`
- `XOR`
- `ADDI`
- `LDW`
- `STW`
- `BEQ`
- `BNE`
- `J`
- `HALT`

The CPU uses the unified `mem_valid` / `mem_ready` transaction interface
documented in `docs/ISA_SPEC.md`.

`make -C sim cpu-test` runs seven focused CPU tests:

- `cpu-state-test` — reset, PC, register file, `r0`, and halted state
- `cpu-fetch-test` — instruction fetch and stalled request handling
- `cpu-basic-exec-test` — `NOP`, `ADDI`, and `HALT`
- `cpu-alu-test` — register-register arithmetic and logic
- `cpu-memory-test` — `LDW`, `STW`, and data-memory stalls
- `cpu-control-test` — `BEQ`, `BNE`, and `J`
- `cpu-program-test` — deterministic end-to-end CPU program

The deterministic program exercises arithmetic and logic, load/store,
taken and not-taken branches, a backward conditional loop, an
unconditional jump, `NOP`, `HALT`, and the hardwired-zero behavior of
`r0`. Its simulation memory also introduces deterministic wait states.

The program test has an explicit timeout and automated PASS/FAIL result.
Its reported cycle count is a simulation sanity value only and is not an
FPGA performance, timing, or frequency claim.

The Milestone 1 `jupiter_cpu_stub` remains a subsystem-boundary placeholder
used by the Milestone 1 hierarchy test. It is separate from the functional
Milestone 2 CPU implementation.

## Milestone 3 Internal Bus and Memory Regression

Milestone 3 adds the initial Jupiter internal transaction mechanism,
memory map, internal/test RAM, MMIO scratch register, and integrated CPU
memory subsystem. The bus and memory-map contract is documented in
`docs/BUS_MEMORY_MAP.md`.

`make -C sim m3-test` runs five focused Milestone 3 tests:

- `interconnect-test` — address decoding, target selection, request forwarding,
  stalls, and deterministic invalid/unmapped behavior
- `internal-ram-test` — 4 KiB internal/test RAM reads, writes, independent
  locations, and byte write strobes
- `mmio-scratch-test` — reset behavior, MMIO reads/writes, byte strobes, and
  scratch-register state
- `cpu-subsystem-test` — CPU instruction fetch through the integrated
  CPU → interconnect → RAM path
- `cpu-memory-map-test` — deterministic CPU program exercising RAM store/load,
  MMIO write/readback, unmapped reads/writes, target selection, and HALT

The Milestone 3 integration program preloads the simulation RAM from the
testbench. This is simulation infrastructure and does not define a final
Jupiter boot or program-loading mechanism.

The CPU is the only implemented transaction master in Milestone 3, so no
runtime arbitration is required yet. Additional masters and arbitration policy
belong to later milestones.

Passing the host-side regression does not establish Quartus synthesis,
timing closure, FPGA resource usage, a final clock frequency, or physical
SuperStation One hardware operation.

## Milestone 4 External SDRAM Regression

`make -C sim m4-test` runs the currently implemented Milestone 4
external-memory regression:

- `interconnect-test` — external-SDRAM target decoding and request routing
- `cpu-subsystem-test` — integrated CPU/memory subsystem with SDRAM present
- `system-test` — system-wrapper regression with the SDRAM interface propagated
- `sdram-frontend-test` — 32-bit transaction conversion, installed-size
  gating, stalls, read reassembly, and byte strobes
- `sdram-controller-test` — initialization, command sequencing, and recurring
  refresh/maintenance
- `sdram-path-test` — frontend/controller/behavioral-memory round trips,
  physical address mapping, byte masks, refresh deferral across a logical
  32-bit transaction, and sustained repeated-access integrity while periodic
  refresh occurs
- `cpu-sdram-test` — deterministic CPU store/load through the Milestone 3
  interconnect and complete external-SDRAM path

The top-level `make -C sim test` aggregate includes `m4-test` in addition to
the previously established Milestone 1, CPU/Milestone 2, and Milestone 3
regressions.

The behavioral SDRAM model and host-side Icarus regressions validate
functional RTL behavior only. They do not establish Quartus timing closure,
FPGA resource usage, physical-SDRAM timing, or operation on SuperStation One
hardware.

## Milestone 5 GPU Register Regression

Run the standalone Milestone 5 GPU control-register regression with:

    make -C sim gpu-regs-test

`jupiter_gpu_2d_tb.sv` verifies the CPU-visible register contract before
system-interconnect or rendering integration.

The focused regression covers:

- register reset values;
- deterministic register reads and writes;
- byte write strobes;
- reserved-offset behavior;
- configuration snapshot on `CONTROL.START`;
- zero-dimension immediate completion;
- rejection of another start request while busy; and
- the intentional absence of fake completion for nonzero rendering in M5B-1.

The historical Milestone 1 `jupiter_gpu_stub` remains part of the stub
regression. The functional `jupiter_gpu_2d` module exists alongside that
placeholder during incremental Milestone 5 integration.

Passing this standalone register regression does not establish GPU SDRAM
arbitration, tile rendering, framebuffer correctness, live video output,
Quartus synthesis, timing closure, or physical-hardware operation.

### Milestone 5B-2 CPU-to-GPU MMIO Integration

Run the Milestone 5B register and CPU-integration aggregate with:

    make -C sim m5b-test

`cpu-gpu-mmio-test` executes a deterministic Jupiter CPU program through the
integrated interconnect. It verifies CPU construction of the `0x00001100`
GPU MMIO base, GPU register write/readback, zero-dimension `CONTROL.START`
completion, `STATUS.DONE`, reserved-register reads, target exclusivity, and
preservation of the existing scratch-MMIO state.

The interconnect regression also verifies both boundaries of the GPU control
aperture, request forwarding, stall/completion propagation, the unmapped
address immediately above the aperture, and non-overlapping target selection.

Milestone 5B-2 integrates CPU-visible GPU control only. It does not yet add a
GPU external-SDRAM master, CPU/GPU SDRAM arbitration, tile rendering, or live
GPU video output.
