# Jinix Jupiter — Development Rules

This document governs implementation work on Jinix Jupiter.
Jupiter is a new fantasy console for MiSTer / SuperStation One.
These rules are intended to keep implementation incremental, testable, documented, and grounded in verified hardware facts.
Architecture still marked TBD must remain TBD until the appropriate milestone selects it.

## 1. Core Development Principles

- Jupiter is a new fantasy console, not an emulator of an existing historical system.
- Work milestone-by-milestone according to `docs/MILESTONES.md`.
- Do not implement later-milestone functionality merely because it appears convenient.
- Prefer small, testable changes over large multi-subsystem rewrites.
- Preserve known-good behavior while adding functionality incrementally.
- Architecture decisions still marked TBD remain TBD until deliberately selected and documented.
- Do not silently turn provisional targets into fixed requirements.
- Do not invent hardware facts, interfaces, capacities, clocks, addresses, or performance figures.

## 2. Simulation-First Rule

- New functional RTL should have deterministic simulation coverage where practical.
- Tests must clearly report pass/fail.
- Prefer small focused tests.
- Reproduce bugs with tests before or alongside fixes where practical.
- Prefer automated assertions/reference comparisons over relying only on waveform inspection.
- Existing applicable regressions must continue to pass.
- Hardware testing supplements simulation and does not replace it.
- Do not require a specific simulator yet.
- The simulation toolchain will be selected and documented during Milestone 1.
- Never claim a test was run if it was not actually run.

## 3. Architecture and Documentation Discipline

- Document architectural decisions made during implementation.
- Update `docs/ARCHITECTURE.md` when a previously TBD decision becomes established.
- Update roadmap/documentation when measured FPGA limitations justify a revision.
- Clearly distinguish:
  - verified MiSTer/template facts
  - implemented Jupiter behavior
  - provisional design targets
  - unresolved/TBD decisions
- Never document speculative behavior as implemented fact.
- Architecture may be revised when FPGA resource, timing, or memory-bandwidth evidence justifies it.
- Significant revisions should state why the previous assumption changed.

## 4. RTL Organization

Use these existing primary subsystem locations:

- `rtl/cpu/`
- `rtl/gpu/`
- `rtl/audio/`
- `rtl/memory/`
- `rtl/dma/`
- `rtl/peripherals/`

- Keep modules focused on clear responsibilities.
- Avoid giant monolithic modules when clean subsystem boundaries are practical.
- Module and file names should describe actual function.
- Do not create duplicate directory structures for the same subsystem.
- Additional directories may be created when genuinely useful.
- Significant repository-structure changes should be documented.
- Preserve the MiSTer framework/template boundary rather than casually rewriting framework code.
- Do not prescribe exact future module filenames before implementation requires them.

## 5. RTL Coding Rules

- Use explicit signal widths.
- Avoid unintended implicit nets.
- Production RTL must use synthesizable constructs unless code is explicitly simulation-only.
- Distinguish combinational and sequential logic clearly.
- Avoid inferred latches unless intentional and documented.
- Define reset behavior intentionally.
- Document clock-domain crossings.
- Synchronize asynchronous inputs appropriately.
- Never assume unsynchronized signals are safe across clock domains.
- Use nonblocking assignments for ordinary clocked sequential logic.
- Use blocking assignments for ordinary combinational logic.
- Avoid unexplained magic constants; prefer named parameters/localparams where practical.
- Comments should explain why unusual timing/resource-sensitive logic exists rather than narrating obvious syntax.
- Do not prescribe unresolved CPU, GPU, SDRAM, audio, or peripheral clock frequencies.

## 6. Clock and Reset Discipline

- Every clock domain must be identified and documented.
- Reset polarity, source, and behavior must be explicit for Jupiter-owned logic.
- Clock-domain crossings require an intentional synchronization or CDC mechanism.
- Generated clocks and PLL changes require understanding of the existing MiSTer template first.
- Do not casually alter template PLL or board-level clocking simply for subsystem convenience.
- Do not claim the whole design uses a single clock domain unless verified.
- Clock/reset assumptions used in simulations must match the documented design.

## 7. Memory and Bus Discipline

- Memory-map changes must be documented.
- Memory-map regions must not overlap.
- Once unmapped-access behavior is defined, it must be deterministic and tested.
- Bus/interconnect behavior must match its documented protocol.
- Arbitration behavior must be documented.
- Arbitration changes require deterministic tests.
- CPU, DMA, GPU, audio, and other bus masters must not rely on undocumented priority assumptions.
- Memory-corruption tests should accompany DMA, graphics, audio, and external-memory work where applicable.
- External SDRAM implementation decisions must be based on verified MiSTer-facing interfaces rather than assumptions.
- Do not nominate an existing MiSTer SDRAM-related support file as Jupiter's controller, bridge, or wrapper unless analysis establishes that role.
- Memory widths, timings, burst behavior, scheduling, and arbitration remain design decisions until established by the appropriate milestone.

