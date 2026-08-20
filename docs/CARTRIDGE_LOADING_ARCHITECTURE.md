# Jinix Jupiter — Milestone 12 Cartridge Loading Architecture

## 1. Status

This document proposes the architecture for **Milestone 12**, which adds
runtime loading of game images larger than Jupiter's internal RAM into
external SDRAM, and CPU control transfer into a loaded image.

M12 has not been implemented. No RTL, ISA revision, or host tooling
described here exists in the repository yet. This document is the
architecture contract implementation must satisfy, in the same sense that
`docs/BOOT_ARCHITECTURE.md` recorded the M9A architecture before M9B–M9D
implemented it.

This document does not modify `docs/BUS_MEMORY_MAP.md`,
`docs/SDRAM_ARCHITECTURE.md`, `docs/DMA_ARCHITECTURE.md`, or
`docs/ISA_SPEC.md`. It defines additions layered on top of them; those
documents remain the normative source for everything they already define.

Milestone 11 explicitly left this feature unselected. `KNOWN_LIMITATIONS.md`
states: "The initial M11 release baseline adopts no new HPS-assisted
storage, networking, media, runtime file-loading, or save-data protocol."
M12 is that deferred work, picked back up.

---

## 2. Design Goals

M12 must make it possible to:

1. select a `.jup` cartridge image from the MiSTer OSD file browser;
2. stream that image from the SD card into external SDRAM, at a size
   limited only by installed SDRAM capacity rather than the 4 KiB internal
   RAM;
3. transfer CPU control from BIOS into the loaded image;
4. do this without the HPS ARM processor executing any Jupiter game logic,
   consistent with the Milestone 11 non-goal: "the HPS must remain an
   optional I/O/network/media assistant and must not become Jupiter's
   normal game CPU" (`docs/MILESTONES.md`);
5. do this without weakening or reworking any already-verified subsystem —
   `jupiter_sdram_controller`, `jupiter_sdram_frontend`, and
   `jupiter_sdram_arbiter` are left unmodified;
6. reject an oversized or malformed image deterministically rather than
   silently corrupting memory or hanging, consistent with the existing
   system-wide principle in `docs/BUS_MEMORY_MAP.md` §8: "Jupiter requires
   deterministic behavior rather than hanging the CPU."

---

## 3. Existing Constraints Reused

M12 deliberately reuses four pieces of already-verified or already-present
architecture rather than inventing new ones.

**3.1 The MiSTer HPS download interface already exists and is unused.**
`sys/hps_io.sv` (stock MiSTer framework code) exposes `ioctl_download`,
`ioctl_index`, `ioctl_wr`, `ioctl_addr[26:0]`, `ioctl_dout`, and
`ioctl_wait`. No Jupiter RTL currently references any `ioctl_*` signal, and
`Template.sv` instantiates `hps_io` without connecting them. `ioctl_addr`
is 27 bits — exactly 128 MiB, matching Jupiter's maximum SDRAM aperture.

