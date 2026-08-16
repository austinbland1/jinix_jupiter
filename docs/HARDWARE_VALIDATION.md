# Jinix Jupiter Hardware Validation

## Current Status

Hardware validation status: PARTIAL — selected 2D, audio, controller, and bring-up paths have physical evidence; fixed-function 3D physical output remains unresolved.

M11A does not claim successful operation on SuperStation One or other
MiSTer-compatible hardware.

This document defines the procedure to follow after a real Quartus build
produces an FPGA image.

## Required Test Record

Each hardware-validation run must record:

- exact Git commit and verified milestone tag, if present;
- Quartus version and device-support version;
- source project used (`Template` or the justified legacy variant);
- generated FPGA image identity or checksum;
- target hardware and SDRAM configuration;
- display connection and mode;
- test date; and
- pass/fail notes for every category below.

## Procedure

### 1. Configuration and Reset

1. load the generated image using the normal target-hardware workflow;
2. verify the core configures without repeated reset or configuration failure;
3. exercise cold/core reset behavior; and
4. verify the system returns to deterministic initial behavior.

### 2. Video

Verify stable video timing and visible output on the target display.

Verify known 2D and 3D reference scenes through the integrated framebuffer
scanout on physical output and compare them with the simulation references.

Record any resolution, crop, sync, color, or display-compatibility problem.

### 3. Controllers

Verify the selected MiSTer digital controller path for the intended controller
ports and confirm visible software-observable state changes.

### 4. Audio

Verify signed stereo PCM output, silence after reset, basic playback, and
multi-voice mixing without obvious channel reversal or persistent corruption.

### 5. External SDRAM

Verify initialization, repeated read/write operation, installed-size handling,
and sustained operation long enough to expose refresh or physical-timing
problems.

### 6. DMA and Shared-Memory Contention

Exercise CPU, GPU, and DMA external-memory activity and verify that the system
does not hang or visibly corrupt unrelated state.

### 7. 2D Graphics

Render deterministic tilemap references through the integrated framebuffer
scanout and compare visible output with the simulation reference.

### 8. 3D Graphics

Render deterministic flat, depth-tested, textured, perspective-correct, and
blended reference triangles through the integrated framebuffer scanout.

### 9. Extended Stability

Run repeated resets and representative workloads for an extended interval.
Record hangs, visual corruption, audio failure, SDRAM instability, or
controller loss.

## Result Policy

Do not change this document to claim hardware PASS until the procedure is
actually executed on physical target hardware.

Partial hardware testing must clearly identify which categories were and were
not performed.

## v0.1-alpha Public Release Boundary — 2026-08-15

The `v0.1-alpha` developer preview intentionally makes a **partial physical-validation claim**, not an all-categories/stable-console claim.

For release purposes:

- the verified physical 2D baseline is `hv8-2d-graphics-verified` at `1aa919e2424bc8fd0cd94d2278cacf2be5493826`;
- the verified physical 2D reference RBF SHA-256 is `84ecf987d86b47c285383947a7e3a1bcb9256fefce369290c2a0756da751e9a8`;
- physical PCM-audio validation has demonstrated silence, left/right/stereo playback, and simultaneous two-voice playback/mixing without obvious persistent corruption during the recorded test;
- the selected digital controller path has physically demonstrated D-pad input, sustained input, and rapid transitions, while complete face-button mapping/analog/remapping remain limited or unproven;
- fixed-function 3D is **not physically supported** because the current hardware bring-up has a reproducible implementation-sensitive HDMI/video-link failure;
- long-duration mixed-workload soak qualification remains future work.

Accordingly, this document must not be read as claiming full Hardware Validation PASS or `1.0`-class reliability for `v0.1-alpha`.
