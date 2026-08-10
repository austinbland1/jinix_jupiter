# Jinix Jupiter Known Limitations

## Validation Limits

The M11A development machine does not have Intel Quartus installed.

Consequently, the current release baseline has no verified Quartus synthesis,
fitter, timing-closure, Fmax, or FPGA-resource result.

No FPGA image produced from the M11A baseline has yet been validated on a
SuperStation One or other MiSTer-compatible target.

## Video Integration

The production `jupiter_system` still preserves the inherited `mycore
video_demo` path for visible video timing/output.

The implemented Jupiter 2D and 3D engines render deterministic framebuffer
content and are extensively verified in simulation, but the current top-level
video output is not yet a scanout of Jupiter's rendered framebuffer.

This is an explicit Milestone 11 integration item, not a claim of completed
Jupiter gameplay video output.

## Quartus-Generated Framework Inputs

A plain-Icarus diagnostic elaboration of the complete MiSTer `emu` source
graph stops at the missing generated `build_id.v` include.

The normal repository simulation suite remains independent of that generated
top-level build input.

## Optional HPS Services

The initial M11 release baseline adopts no new HPS-assisted storage,
networking, media, runtime file-loading, or save-data protocol.

Existing MiSTer framework interaction is not permission to move normal Jupiter
game logic onto the HPS ARM processor.

## Boot and Software Environment

The verified initial boot flow uses the selected build-time BIOS/system-image
workflow established by Milestone 9.

A richer runtime filesystem loader, general-purpose operating environment,
compiler toolchain, debugger transport, or HPS firmware-update mechanism is
not part of the verified initial release baseline.

## Feature Scope

The implemented 2D engine is the selected deterministic tile/background
renderer rather than the full long-term sprite/blitter roadmap.

The implemented 3D engine is the selected bounded fixed-function triangle
renderer rather than a programmable modern GPU.

Audio remains the verified initial four-voice PCM architecture.

Future feature expansion must not be described as implemented until its own
RTL and deterministic validation exist.