**3.2 The CPU already fetches instructions through the general memory
bus.** Per `rtl/cpu/jupiter_cpu.sv`, instruction fetch, `LDW`, and `STW`
all issue the same `mem_valid`/`mem_addr` transaction (also documented in
`docs/ISA_SPEC.md` §7: "The same interface is used for: instruction
fetches; LDW; STW"). No CPU RTL change is required for the CPU to execute
code from SDRAM.

**3.3 A two-stage SDRAM arbitration pattern already exists.**
`jupiter_sdram_arbiter` performs the Milestone 6 three-way CPU/GPU/DMA
round robin. `jupiter_sdram_scanout_arbiter` sits downstream of it and
merges that arbitrated stream with the read-only video-scanout master,
explicitly documented as leaving "that first-stage arbitration policy
unchanged." M12 adds a third stage in the same shape rather than modifying
either existing arbiter.

**3.4 Host-side image tooling conventions already exist.**
`software/devkit/jupiter_asm.py` emits a flat, deterministic 32-bit word
stream. `software/tools/build_system_image.py` combines and validates such
streams with deterministic rejection of malformed input. `.jup` packaging
reuses both.

---

## 4. Selected Architecture Overview

At a high level:

1. A new `.jup` file is registered as an OSD-selectable, top-level
   file-load menu entry.
2. Selecting it drives `ioctl_download` high with a matching
   `ioctl_index`. `hps_io` streams the file byte-by-byte.
3. A new module, `jupiter_loader`, accumulates four bytes per 32-bit
   Jupiter word and writes them into external SDRAM starting at
   `0x10000000`, auto-incrementing.
4. While a matching download is active, Jupiter's CPU, GPU, DMA, audio,
   and video-scanout subsystems are held in a dedicated **core reset** so
   that they cannot fetch, render, or contend for SDRAM against a memory
   image that is still being written.
5. A new **loader arbiter** stage gives `jupiter_loader` exclusive,
   uncontested use of the shared SDRAM path while it is active. Because of
   (4), this is never genuinely contested; the stage exists for
   deterministic, defined behavior at the reset/completion boundary rather
   than for steady-state fairness.
6. When the download completes, core reset releases. BIOS resumes
   execution at `0x00000000`, reads a small fixed-offset header out of
   SDRAM, and transfers control into the loaded image with a new indirect
   jump instruction, `JMPR`.

This keeps `jupiter_sdram_controller`, `jupiter_sdram_frontend`, and
`jupiter_sdram_arbiter` byte-for-byte unmodified. It also avoids building
genuine four-way concurrent SDRAM arbitration, which M12 does not need:
nothing else should be running while a new cartridge is being written into
the memory it is about to occupy.

---

## 5. Reset Domain Split

Today, a single `reset` signal (`Template.sv`: `RESET | status[0] |
buttons[1]`) reaches every subsystem uniformly through `jupiter_system` →
`jupiter_cpu_subsystem`.

M12 splits this into two domains inside `jupiter_cpu_subsystem`:

| Domain | Drives | Held during a matching download? |
| --- | --- | --- |
| `reset` (unchanged) | `jupiter_loader`, the new `jupiter_sdram_loader_arbiter`, `jupiter_sdram_frontend`, `jupiter_sdram_controller`, `jupiter_internal_ram` | No — the loader's downstream memory path must stay operational to receive the image |
| `core_reset = reset \|\| loader_active` (new) | `jupiter_cpu`, `jupiter_gpu_2d`, `jupiter_dma`, `jupiter_audio`, `jupiter_video_scanout`, `jupiter_sdram_arbiter`, `jupiter_sdram_scanout_arbiter` | Yes |

`loader_active` is asserted for the full duration of a matching
`ioctl_download`. Because `jupiter_cpu`'s `mem_valid` is already gated by
`!reset` (`assign mem_valid = !reset && ...`), holding `core_reset` high is
sufficient to guarantee the CPU issues zero SDRAM requests during a load;
GPU and DMA follow the same existing gating pattern on their own SDRAM
master interfaces.

**M12C exact-source boundary correction.** The M12C1 preflight found that
both existing game-path arbiters retain a non-preemptive `grant_state` until
the selected upstream requester is still `valid` when downstream `ready`
returns. Resetting only the requester can therefore strand a stale grant if
a download begins during an outstanding SDRAM transaction. M12C drives the
*existing reset ports* of `jupiter_sdram_arbiter` and
`jupiter_sdram_scanout_arbiter` with `core_reset` as well; their source files
and internal grant logic remain byte-for-byte unchanged. The new downstream
`jupiter_sdram_loader_arbiter` latches any game transaction already presented
before `core_reset`, drains that transaction non-preemptively, and only then
grants the loader. This preserves a live loader-to-frontend path while
guaranteeing the pre-existing game arbiters restart from `GRANT_NONE` after
the download.

Screen blanking and audio silence during a cartridge load are the
expected, normal result of this — the same behavior MiSTer users already
see on other cores while a ROM loads.

---

## 6. `jupiter_loader` Module

### 6.1 CPU-Visible MMIO Aperture

Following the existing 256-byte-per-target, `0x100`-spaced pattern in
`docs/BUS_MEMORY_MAP.md` §5, M12 selects:

    0x00001500 - 0x000015FF

as the CPU-visible loader aperture — the next unused slot after the
Milestone 8 controller-input aperture.

| Address | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x1500` | `STATUS` | R | Bit 0 = LOADING, bit 1 = DONE, bit 2 = OVERFLOW |
| `0x1504` | `LOAD_SIZE` | R | Bytes written for the most recent matching download |
| `0x1508` | `LOAD_BASE` | R | Hardwired constant: always reads `0x10000000` |

Unused aligned offsets within the aperture read as zero and ignore writes,
matching every other MMIO target's reserved-offset behavior.

There is no `CONTROL`/`START` register. Unlike DMA, a load is not
initiated by CPU software — it is initiated by the person selecting a file
in the OSD. Software's role is entirely read-side: poll `STATUS`, then
act.

**`LOAD_BASE` exists to solve a real constraint, not for convenience.**
Jupiter's ISA has no instruction that constructs a large 32-bit constant —
`ADDI`'s immediate is 14 bits (`docs/ISA_SPEC.md` §4.2), far short of
`0x10000000`. `docs/BUS_MEMORY_MAP.md` §7 already established the pattern
this follows: "The low address [`0x00001000`] is intentional: the current
minimal ISA can construct `0x00001000` directly with its existing `ADDI`
instruction." `LOAD_BASE` extends that same pattern — BIOS reaches the
loader's low, `ADDI`-constructible MMIO address, then one `LDW` returns
the SDRAM base as an ordinary 32-bit value, with no new instruction
required to build it.

`STATUS` and `LOAD_SIZE` reset to zero on `reset` (not on `core_reset`,
since the loader itself is not in the `core_reset` domain — see §5).
`DONE` and `OVERFLOW` are sticky and clear only on `reset` or on the start
of the next matching download, mirroring `docs/DMA_ARCHITECTURE.md` §4's
existing `DONE` semantics.

### 6.2 OSD / `ioctl` Wiring

`Template.sv` gains a real, top-level (not page-gated, not `d0`-disabled)
`CONF_STR` file-load entry, replacing the inherited, never-wired Template
placeholder line:

    F1,JUP;

This assigns `ioctl_index = 1` to `.jup` files. `jupiter_loader` only acts
while `ioctl_download && (ioctl_index == 8'h01)`; a download for any other
index passes through unobserved.

### 6.3 Byte Accumulation and Address Generation

`hps_io` is instantiated without `WIDE`, so `ioctl_dout` delivers one byte
per `ioctl_wr` pulse and `ioctl_addr` increments by one per byte.
`jupiter_loader` accumulates four such bytes, low byte first, into a
32-bit shift register, and issues one aligned SDRAM write per complete
word:

    write_addr = LOAD_BASE + (words_written << 2)

`write_addr` begins at `LOAD_BASE` (`0x10000000`) and auto-increments by
four bytes per completed word, mirroring the increment convention already
used by `jupiter_dma`'s source/destination addressing
(`docs/DMA_ARCHITECTURE.md` §2).

If `ioctl_download` falls with 1–3 bytes accumulated but not yet a
complete word, that partial word is discarded rather than written. A
correctly built `.jup` file (§8) is always a whole number of words; this is
a defined fallback for malformed input, not an expected path.

### 6.4 Capacity Enforcement

`jupiter_loader` compares `write_addr` against the same installed-capacity
ceiling `jupiter_cpu_subsystem` already computes from `sdram_sz[1:0]` for
video scanout. If the next word would exceed installed capacity:

- no further SDRAM write is issued;
- incoming bytes continue to be accepted and discarded, so the HPS-side
  transfer is not stalled indefinitely;
- `STATUS.OVERFLOW` is set and remains set until the next matching
  download or reset.

Software is expected to check `OVERFLOW` before trusting a loaded image;
§9 describes BIOS doing exactly this.

### 6.5 Backpressure

`ioctl_wait` is asserted whenever `jupiter_loader` has an SDRAM write
outstanding and the loader arbiter (§7) has not yet returned `ready` for
it — the same `valid`/`ready` wait-state idiom used everywhere else in
Jupiter's bus, projected outward through the one `hps_io` signal built for
exactly this purpose.

---

## 7. `jupiter_sdram_loader_arbiter`

A new third arbitration stage, named and shaped after the existing
`jupiter_sdram_scanout_arbiter`, is inserted between that module's output
and `jupiter_sdram_frontend`'s input:

    jupiter_sdram_arbiter (CPU/GPU/DMA)
        -> jupiter_sdram_scanout_arbiter (+ video scanout)
            -> jupiter_sdram_loader_arbiter (+ loader)   <- new
                -> jupiter_sdram_frontend (unchanged)
                    -> jupiter_sdram_controller (unchanged)

Two inputs: the aggregate "game" stream from `jupiter_sdram_scanout_arbiter`,
and `jupiter_loader`'s own master interface. `jupiter_loader` is
structurally write-only at this boundary — it never reads SDRAM — the same
asymmetry `jupiter_sdram_scanout_arbiter` already documents in the other
direction ("Scanout is structurally incapable of writing SDRAM").

Because §5's reset domain split guarantees the game stream is silent
whenever the loader is active, this stage does not need genuine
round-robin fairness. The selected policy is simple non-preemptive
priority: `jupiter_loader` wins the next free arbitration point whenever
it is requesting; the game stream is served otherwise. This is
deliberately simpler than `jupiter_sdram_arbiter`'s or
`jupiter_sdram_scanout_arbiter`'s contested-round-robin logic, because true
contention between the two paths is not an expected condition — only a
defined boundary case.

`jupiter_sdram_arbiter` and `jupiter_sdram_scanout_arbiter` are not
modified. Their internal `grant_state` encodings, each already sized to
their existing number of masters, are untouched.

---

## 8. The `.jup` Format

A `.jup` file is a fixed 32-byte header followed by a flat 32-bit word
payload — the same payload shape `jupiter_asm.py` already emits. All
header fields are 32-bit little-endian words, matching Jupiter's own byte
order (`docs/ISA_SPEC.md` §3), so BIOS reads them with ordinary `LDW` and
no byte-swapping.

| Byte offset | Field | Meaning |
| --- | --- | --- |
| `0x00` | `MAGIC` | Bytes `'J','U','P','1'` (`0x4A,0x55,0x50,0x31`); read as one `LDW` word this is `0x3150554A` |
| `0x04` | `FORMAT_VERSION` | `1` for this revision |
| `0x08` | `IMAGE_LENGTH_BYTES` | Total file length, header included, as declared by the packaging tool |
| `0x0C` | `ENTRY_OFFSET` | Byte offset from `LOAD_BASE` to the first instruction to execute |
| `0x10` | `CHECKSUM` | Additive checksum of all payload words following the header |
| `0x14`–`0x1F` | reserved | Must be zero |
| `0x20`+ | payload | Flat 32-bit word stream (raw Jupiter machine code / data) |

For a header-immediately-followed-by-code image, `ENTRY_OFFSET = 0x20`.
Nothing in the format requires that; it is only the expected common case.

The header is a **software-level convention only**. `jupiter_loader` does
not parse it, compare `MAGIC`, or interpret any field — it is a dumb byte
mover, exactly as `jupiter_dma` is a dumb word mover. Every non-goal in
`docs/DMA_ARCHITECTURE.md` §2 that excludes content-dependent hardware
behavior (no descriptor chains, no scatter/gather) applies here for the
same reason: keeping content interpretation in software keeps the hardware
small, deterministic, and independent of the format's own evolution.

---

## 9. BIOS Integration

The Milestone 9 boot flow (`docs/BOOT_ARCHITECTURE.md`) is unchanged:
reset places `PC` at `0x00000000`, and BIOS executes from internal RAM.
M12 extends BIOS behavior once it is already running:

1. poll `STATUS.DONE` (loop while clear — a cold boot with no cartridge
   loaded simply never sets it, and BIOS spins, matching a MiSTer core
   sitting idle until a ROM is selected);
2. once `DONE` is set, check `STATUS.OVERFLOW`; if set, do not proceed
   (behavior beyond "do not proceed" — some error indication — is left to
   a later, non-M12 decision);
3. `LDW` `LOAD_BASE` from `0x1508` into a register;
4. `LDW` the word at `LOAD_BASE + 0x00` and compare against `MAGIC`
   (`0x3150554A`); if it does not match, do not proceed;
5. `LDW` `ENTRY_OFFSET` from `LOAD_BASE + 0x0C`;
6. `ADD` `LOAD_BASE + ENTRY_OFFSET` into a register;
7. `JMPR` to that register.

No step requires constructing a 32-bit constant from scratch — step 3
obtains the only large constant BIOS needs (§6.1), and every other value
involved is either already in a register or small enough for `LDW`'s
existing 14-bit immediate.

---

## 10. ISA Revision: `JMPR`

`docs/ISA_SPEC.md` §8 already anticipates this: "The Milestone 2 ISA does
not provide indirect jumps, calls, returns, or link instructions. Those
may be introduced by a later ISA revision if required." M12 is that
revision, and it introduces exactly one instruction.

| Opcode | Mnemonic | Format | Operation |
| --- | --- | --- | --- |
| `0x33` | `JMPR` | I | `PC = rs1 + sign_extend(imm14)` |

`0x33` is the next unused opcode in the existing control-flow group
(`0x30` `BEQ`, `0x31` `BNE`, `0x32` `J`). `JMPR` reuses the existing
I-format bit layout unchanged (`docs/ISA_SPEC.md` §4.2) — `rd` is encoded
as zero and reserved, matching the existing convention for unused fields.

Semantics, deliberately parallel to `J`'s existing definition:

- the target must satisfy `target[1:0] == 2'b00`, the same alignment
  contract already defined for `LDW`/`STW`;
- `JMPR` does not write a link register, exactly as `J` does not;
- subroutine-call and return conventions remain outside M12's scope,
  exactly as `docs/ISA_SPEC.md` §6.12 already states they are outside
  Milestone 2's.

`software/devkit/jupiter_asm.py` gains one mnemonic-table entry; no new
format, no assembler architecture change.

---

## 11. Host Tooling

A new `software/tools/build_cartridge.py`, sibling to
`build_system_image.py`, wraps an already-assembled `jupiter_asm.py` word
stream in the §8 header. Following `build_system_image.py`'s existing
deterministic-rejection conventions, it must reject:

- a payload whose length is not a whole number of 32-bit words;
- an explicitly specified `ENTRY_OFFSET` outside the resulting image;
- malformed input word text (reusing `build_system_image.py`'s existing
  word-text validation);

and it must exit nonzero on any rejection rather than emit a
partially-valid file.

It computes `IMAGE_LENGTH_BYTES` and `CHECKSUM` itself; both are
deterministic functions of its validated input.

---

## 12. Non-Goals

M12 does not implement:

- a filesystem, directory browsing, or media-mount semantics in FPGA
  fabric — the HPS/Linux side already provides file browsing, and Jupiter
  fabric never sees more than a byte stream;
- save data or any non-volatile write-back path;
- compression;
- multiple simultaneous cartridge slots, bank switching, or cartridge
  swapping without a reset;
- concurrent background loading while a game is running — §5's
  reset-domain split is deliberately exclusive, not concurrent;
- a configurable load base address — `LOAD_BASE` is fixed at
  `0x10000000`;
- cryptographic signing or authentication of images;
- a link-register-capable `CALL`/`RET` pair — `JMPR` alone is sufficient
  for a one-way BIOS-to-application handoff;
- SD block-device / sector-mounted media (`img_mounted`, `sd_lba`,
  `sd_buff_*`) — that is a materially different, heavier mechanism suited
  to media that should not be fully SDRAM-resident, not to this
  milestone's goal;
- any change to `jupiter_sdram_controller`, `jupiter_sdram_frontend`,
  `jupiter_sdram_arbiter`, or `jupiter_sdram_scanout_arbiter`'s internal
  grant logic.

Those remain available for later milestones, and none of them is required
for a cartridge larger than 4 KiB to load and run.

---

## 13. Verification Plan

Following the pattern established by `docs/DMA_ARCHITECTURE.md` §10 and
§12, M12 verification must cover:

1. `jupiter_loader` reset state (`STATUS`, `LOAD_SIZE` clear);
2. `ioctl_index` gating — a non-matching download produces no SDRAM writes
   and no state change;
3. byte-to-word accumulation, including a non-word-aligned trailing
   partial word being discarded;
4. address auto-increment from `LOAD_BASE` across a multiword download;
5. `OVERFLOW` behavior at the installed-capacity boundary, for each of the
   32 MiB / 64 MiB / 128 MiB / no-SDRAM configurations;
6. `core_reset` assertion for the full duration of a matching download and
   clean release on completion;
7. CPU/GPU/DMA/video-scanout quiescence — no SDRAM requests from any of
   them while `core_reset` is asserted, and both existing game-path arbiters
   return to `GRANT_NONE`;
8. `jupiter_sdram_loader_arbiter` priority behavior, including draining a
   game transaction already in flight when `core_reset` asserts, and clean
   resumption of the game path after a load completes;
9. `ioctl_wait` correctly reflects backpressure from the shared SDRAM
   path;
10. CPU-visible `STATUS`/`LOAD_SIZE`/`LOAD_BASE` MMIO readback;
11. `JMPR` semantics: target computation, the alignment contract, and that
    no link register is written;
12. an end-to-end boot-to-application test in the shape of the existing
    `m9c-test`: a simulated `ioctl_download` of a minimal valid `.jup`
    image, BIOS polling `DONE`, validating `MAGIC`, computing the target,
    executing `JMPR`, and the loaded application reaching `HALT`;
13. host-side rejection tests for `build_cartridge.py`: bad magic on
    reassembly-check, declared length mismatching actual payload,
    non-word-aligned payload, out-of-range `ENTRY_OFFSET`;
14. full regression — `make -C sim test` continues passing unchanged,
    demonstrating no disturbance to CPU, GPU, SDRAM, DMA, audio,
    controller, or arbitration behavior verified by earlier milestones.

As with every prior milestone, this verification plan establishes
simulation correctness. It does not by itself establish Quartus synthesis,
timing closure, FPGA resource usage, or successful operation on
SuperStation One / MiSTer-compatible hardware — those require the same
actual build-and-test step every other Jupiter subsystem still has ahead
of it per `docs/KNOWN_LIMITATIONS.md`.

---

## 14. Deferred Questions

- Whether a future milestone wants genuine concurrent background loading
  (streaming a next level while gameplay continues) — this would require
  revisiting §5's exclusivity design and giving
  `jupiter_sdram_loader_arbiter` real round-robin fairness.
- Whether `CHECKSUM` should become a stronger function (e.g. CRC32) once
  real-world corruption modes are observed; the additive checksum selected
  here is a minimum, not a claim of strength.
- Whether more than one `ioctl_index` / OSD slot is ever wanted (e.g. a
  separate slot for a BIOS/firmware image distinct from a cartridge).
- Whether `LOAD_BASE` belongs in a more general location once software
  other than the boot handoff wants Jupiter's SDRAM base as a constant.
- Whether a future ISA revision wants a link-writing `CALL`/`RET` pair now
  that `JMPR` establishes indirect control flow exists at all; M12
  deliberately does not walk through that door.
- Whether SD block-device-mounted media is ever justified by a cartridge
  exceeding installed SDRAM, or by streamed assets that should not be
  fully SDRAM-resident.

---

## 15. Planned M12 Checkpoints

### M12A — Architecture selection

This document.

### M12B — Host tooling

`build_cartridge.py` and its deterministic-rejection tests.

### M12C — RTL: loader, reset split, loader arbiter, OSD wiring

`jupiter_loader`, the `core_reset` split inside `jupiter_cpu_subsystem`,
`jupiter_sdram_loader_arbiter`, and the `Template.sv` `CONF_STR`/`hps_io`
wiring.

### M12D — ISA revision

`JMPR` in `docs/ISA_SPEC.md`, the CPU RTL, and `jupiter_asm.py`.

### M12E — BIOS integration and closeout

BIOS handoff sequence, the end-to-end boot-to-application simulation test,
and full-suite regression.
