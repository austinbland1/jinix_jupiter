# Jinix Jupiter v0.1-alpha — Known Limitations

Jinix Jupiter `v0.1-alpha` is a public developer preview. It is intentionally not presented as a finished or fully reliability-qualified console release.

## Fixed-function 3D

Fixed-function 3D is **not physically supported for gameplay in v0.1-alpha**.

The 3D renderer is implemented and simulation-validated, but current SuperStation One hardware bring-up exposes an unresolved implementation-sensitive video-link failure. Physical diagnostics have shown:

- original direct RGB reference: signal present, black picture;
- static `VGA_R[7] = 1`: no HDMI signal;
- static `VGA_B[7] = 1`: no HDMI signal;
- static `VGA_B[6] = 1`: no HDMI signal.

This rules out red-channel specificity and bit-7/MSB specificity as necessary conditions. It does **not** establish the final root cause.

See `docs/KNOWN_3D_ISSUE.md`.

## Controllers

The selected controller interface exposes raw MiSTer digital controller words through Jupiter MMIO.

Physical validation has demonstrated the D-pad path, sustained input, and rapid transitions. Complete face-button mapping, analog input, and software-configurable remapping are not claimed as fully supported in this alpha.

## Development tools

The current toolchain is intentionally low-level.

The repository provides a minimum Jupiter assembler and host-side system-image tooling. A mature C/C++ compiler toolchain, full relocatable linker/runtime, graphical debugger, polished asset pipeline, and one-click SDK are not part of the `v0.1-alpha` support claim.

## Reliability qualification

The verified subsystems have deterministic regression coverage and selected physical validation, but `v0.1-alpha` has not completed the long-duration qualification expected of a stable `1.0` release.

In particular, this alpha does not claim:

- exhaustive controller compatibility;
- exhaustive display compatibility;
- exhaustive SDRAM transaction-pattern coverage;
- overnight mixed-workload soak qualification;
- physically qualified fixed-function 3D;
- consumer-console-level stability certification.

## Verified physical 2D reference

The physical 2D validation baseline is tagged:

`hv8-2d-graphics-verified`

Verified 2D RBF SHA-256:

`84ecf987d86b47c285383947a7e3a1bcb9256fefce369290c2a0756da751e9a8`

That artifact is validation evidence; the eventual packaged public release RBF should be built and smoke-tested from the release-prep branch before publication.
