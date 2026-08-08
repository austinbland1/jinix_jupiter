# Jinix Jupiter — Milestone 1 Simulation

## Quick start

```sh
make -C sim test
```

This command runs the full Milestone 1 regression with Icarus Verilog.

## Simulator / tool selected

**Icarus Verilog (`iverilog` + `vvp`) is the only simulator for this milestone.**

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
