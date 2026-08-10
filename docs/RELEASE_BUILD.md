# Jinix Jupiter Release Build

## Status

This document describes the intended Milestone 11 release-build workflow.

The current development machine does not have Intel Quartus installed, so the
Quartus steps below are documented build instructions rather than a claim that
a release FPGA image has been produced on this machine.

## Quartus Project Structure

The current project uses the inherited MiSTer project structure:

- `Template.qpf` / `Template.qsf` are the normal project entry files.
- `Template_Q13.qpf` / `Template_Q13.qsf` provide the legacy project variant.
- the Quartus top-level entity is `sys_top`;
- `sys/sys.qip` registers the MiSTer framework sources, including
  `sys/sys_top.v`, `sys/hps_io.sv`, and `sys/emu_ports.vh`;
- `files.qip` registers Jupiter's developer-owned production RTL; and
- `Template.sv` contains the MiSTer `emu` module and instantiates
  `jupiter_system`.

Jupiter production RTL must remain in `files.qip`. Simulation-only
compatibility stubs under `sim/` must never be added to the synthesis source
list.

## Build Prerequisites

A release build requires:

1. Intel Quartus with device support compatible with the inherited MiSTer
   project;
2. the complete repository checkout, including the `sys/` framework sources;
3. a clean source tree at the release commit; and
4. any generated MiSTer build files required by the project flow, including
   the build identifier used by `Template.sv`.

The currently audited development machine does not satisfy prerequisite 1.

## GUI Build Procedure

When Quartus and the required device support are available:

1. open `Template.qpf` in Quartus;
2. confirm `sys_top` is the top-level entity;
3. confirm the project includes the framework source graph and `files.qip`;
4. run a full compilation;
5. preserve the actual compilation, fitter, resource, and timing reports;
6. confirm that the programming image is generated successfully; and
7. do not describe the image as hardware-validated until the separate hardware
   procedure has actually been performed.

The legacy `Template_Q13.qpf` variant may be used only with a compatible
legacy Quartus workflow.

## Command-Line Build

Where `quartus_sh` is installed, the normal Quartus project-flow form is:

    quartus_sh --flow compile Template

For the legacy project variant:

    quartus_sh --flow compile Template_Q13

These commands are documented for the project structure but have not been
executed on the current development machine because `quartus_sh` is absent.

## Required Evidence Before Release Claims

A release build may claim synthesis success only when an actual Quartus run
completes successfully.

Timing closure may be claimed only from the actual timing report.

FPGA resource utilization may be reported only from actual Quartus output.

Physical SuperStation One / MiSTer-compatible operation may be claimed only
after the generated image is tested on real target hardware and the results are
recorded in `docs/HARDWARE_VALIDATION.md`.
