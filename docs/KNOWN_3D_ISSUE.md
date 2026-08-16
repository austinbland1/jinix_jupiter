# Known Issue — Fixed-Function 3D Physical Video-Link Failure

**Release affected:** `v0.1-alpha`
**Status:** open / hardware bring-up paused at a reproducible resume point

## Summary

Jinix Jupiter's fixed-function 3D subsystem is implemented and has deterministic simulation coverage, but the current physical SuperStation One bring-up cannot yet support 3D gameplay reliably.

The original physically loaded reference implementation establishes HDMI signal but a black visible picture. Subsequent tightly controlled RGB-boundary diagnostics show that small synthesized output-cone perturbations can cause the HDMI link itself to disappear.

## Key physical observations

| Implementation | Result |
|---|---|
| Original direct RGB reference | `SIGNAL_PLUS_BLACK` |
| Full 24-bit runtime RGB mux | `NO_SIGNAL` |
| Runtime one-bit `VGA_R[7]` override | `NO_SIGNAL` |
| Static `VGA_R[7] = 1` | `NO_SIGNAL` |
| Static `VGA_B[7] = 1` | `NO_SIGNAL` |
| Static `VGA_B[6] = 1` | `NO_SIGNAL` |

The tested static candidates retained 23 of 24 RGB bits as direct reference paths and used no runtime selector or RGB mux.

## What has been ruled out

The evidence is sufficient to reject these as necessary conditions:

- runtime selector dependence;
- runtime RGB mux dependence;
- full 24-bit mux width;
- mass RGB-cone pruning;
- red-channel specificity;
- single-channel specificity;
- bit-7 / MSB specificity.

A non-MSB `VGA_B[6]` static override also reproduces the no-signal failure.

## What is not yet proven

The root cause is still unknown.

The evidence does **not** yet prove a specific:

- routing or placement mechanism;
- internal timing mechanism;
- IO-cell/pin-route mechanism;
- RGB-content mechanism;
- electrical/static-high mechanism.

## Exact next discriminator

When hardware bring-up resumes, the next experiment keeps the same blue channel and bit position while changing only the forced value:

```systemverilog
assign VGA_R = video_r;
assign VGA_G = video_g;
assign VGA_B[7] = video_b[7];
assign VGA_B[6] = 1'b0;
assign VGA_B[5:0] = video_b[5:0];
```

This asks whether the failure is associated specifically with forcing that cone high (`1`) or whether the implementation sensitivity persists when the same bit is statically forced low (`0`).

The local bring-up evidence was intentionally frozen before that experiment so the investigation can resume without reconstructing prior state.

## Release policy

Until a physical 3D reference scene is repeatably visible and subsequent 3D qualification passes, fixed-function 3D is considered **experimental / not physically supported** in public Jupiter releases.
