# Jupiter Core — Milestone 1A Simulation Smoke Test

## Quick start

```sh
make -C sim test
```

This command runs the smoke test with Icarus Verilog.

## Simulator / tool selected

**Icarus Verilog (`iverilog` + `vvp`) is the only simulator for this milestone.**

No supported simulator is currently detected in the OpenHands environment. Icarus Verilog requires both `iverilog` and `vvp` to be installed.

The RTL and testbench have been created but have not yet been compiled or executed because Icarus Verilog is not currently available in the OpenHands environment.

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

`make -C sim test` now runs both the original `jupiter_core` smoke test and
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