## 8. FPGA Resource and Timing Discipline

- Never claim synthesis success unless Quartus actually completed successfully.
- Never claim timing closure without an actual timing report.
- Never claim FPGA resource utilization without an actual synthesis/resource report.
- Never invent Fmax, LUT, FF, DSP, BRAM, memory-bandwidth, polygon-throughput, pixel-throughput, audio-voice capacity, or other performance/resource figures.
- Provisional performance goals may be revised based on measured results.
- Resource or timing regressions should be documented once synthesis becomes part of the workflow.
- Quartus availability is not assumed.
- If Quartus or required device support is unavailable, state that clearly rather than fabricating results.
- Hardware-validation claims require actual hardware testing.
- A generated bitstream must not be described as working hardware merely because compilation succeeded.

Do not prescribe any unresolved clock frequency or performance target.

## 9. Software and Firmware Rules

Use these existing directories:

- `software/bios/`
- `software/devkit/`
- `software/tools/`

- BIOS behavior must follow the documented Jupiter boot architecture.
- Jupiter boot firmware is original Jupiter software, not copied historical firmware.
- Tools generating machine code must agree with `docs/ISA_SPEC.md`.
- Host tools should fail clearly on invalid input rather than silently emit malformed output.
- Executable, object, image, and asset formats must be documented when selected.
- Generated software artifacts should be reproducible where practical.
- Firmware storage/loading behavior must be documented once selected.
- Do not assume a particular compiler implementation language.
- Do not assume a particular binary/object format before it is selected.
- Do not assume a particular boot storage medium.
- Do not assume a particular debugger transport.
- Do not assume a particular firmware-loading mechanism.

## 10. HPS Boundary

- HPS assistance is optional.
- HPS may assist with storage, networking, media, file loading, save data, or other host-facing services if intentionally adopted.
- Normal Jupiter game logic must execute in the FPGA-side Jupiter architecture, not on the HPS ARM CPU.
- Any adopted HPS interface or protocol must be based on verified MiSTer interfaces and documented.
- Do not invent HPS transport mechanisms.
- The Jupiter architecture must not silently become dependent on HPS processing for ordinary gameplay behavior.
- Optional HPS assistance should have a clearly documented boundary between host-facing work and Jupiter hardware behavior.

## 11. Change and Commit Discipline

- Inspect `git status` before and after significant implementation work.
- Keep commits focused when commits are made.
- Do not combine unrelated subsystem changes without a documented reason.
- Commit messages should describe the functional change.
- Do not commit generated build products unless intentionally required.
- Do not rewrite unrelated user work.
- Do not discard uncommitted work merely to obtain a clean working tree.
- Do not automatically reset, clean, checkout, restore, or delete unrelated changes.
- Do not commit or push unless explicitly instructed.
- Milestone completion does not itself require a commit.
- Verify that intended files were actually written before reporting task completion.

Do not require a particular branching model.

## 12. Definition of Done for Implementation Tasks

A future implementation task is complete only when the applicable items below are satisfied:

- The requested implementation exists on disk.
- Relevant documentation is updated.
- Deterministic tests exist where practical.
- Relevant tests pass.
- Existing applicable regressions still pass.
- No known unrelated functionality was broken.
- Memory or state corruption has been checked where relevant.
- No synthesis, timing, resource, or hardware claim is made without actual evidence.
- `git status` has been inspected.
- Remaining limitations and unresolved/TBD items are stated rather than hidden.
- Commands claimed as executed were actually executed.
- The implementation remains within the requested milestone/task boundary.

Not every task requires every item, but omitted items should be appropriate to the task's scope.

## 13. Rules for Autonomous/AI Development

- Inspect only enough context to perform the bounded task.
- Prefer editing early rather than spending the entire task planning.
- Obey the requested milestone and task boundary.
- Do not implement adjacent features without instruction.
- Do not invent hardware facts.
- Do not silently make TBD architectural decisions.
- Do not claim tests were run if they were not run.
- Do not claim Quartus synthesis succeeded if it was not actually run successfully.
- Do not claim timing closure without an actual timing report.
- Do not claim hardware testing occurred unless it actually occurred.
- Do not modify unrelated files.
- Do not commit or push unless explicitly instructed.
- Report incomplete work clearly.
- If a task cannot be completed within the available execution window, leave completed work intact and state exactly what remains.
- Prefer deterministic commands, simulations, assertions, and reference comparisons over prose assertions that something works.
- Verify created or edited files exist before reporting completion.
- Avoid broad repository exploration when the bounded task already provides enough context.
- Do not spend the entire task rereading documentation when a direct edit is requested.

Do not mention any particular AI model, provider, or service by name.
