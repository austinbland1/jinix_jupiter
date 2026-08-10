# Jinix Jupiter Controller / Peripheral Architecture

## 1. Milestone 8 Scope

Milestone 8 introduces Jupiter's first CPU-visible controller-input subsystem.

The initial selected design intentionally adopts only the digital joystick
state already exposed by the verified MiSTer `hps_io` interface.

The selected implementation provides:

- six digital controller ports;
- one 32-bit state word per controller;
- direct bit-for-bit propagation from MiSTer `joystick_0` through
  `joystick_5`;
- CPU-visible read-only controller state;
- deterministic reserved-register behavior;
- no interrupt or event-latching mechanism;
- operation entirely in the existing `clk_sys` domain.

Analog sticks, keyboard, mouse, paddles, spinners, rumble, light guns, raw HID,
and other framework input facilities are not selected for the initial
Milestone 8 implementation.

---

## 2. Verified MiSTer Input Boundary

The repository's `sys/hps_io.sv` exposes the following digital joystick ports:

- `joystick_0[31:0]`;
- `joystick_1[31:0]`;
- `joystick_2[31:0]`;
- `joystick_3[31:0]`;
- `joystick_4[31:0]`;
- `joystick_5[31:0]`.

It also exposes analog joystick values, paddles, spinners, PS/2 keyboard and
mouse information, and rumble interfaces.

Those additional interfaces are verified framework capabilities but are not
automatically Jupiter features.

Milestone 8 deliberately selects only `joystick_0` through `joystick_5`.

The repository does not currently establish an authoritative semantic
button-name mapping for the 32 bits of each MiSTer joystick word. Jupiter
therefore does not invent one in this milestone.

The architectural contract is bit-preserving:

    Jupiter controller N state bit B = hps_io joystick_N bit B

for controller N = 0 through 5 and bit B = 0 through 31.

A later software/devkit layer may define symbolic names when the project has an
authoritative mapping to document.

---

## 3. Clock and Update Semantics

`hps_io` is instantiated with the existing Jupiter `clk_sys`.

The selected joystick signals therefore already enter the core as
`clk_sys`-domain registered values.

Milestone 8 does not add a second controller clock domain or an additional
synchronizer for these selected signals.

The controller peripheral contains no event FIFO and no software-visible input
latch.

A CPU read returns the current 32-bit controller value presented to the
controller peripheral for that transaction.

Once a selected `joystick_N` value changes at the Jupiter-side input, the
corresponding CPU-visible state changes without an additional intentional
controller-update delay.

Deterministic simulation will drive input changes away from ambiguous
same-edge testbench races and verify the resulting CPU-visible state.

---

## 4. CPU-Visible MMIO Aperture

Milestone 8 selects:

    0x00001400 - 0x000014FF

as the controller/peripheral MMIO aperture.

This follows the existing allocations:

    0x00001000 - 0x00001003   scratch MMIO
    0x00001100 - 0x000011FF   GPU control MMIO
    0x00001200 - 0x000012FF   DMA control MMIO
    0x00001300 - 0x000013FF   PCM audio MMIO
    0x00001400 - 0x000014FF   controller MMIO

The controller aperture does not overlap RAM, GPU, DMA, audio, or external
SDRAM.

---

## 5. Register Map

All selected registers are naturally aligned 32-bit registers.

| Address | Register | Access | Meaning |
|---|---|---|---|
| `0x00001400` | `CONTROLLER_0_STATE` | RO | Exact current `joystick_0[31:0]` |
| `0x00001404` | `CONTROLLER_1_STATE` | RO | Exact current `joystick_1[31:0]` |
| `0x00001408` | `CONTROLLER_2_STATE` | RO | Exact current `joystick_2[31:0]` |
| `0x0000140C` | `CONTROLLER_3_STATE` | RO | Exact current `joystick_3[31:0]` |
| `0x00001410` | `CONTROLLER_4_STATE` | RO | Exact current `joystick_4[31:0]` |
| `0x00001414` | `CONTROLLER_5_STATE` | RO | Exact current `joystick_5[31:0]` |
| `0x00001418`–`0x000014FC` | reserved | RO | Reads return zero |

The register words are not remapped, packed, filtered, edge-detected, or
translated by Jupiter.

---

## 6. Read and Write Behavior

A valid aligned read of one of the six implemented state registers:

- completes deterministically;
- returns the corresponding complete 32-bit controller word.

A valid aligned read of any reserved offset in the selected controller
aperture:

- completes deterministically;
- returns `0x00000000`.

Writes anywhere in the controller aperture:

- complete deterministically;
- do not modify controller state;
- do not alter unrelated Jupiter state.

Byte-write strobes therefore have no state-changing effect in the initial
read-only controller implementation.

