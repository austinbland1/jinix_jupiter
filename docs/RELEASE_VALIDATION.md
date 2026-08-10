# Jinix Jupiter Release Validation

## M11A Validation Baseline

M11A establishes a release-validation baseline without fabricating synthesis
or hardware results.

M11A regression result: PASS — the M11A-specific gate and the complete `make -C sim test` repository regression both completed successfully before this validation record was finalized.

## M11B Integration Validation

M11B framebuffer-scanout integration result: PASS.

The production path now includes the scanout MMIO/timing shell, deterministic
line-buffer framebuffer fetch, second-stage normal/scanout SDRAM arbitration,
system-level scanout integration, and direct MiSTer-facing RGB888/timing
propagation.

The dedicated production-boundary regression verifies known RGB565 red, green,
blue, and white pixels through `jupiter_system`, and the complete repository
regression passed after the visible-video cutover.

This is simulation evidence only. It is not a claim of Quartus synthesis,
timing closure, FPGA-image generation, or physical display validation.

## Automated Simulation

The authoritative repository regression command is:

    make -C sim test

The repository regression includes the historical M11A integration/release gate, the M11B scanout integration tests, and the M11C release-acceptance checker. Release-validation claims must remain consistent with those automated gates.

## Quartus Availability

Quartus availability: UNAVAILABLE on the current audited development machine.

The audit found all of the following commands absent:

- `quartus_sh`
- `quartus_map`
- `quartus_fit`
- `quartus_sta`
- `quartus_asm`
- `quartus_cpf`

Therefore the current Milestone 11 checkpoint makes no claim of:

- Quartus synthesis success;
- fitter success;
- timing closure or Fmax;
- FPGA resource utilization; or
- generation of a usable FPGA programming image.

This limitation is permitted by the Milestone 11 plan and must remain explicit
until actual Quartus evidence exists.

## Plain-Icarus Top-Level Probe

A diagnostic attempt to elaborate the complete MiSTer `emu` source graph with
the installed Icarus Verilog stopped because `Template.sv` includes generated
`build_id.v`, which was not present during the probe.

That diagnostic result is not a production RTL regression and is not a
substitute for a Quartus compilation. The normal subsystem and repository
simulation harnesses use their established compatibility environment.

## Hardware Validation

Hardware validation status: NOT PERFORMED for the current Milestone 11 checkpoint.

No successful SuperStation One or MiSTer-compatible hardware operation is
currently claimed.

The procedure to use when an actual FPGA image becomes available is recorded
in `docs/HARDWARE_VALIDATION.md`.

## Optional HPS Services

Milestone 11 currently selects no new optional HPS storage, networking, media,
file-loading, or save-data service for the initial release baseline.

The existing MiSTer `hps_io` framework boundary remains available for the
already integrated host-facing framework functions, including controller
state, status/configuration, and reported SDRAM configuration.

Normal Jupiter game logic remains FPGA-side and does not execute on the HPS
ARM processor.

## Milestone 11 Acceptance Closeout

Milestone 11 acceptance adjudication: PASS.

All seven documented Milestone 11 acceptance criteria are satisfied within
their stated evidence boundaries:

1. All required automated regressions pass, including the historical M11A
   integration/release gate, the M11C release/acceptance gate, and the complete
   repository simulation regression.
2. Integrated address decoding, display MMIO routing, SDRAM arbitration, and
   production system interfaces have automated regression coverage with no
   unresolved conflict, deadlock, or interface mismatch observed.
3. The framebuffer-scanout architecture discovered and finalized during
   integration is documented and regression-tested through the production
   system video boundary.
4. Quartus synthesis was not performed because Quartus was unavailable on the
   audited development machine. The conditional synthesis criterion was
   therefore not triggered, and no synthesis/resource/timing result is
   fabricated.
5. Physical SuperStation One / MiSTer-compatible hardware validation was not
   performed. The conditional hardware-results criterion was therefore not
   triggered, and no hardware PASS is claimed.
6. No new optional HPS service was selected, and normal Jupiter game logic
   remains FPGA-side.
7. Release documentation explicitly distinguishes simulation-verified behavior
   from unavailable Quartus validation and unperformed physical hardware
   validation.

Milestone 11 repository acceptance completion does not convert unavailable
Quartus synthesis or unperformed physical hardware validation into successful
results. Those limitations remain recorded as such.
