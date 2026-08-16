# Jinix Jupiter v0.1-alpha — First Public Developer Preview

This is the first public alpha release of Jinix Jupiter, a new fantasy-console FPGA platform for MiSTer-compatible hardware including the SuperStation One.

## Release focus

`v0.1-alpha` is intended for low-level homebrew, experimentation, and contributor development. It is not a finished consumer-stable `1.0`.

## Included architecture

The release exposes the current Jupiter platform including:

- custom 32-bit Jupiter CPU / ISA;
- internal memory and CPU-visible MMIO;
- external SDR SDRAM support;
- DMA and shared CPU/GPU/DMA memory arbitration;
- hardware-assisted 2D graphics / framebuffer path;
- initial four-voice signed PCM audio system;
- raw digital controller MMIO;
- minimal BIOS/system-image workflow;
- Jupiter assembler and host-side image tooling;
- fixed-function 3D RTL and simulation support as an experimental subsystem.

## Physical support boundary

The verified physical gameplay path for this alpha is **2D**.

The prior verified 2D baseline is:

- tag: `hv8-2d-graphics-verified`
- commit: `1aa919e2424bc8fd0cd94d2278cacf2be5493826`
- physical reference RBF SHA-256: `84ecf987d86b47c285383947a7e3a1bcb9256fefce369290c2a0756da751e9a8`

A release RBF will be rebuilt and smoke-tested from the release-prep branch before the GitHub release is tagged/published.

## Fixed-function 3D

Fixed-function 3D is not physically supported in this release.

The 3D engine is implemented and simulation-tested, but hardware bring-up currently exposes an unresolved implementation-sensitive HDMI/video-link failure. See `docs/KNOWN_3D_ISSUE.md` for the reproducible findings and preserved next experiment.

## Known limitations

See `KNOWN_LIMITATIONS.md`.

## Developer entry point

See `docs/DEVELOPER_QUICKSTART.md`.

## Stability statement

Selected subsystems have deterministic simulation coverage and physical validation, but this alpha has not completed the long-duration mixed-workload reliability qualification required for a future stable/`1.0` claim.

Bug reports, homebrew experiments, hardware test results, tooling improvements, and reproducible validation evidence are welcome.