Misaligned accesses retain the existing interconnect's deterministic invalid
transaction behavior.

---

## 7. Interrupt / Status Policy

Milestone 8 does not select an interrupt-on-controller-change mechanism.

There is no pending-event register, changed-bit register, acknowledgement
register, interrupt enable register, or interrupt output in the initial design.

Software polls the controller state registers when it needs input state.

The Milestone 8 acceptance criterion concerning an interrupt/status mechanism
is satisfied by documenting that no such mechanism is intentionally selected.

---

## 8. Production Integration Topology

The intended production path is:

    hps_io
      joystick_0..5
          |
          v
    Template.sv
          |
          v
    jupiter_system
          |
          v
    jupiter_cpu_subsystem
          |
          v
    jupiter_controllers
          |
          v
    jupiter_interconnect
          |
          v
       CPU MMIO

`Template.sv` will explicitly connect all six selected `hps_io` digital
joystick outputs.

The selected controller words will then be propagated through
`jupiter_system` into the CPU subsystem and controller peripheral.

No HPS-side game logic is introduced.

---

## 9. Initial Implementation Checkpoints

### M8B-1 — Controller MMIO and interconnect

Implemented and verified in simulation:

- `rtl/peripherals/jupiter_controllers.sv`;
- six 32-bit controller-state inputs;
- the selected read-only register map;
- deterministic reserved reads and ignored writes;
- the `0x00001400–0x000014FF` interconnect target;
- CPU-subsystem integration;
- focused peripheral, interconnect, and CPU-MMIO tests.

M8B-1 intentionally leaves the production `hps_io` connection for the next
checkpoint. `jupiter_system` supplies deterministic zero values to the six new
CPU-subsystem controller inputs until M8B-2.

### M8B-2 — Production MiSTer input wiring

Integrate:

- `hps_io.joystick_0` through `joystick_5` in `Template.sv`;
- corresponding `jupiter_system` ports;
- propagation into `jupiter_cpu_subsystem`;
- production wrapper/topology verification.

---

## 10. Deterministic Verification Plan

M8B-1 automated evidence currently includes:

- `controller-regs-test` for all six raw state registers, bit preservation,
  immediate visibility, reserved-zero behavior, and ignored writes;
- `interconnect-controller-test` for aperture decode, wait-state propagation,
  forwarding, alignment, boundary behavior, and preservation of adjacent
  audio/SDRAM targets;
- `cpu-controller-mmio-test` for CPU-visible reads/writes through the production
  CPU/interconnect/subsystem path and preservation of unrelated MMIO state;
- the legacy generic and audio interconnect regressions updated so the first
  unmapped aligned address after the controller aperture is `0x00001500`;
- the complete repository regression, which remains green with M8B-1 present.

Production `hps_io`/`Template.sv` propagation remains an M8B-2 verification
requirement.

Milestone 8 implementation tests must verify:

1. controller 0 through controller 5 each return their exact corresponding
   32-bit input word;
2. every bit position is preserved without remapping;
3. changing one controller does not alter another controller's state;
4. state changes become visible according to the documented no-extra-latch
   behavior;
5. reserved aligned offsets return zero;
6. writes to implemented and reserved controller offsets have no effect;
7. controller accesses do not corrupt scratch, GPU, DMA, audio, RAM, or SDRAM
   state;
8. the controller aperture does not overlap another interconnect target;
9. CPU reads through the production CPU/interconnect/subsystem path return the
   expected values;
10. all six selected MiSTer joystick outputs are connected exactly once through
    the production wrapper hierarchy;
11. unselected analog, keyboard, mouse, paddle, spinner, rumble, and other
    framework input facilities are not required for Milestone 8 acceptance;
12. all tests automatically report pass/fail;
13. all previously verified regressions continue to pass.

---

## 11. Features Not Selected for Initial Milestone 8

The initial implementation does not include:

- analog stick registers;
- keyboard input;
- mouse input;
- paddle input;
- spinner input;
- rumble output;
- light-gun input;
- raw HID reports;
- controller hot-plug events;
- controller-type identification;
- interrupt-on-change;
- changed-bit or edge-event latches;
- input FIFOs;
- software-configurable remapping.

These remain future design choices rather than hidden milestone requirements.

---

## 12. Milestone 8 Acceptance Boundary

Milestone 8 establishes deterministic CPU-visible digital controller state and
production propagation of the six selected MiSTer joystick words.

It does not establish a final controller API for all future Jupiter hardware,
a final human-readable button naming scheme, analog-controller support,
keyboard/mouse support, rumble, HID support, interrupt-driven input, or any
other unselected peripheral capability.

The milestone is complete when the selected six-port digital interface is
documented, implemented, integrated, and verified according to the acceptance
criteria in `docs/MILESTONES.md`.
