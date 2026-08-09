# Jinix Jupiter PCM Audio Architecture

## 1. Milestone 7 Scope

Milestone 7 introduces Jupiter's first functional PCM playback and mixing
hardware.

This document selects the initial architecture. It does not claim a final
long-term audio capability or measured FPGA capacity.

The initial selected design provides:

- four hardware PCM voices;
- signed 16-bit mono source samples;
- independent left/right volume per voice;
- deterministic stereo PCM mixing;
- one source sample consumed per active voice per 48 kHz output sample;
- shared internal sample RAM;
- CPU-visible audio control through MMIO;
- signed 16-bit stereo output to the existing MiSTer core audio interface.

The provisional project goal of roughly 32-64 voices remains provisional.
Four voices are selected only as the bounded initial Milestone 7
implementation. No larger FPGA voice capacity is claimed without synthesis,
resource, timing, and hardware evidence.

## 2. Verified MiSTer Audio Boundary

The actual MiSTer core-facing interface provides:

- `CLK_AUDIO`, documented by the framework as 24.576 MHz;
- `AUDIO_L[15:0]`;
- `AUDIO_R[15:0]`;
- `AUDIO_S`, where 1 identifies signed samples;
- `AUDIO_MIX[1:0]`.

The framework already owns `audio_out`, I2S, S/PDIF, filtering, and physical
audio-output handling.

Jupiter therefore does not instantiate its own copy of those framework
modules.

For the selected Jupiter interface:

- `AUDIO_L` receives Jupiter's mixed signed 16-bit left sample;
- `AUDIO_R` receives Jupiter's mixed signed 16-bit right sample;
- `AUDIO_S` is 1;
- `AUDIO_MIX` is 0.

Jupiter does not use the MiSTer mono-mixing modes for the initial stereo
implementation.

## 3. Clocking and Sample Tick

The existing Jupiter system clock is currently 20 MHz.

The initial PCM engine, sample RAM control, voice state, mixer, and audio MMIO
all remain in that existing `clk_sys` domain.

A separate Jupiter audio clock domain is not introduced in the initial
Milestone 7 implementation.

Jupiter generates an exact-average 48 kHz sample tick from the current
20 MHz `clk_sys` using a fractional phase accumulator:

- phase increment = 48,000;
- modulus = 20,000,000;
- emit one sample tick whenever the accumulated value reaches or exceeds the
  modulus;
- subtract the modulus after the tick.

At the current clock this produces the repeating spacing:

    417, 417, 416 clk_sys cycles

for an exact average of 48,000 output updates per second.

This is a selected behavior for the current implemented 20 MHz Jupiter clock.
It is not an Fmax or future-clock requirement.

The mixed `AUDIO_L` and `AUDIO_R` samples are held stable between output
updates.

MiSTer's existing `audio_out` path operates in its framework-owned
24.576 MHz audio domain and already resynchronizes stable `core_l` and
`core_r` values. Jupiter therefore does not add another audio-output CDC
mechanism in the initial design.

## 4. Sample Format

The selected source format is:

- signed two's-complement PCM;
- 16 bits per sample;
- mono source data;
- logical source rate of 48 kHz;
- no compression;
- no interpolation;
- no pitch conversion in the initial implementation.

Stereo output is produced by applying separate left and right volume values
to each mono source sample.

## 5. Internal Sample RAM

The initial implementation uses a shared internal PCM sample RAM rather than
external SDRAM.

Selected capacity:

    4096 x 16-bit samples

This is 8192 bytes of sample storage.

Valid sample indices are:

    0x000 - 0xFFF

This capacity is intentionally bounded for the first implementation and is
not a claim about the final Jupiter audio-memory architecture.

Audio is not a fourth external-SDRAM master in Milestone 7.

The verified Milestone 6 CPU/GPU/DMA three-master SDRAM arbiter remains
unchanged.

The Milestone 6 DMA engine also remains unchanged and does not gain
audio-triggered transfers.

## 6. CPU-Visible Audio MMIO

Milestone 7 selects the following audio MMIO aperture:

    0x00001300 - 0x000013FF

This follows the existing GPU aperture at `0x1100-0x11FF` and DMA aperture at
`0x1200-0x12FF`.

All accesses are aligned 32-bit Jupiter bus transactions.

Reserved aligned registers read as zero and ignore writes.

