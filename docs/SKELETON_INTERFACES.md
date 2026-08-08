# Jinix Jupiter — Milestone 1 Skeleton Interfaces

## Purpose

This document records the concrete RTL hierarchy and subsystem boundaries
established during Milestone 1.

Milestone 1 defines integration boundaries only. It does not define the final
CPU ISA, system bus protocol, memory map, DMA protocol, graphics command
interface, audio architecture, or peripheral register layout.

Those interfaces remain TBD for later milestones.

## Current MiSTer Integration Hierarchy

The current synthesizable integration path is:

    Template.sv / emu
            |
            +-- jupiter_system
                    |
                    +-- jupiter_core
                    |
                    +-- mycore

`Template.sv` remains the MiSTer-facing `emu` implementation.

`jupiter_system` is the Jupiter-owned integration wrapper. It currently
contains the minimal `jupiter_core` skeleton while preserving the original
template `mycore` video path.

`jupiter_core` currently contains only deterministic Milestone 1 skeleton
state used by simulation.

`mycore` continues to provide the known-good template video behavior. It is
retained so later Jupiter implementation work can proceed incrementally
without discarding the verified output path.

## Clock Domain

The current hardware skeleton uses the existing MiSTer template `clk_sys`
clock domain.

`Template.sv` generates `clk_sys` through the existing template PLL and passes
that clock into `jupiter_system`.

`jupiter_system` currently passes that same clock to both `jupiter_core` and
the preserved `mycore` path.

Milestone 1 does not define a final Jupiter operating frequency or any
additional Jupiter-specific clock domains.

The simulation testbenches may use deterministic testbench clock periods for
verification. Those testbench periods are not hardware frequency
specifications.

## Reset Behavior

The MiSTer-facing reset is currently derived in `Template.sv` as:

    RESET | status[0] | buttons[1]

This reset is active high and is passed into `jupiter_system`.

`jupiter_core` uses a synchronous active-high reset.

The subsystem placeholder modules expose an active-high `reset` input as part
of the Milestone 1 boundary. They contain no functional state or behavior.

Future milestones may refine subsystem-specific reset requirements if the
architecture requires them.

## Future Subsystem Boundaries

Milestone 1 establishes the following placeholder modules:

| Subsystem | Placeholder module | Current interface |
| --- | --- | --- |
| CPU | `jupiter_cpu_stub` | `clk`, `reset` |
| Memory / bus | `jupiter_memory_stub` | `clk`, `reset` |
| DMA | `jupiter_dma_stub` | `clk`, `reset` |
| Graphics | `jupiter_gpu_stub` | `clk`, `reset` |
| Audio | `jupiter_audio_stub` | `clk`, `reset` |
| Peripherals | `jupiter_peripherals_stub` | `clk`, `reset` |

These modules are boundary placeholders only.

They intentionally do not yet define:

- address or data buses;
- request/acknowledge handshakes;
- interrupt routing;
- DMA request protocols;
- GPU command or memory interfaces;
- audio sample or mixer interfaces;
- controller/peripheral register interfaces;
- SDRAM controller interfaces.

Those contracts must be introduced by the milestone responsible for each
architecture decision rather than invented prematurely during Milestone 1.

The six subsystem stubs are not currently instantiated by `jupiter_system`.
They establish future RTL ownership boundaries and are compiled together by
the Milestone 1 stub-hierarchy simulation.

## Simulation Structure

`make -C sim test` runs three Milestone 1 tests:

1. `jupiter_core_tb` verifies deterministic state and reset behavior in the
   minimal Jupiter skeleton.
2. `jupiter_system_tb` verifies the Jupiter wrapper and compares its preserved
   video, pixel-enable, blanking, and sync outputs against a direct `mycore`
   reference.
3. `jupiter_stubs_tb` instantiates all six future subsystem placeholders and
   verifies that the complete placeholder set elaborates and executes without
   unresolved module/interface errors.

The M1B integration test compares the preserved output path cycle-for-cycle
for 320000 clock cycles.

## Simulation-Only Template Compatibility Models

`sim/template_compat_stubs.sv` provides simulation-only models for the
template `lfsr` and `cos` helpers.

These exist because the current Icarus Verilog environment does not directly
support all syntax/vendor primitives used by the original template RTL.

They are testbench infrastructure only.

They must not:

- be added to `files.qip`;
- replace the original FPGA RTL;
- be treated as synthesizable Jupiter implementation.

## Verification Boundary

Milestone 1 verification establishes that:

- the Jupiter skeleton simulations compile and execute under Icarus Verilog;
- deterministic smoke tests report pass/fail;
- the Jupiter integration wrapper preserves the known-good template output
  behavior under simulation;
- all six future subsystem boundary stubs elaborate together.

Milestone 1 verification does not establish:

- Quartus synthesis success;
- timing closure;
- FPGA resource utilization;
- hardware operation on SuperStation One;
- CPU, GPU, DMA, audio, SDRAM, or peripheral functionality.

Those claims require later implementation and verification.
