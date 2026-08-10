# Jinix Jupiter Release Validation

## M11A Validation Baseline

M11A establishes a release-validation baseline without fabricating synthesis
or hardware results.

M11A regression result: PASS — the M11A-specific gate and the complete `make -C sim test` repository regression both completed successfully before this validation record was finalized.

## Automated Simulation

The authoritative repository regression command is:

    make -C sim test

M11A will add an automated static integration/release checker before its
regression closeout. A PASS entry will be recorded only after both the
M11A-specific gate and the complete repository regression finish successfully.

## Quartus Availability

Quartus availability: UNAVAILABLE on the audited M11A development machine.

The audit found all of the following commands absent:

- `quartus_sh`
- `quartus_map`
- `quartus_fit`
- `quartus_sta`
- `quartus_asm`
- `quartus_cpf`

Therefore M11A makes no claim of:

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

Hardware validation status: NOT PERFORMED for the M11A baseline.

No successful SuperStation One or MiSTer-compatible hardware operation is
claimed by M11A.

The procedure to use when an actual FPGA image becomes available is recorded
in `docs/HARDWARE_VALIDATION.md`.

## Optional HPS Services

M11A selects no new optional HPS storage, networking, media, file-loading, or
save-data service for the initial release baseline.

The existing MiSTer `hps_io` framework boundary remains available for the
already integrated host-facing framework functions, including controller
state, status/configuration, and reported SDRAM configuration.

Normal Jupiter game logic remains FPGA-side and does not execute on the HPS
ARM processor.