Byte-write strobes are honored for writable registers.

### 6.1 Global Registers

| Address | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x1300` | `SAMPLE_ADDR` | R/W | Low 12 bits select PCM RAM sample index |
| `0x1304` | `SAMPLE_DATA` | R/W | Low 16 bits contain the selected signed PCM sample |
| `0x1308` | `OUTPUT_L` | R | Current mixed left sample, sign-extended to 32 bits |
| `0x130C` | `OUTPUT_R` | R | Current mixed right sample, sign-extended to 32 bits |
| `0x1310` | `SAMPLE_COUNT` | R | 32-bit count of completed mixed-output updates |
| `0x1314-0x131F` | Reserved | - | Reads zero, writes ignored |

`SAMPLE_COUNT` resets to zero and wraps naturally at 32 bits.

A `SAMPLE_DATA` access may hold MMIO `ready` low while the audio playback
sequencer owns the shared sample-RAM port. Other audio control/status
register accesses do not require ownership of the sample-RAM data port.

This prevents undefined CPU/playback collisions without requiring audio to
become an external-memory master.

## 7. Voice Organization

Four voices are implemented.

Each voice occupies a 0x20-byte register block.

| Voice | Base address |
| --- | --- |
| Voice 0 | `0x1320` |
| Voice 1 | `0x1340` |
| Voice 2 | `0x1360` |
| Voice 3 | `0x1380` |

The per-voice register layout is:

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `+0x00` | `CONTROL` | W | Command bits described below |
| `+0x04` | `STATUS` | R | Bit 0 ACTIVE, bit 1 DONE |
| `+0x08` | `BASE` | R/W | Low 12 bits = first sample index |
| `+0x0C` | `LENGTH` | R/W | Low 13 bits = requested sample count |
| `+0x10` | `VOLUME_L` | R/W | Low 8 bits = left volume |
| `+0x14` | `VOLUME_R` | R/W | Low 8 bits = right volume |
| `+0x18` | `POSITION` | R | Number of samples consumed by the active/recent playback |
| `+0x1C` | Reserved | - | Reads zero, writes ignored |

### 7.1 CONTROL

`CONTROL` command bits are:

- bit 0: `START`;
- bit 1: `STOP`;
- bit 2: `CLEAR_DONE`.

Commands are recognized when byte strobe 0 is asserted.

Command processing is deterministic:

1. `CLEAR_DONE`, if requested, clears DONE;
2. `STOP` has priority over `START`;
3. otherwise `START` begins or restarts playback.

`START` while already active restarts that voice from its configured BASE.

A successful nonzero-length START:

- snapshots BASE;
- derives and snapshots the effective playback length;
- sets POSITION to zero;
- clears DONE;
- sets ACTIVE.

A zero-length START:

- sets POSITION to zero;
- clears ACTIVE;
- sets DONE;
- consumes no sample.

`STOP` clears ACTIVE without setting DONE.

### 7.2 Effective Length

Playback never wraps implicitly beyond sample RAM.

The effective length is:

    min(configured LENGTH, 4096 - BASE)

Therefore a requested range extending beyond sample index 4095 is truncated
at the end of internal sample RAM.

No automatic wrap or looping is selected for the initial implementation.

### 7.3 Volume

Each voice has independent unsigned 8-bit left and right volume values.

For one channel, the contribution is derived from:

    signed_sample * unsigned_volume

The product is interpreted with an 8-bit fractional volume scale.

Therefore:

- volume 0 = mute;
- volume 255 = 255/256 of source amplitude.

This avoids an integer divide-by-255 datapath and makes the arithmetic
deterministic.

Volume registers are live while a voice is active. BASE and effective LENGTH
are snapshotted by START.

## 8. Playback Semantics

At each Jupiter 48 kHz sample tick:

1. every active voice contributes the sample at its current source position;
2. each contribution is scaled independently for left and right output;
3. all active contributions are accumulated;
4. the final left and right results are saturated to signed 16-bit PCM;
5. `AUDIO_L` and `AUDIO_R` update;
6. `SAMPLE_COUNT` increments;
7. each active voice advances by one source sample.

The sample at the pre-increment position contributes to the current mixed
output.

When the final sample of a voice has contributed:

- POSITION advances to the effective length;
- ACTIVE clears;
- DONE sets.

DONE remains set until another START or an explicit CLEAR_DONE command.

## 9. Mixer Arithmetic

Each signed 16-bit source sample is multiplied by an unsigned 8-bit channel
volume.

The implementation must retain sufficient signed width for each product and
for the sum of all four voices.

The selected reference arithmetic is equivalent to:

    left_sum =
        sample0 * volume0_left +
        sample1 * volume1_left +
        sample2 * volume2_left +
        sample3 * volume3_left

    right_sum =
        sample0 * volume0_right +
        sample1 * volume1_right +
        sample2 * volume2_right +
        sample3 * volume3_right

The signed accumulated value is then arithmetically shifted right by 8 bits.

The result is saturated to:

    -32768 .. +32767

before becoming the 16-bit output sample.

Arithmetic right-shift behavior is part of the reference result and therefore
must be reproduced by simulation tests.

The RTL may be written so Quartus can infer FPGA DSP resources where
advantageous, but Milestone 7 does not claim that any particular multiplier
is mapped to a DSP block without an actual synthesis/resource report.

## 10. Shared Sample-RAM Scheduling

The initial architecture allows the audio engine to serialize sample-RAM
reads across the four voices during each output-sample period.

This avoids requiring four independent physical sample-memory read ports.

The exact internal number of sequencer cycles is an implementation detail,
provided that:

- every active voice contributes exactly once per output tick;
- mixed output is deterministic;
- all four voice reads complete before the next output update is committed;
- CPU `SAMPLE_DATA` accesses wait when necessary rather than colliding with
  playback memory access.

No memory-port-count or inferred-BRAM claim is made until synthesis evidence
exists.

## 11. Features Not Selected for Initial Milestone 7

The initial implementation does not include:

- external-SDRAM audio fetching;
- a fourth SDRAM master;
- DMA-triggered audio streaming;
- pitch control;
- sample-rate conversion;
- interpolation;
- hardware looping;
- waveform synthesis;
- ADSR envelopes;
- filters inside the Jupiter PCM engine;
- interrupts;
- descriptors;
- compressed audio formats;
- per-voice effects;
- more than four implemented voices.

These are future design choices rather than hidden requirements.

## 12. Deterministic Verification Plan

Milestone 7 implementation tests must cover:

1. reset clears voice state, outputs, sample address, and sample count;
2. audio MMIO reserved reads/writes behave deterministically;
3. byte-write strobes behave as documented;
4. PCM sample RAM reads reproduce previously written values;
5. sample-RAM accesses wait safely while playback owns the shared port;
6. zero-length START completes immediately with no sample consumption;
7. nonzero START begins at the configured BASE;
8. STOP clears ACTIVE without falsely reporting natural completion;
9. START while active deterministically restarts playback;
10. DONE is sticky and CLEAR_DONE works;
11. effective length truncates safely at the end of sample RAM;
12. one voice produces exact expected signed PCM output;
13. POSITION advances exactly once for every consumed source sample;
14. independent left/right volume produces exact expected stereo values;
15. all four voices mix against a software/reference calculation;
16. positive mixer overflow saturates to +32767;
17. negative mixer overflow saturates to -32768;
18. inactive voices contribute zero;
19. unrelated sample RAM and system state are not corrupted;
20. `SAMPLE_COUNT` advances exactly once for each committed output update;
21. the generated sample-tick sequence matches the documented 20 MHz to
    48 kHz phase-accumulator behavior;
22. CPU-visible audio MMIO works through the production Jupiter interconnect;
23. `AUDIO_L`, `AUDIO_R`, `AUDIO_S`, and `AUDIO_MIX` connect through the
    production Jupiter system/top-level interface without port mismatches;
24. previously verified CPU, SDRAM, GPU, and DMA regressions remain green.

## 13. Milestone 7 Acceptance Boundary

Milestone 7 establishes Jupiter's first deterministic hardware PCM voice and
mixing subsystem and integrates its signed stereo samples with the verified
MiSTer-facing core audio interface.

Milestone 7 does not establish:

- a final Jupiter voice count;
- final audio RAM capacity;
- external-memory streaming bandwidth;
- FPGA DSP usage;
- FPGA resource utilization;
- Fmax or timing closure;
- physical-hardware audio quality;
- physical-hardware success.

Those claims require later design decisions, synthesis reports, or actual
hardware testing.
