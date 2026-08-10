# Jinix Jupiter Hardware Validation

## Current Status

Hardware validation status: NOT PERFORMED.

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

When Jupiter framebuffer scanout is integrated, verify known 2D and 3D
reference scenes on physical output rather than relying on the inherited demo
video path.

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

After physical framebuffer scanout exists, render deterministic tilemap
references and compare visible output with the simulation reference.

### 8. 3D Graphics

After physical framebuffer scanout exists, render deterministic flat,
depth-tested, textured, perspective-correct, and blended reference triangles.

### 9. Extended Stability

Run repeated resets and representative workloads for an extended interval.
Record hangs, visual corruption, audio failure, SDRAM instability, or
controller loss.

## Result Policy

Do not change this document to claim hardware PASS until the procedure is
actually executed on physical target hardware.

Partial hardware testing must clearly identify which categories were and were
not performed.
