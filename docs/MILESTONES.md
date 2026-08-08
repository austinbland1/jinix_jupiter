# Jinix Jupiter — Development Roadmap

Ordered milestones for the Jinix Jupiter fantasy-console MiSTer / SuperStation One FPGA core. This document is a living plan; provisional targets marked TBD may be revised based on FPGA resource, timing, memory-bandwidth, and integration measurements taken during implementation.

---

## Milestone 0 — Architecture and Repository Foundation

**Status:** In progress. Complete only when ARCHITECTURE.md, MILESTONES.md, and DEVELOPMENT_RULES.md all exist in `docs/` and intended repository directories are confirmed present, with Quartus availability verified.

### Objective
Document the MiSTer template integration, architecture direction, development rules, repository structure, and this roadmap so future milestones have a stable reference and clear governance.

### Concrete Deliverables
- `docs/ARCHITECTURE.md` — comprehensive design-direction document distinguishing verified-fact sections from proposed-design sections.
- MILESTONES.md (this file) — the ordered milestone roadmap.
- `docs/DEVELOPMENT_RULES.md` — repository workflow, coding conventions, simulation mandates, commit discipline, and verification requirements.
- Intended repository directories created under `rtl/cpu/`, `rtl/gpu/`, `rtl/audio/`, `rtl/memory/`, `rtl/dma/`, `rtl/peripherals/`, `sim/`, `software/bios/`, `software/devkit/`, `software/tools/` (empty but present).

### Acceptance Criteria
- [ ] ARCHITECTURE.md exists and covers: verified-fact section derived from template RTL (`sys_top`, `emu`, `hps_io`, PLL, existing video/audio chains, SDRAM bus state, `files.qip`), proposed sections for CPU/ISA, bus, memory map, DMA, GPU/2D, 3D, audio, BIOS, devkit tools, HPS services, unresolved questions.
- [ ] MILESTONES.md exists and enumerates milestones 0–11 below.
- [ ] DEVELOPMENT_RULES.md exists and covers: simulation-first mandate, Quartus/timing-closure claims discipline, commit-message conventions, RTL naming/style rules, documentation-before-implementation rule, branching strategy.
- [ ] All intended repository directories listed above are present in the working tree (empty is acceptable).

### Non-Goals
- No RTL implementation.
- No new hardware design or specification beyond documentation.
- Do not modify `docs/ARCHITECTURE.md` content at this phase — its content was already established; Milestone 0 is complete when the file exists and has been read/verified by a subsequent milestone.

### Prerequisites for Next Milestone
- ARCHITECTURE.md, MILESTONES.md, and DEVELOPMENT_RULES.md all exist in `docs/`.
- Intended repository directories are present.
- Quartus availability has been checked and documented; if Quartus is unavailable on the development machine that fact may be documented and Milestone 0 may still complete. Never claim synthesis or timing results that were not actually obtained.

---

## Milestone 1 — Simulation and System Skeleton

### Objective
Establish a minimal Jupiter-specific RTL hierarchy, simulation/testbench infrastructure, and architectural documentation of subsystem boundaries so future milestones have a stable integration baseline. Preserve a simple known-good output path suitable for incremental integration testing.

The exact Jupiter hierarchy beneath or in conjunction with the existing MiSTer template (Template.sv / emu) is determined during this milestone. No particular top-level filename is mandated at this stage.

### Concrete Deliverables
- A minimal Jupiter-specific RTL hierarchy integrated cleanly with the existing MiSTer template (`emu` as defined in Template.sv — which remains under MiSTer-template governance). The representative form and boundaries of a Jupiter top-level wrapper or companion module, if any, is a design decision made during this milestone.
- Placeholder/stub module files (representative naming, not mandated) defining the boundaries for future CPU, bus/memory, DMA, graphics, audio, and peripheral subsystems — only stub/placeholder interfaces, no functional implementation.
- Automated simulation infrastructure under `sim/` (Makefile or shell scripts, testbench harness in SV or Verilog) capable of compiling the stub hierarchy without requiring full subsystem instantiation.
- At least one deterministic smoke test whose pass/fail is reported automatically (e.g., `$display("PASS")`).
- Documentation of: subsystem boundaries and clock domains, reset behavior used by the skeleton, interface expectations between stubbed blocks, and notes on how the skeleton integrates with `emu`.
- Preservation of a known-good visual/output behavior suitable for incremental integration testing.

### Acceptance Criteria
- [ ] The selected simulation toolchain can compile and execute the Jupiter skeleton (RTL hierarchy + simulation harness).
- [ ] A deterministic smoke test runs and reports pass/fail automatically.
- [ ] The minimal hierarchy integrates without unresolved module/interface errors in simulation (any unresolved symbols are confined to stub boundaries).
- [ ] Subsystem boundaries and interface expectations between future blocks are documented within `sim/` and accompanying docs.
- [ ] Clock and reset behavior used by the skeleton is documented.
- [ ] A known-good output behavior is preserved and verified under simulation.
- [ ] No full CPU, GPU, DMA, audio system, or SDRAM controller has been implemented — stubs/placeholders only.

### Non-Goals
- No CPU instruction execution or core implementation.
- No full graphics implementation (2D or otherwise).
- No audio implementation.
- No DMA implementation.
- No external SDRAM controller.
- No Quartus synthesis or timing closure.

### Prerequisites for Next Milestone
- Simulation harness compiles and runs with smoke test passing.
- Subsystem boundaries, interface expectations, clock behavior, and reset behavior are documented.
- Known-good output behavior preserved and verified in simulation.

---

## Milestone 2 — CPU ISA and Minimal CPU

### Objective
Define enough of Jupiter's custom 32-bit RISC ISA to implement a minimal useful CPU. Implement and simulate the smallest CPU capable of executing a deterministic test program, while deferring performance optimization and advanced CPU features. The CPU may use a single-cycle, multi-cycle, pipelined, or another simple architecture — no particular pipeline organization is mandated at this stage.

### Concrete Deliverables
- `docs/ISA_SPEC.md` (within working tree) — unambiguous ISA subset documentation covering instruction encoding, register file organization, exception/interrupt model (if selected), and memory interface protocol from the CPU perspective.
- RTL implementation of a minimal CPU under `rtl/cpu/`, using any module/file organization chosen during implementation.
- Simulation testbench(es) under `sim/` feeding a deterministic program (hard-coded in ROM or loaded via initial memory) into the CPU and checking results via monitor logic.
- A small reference test program demonstrating all required instruction categories: register-register ALU operations, loads/stores to simple memory stubs, and control-flow behavior (branch/jump).

### Acceptance Criteria
- [ ] The implemented ISA subset is documented unambiguously in `docs/ISA_SPEC.md` with encoding table, operand formats, and execution semantics for each instruction.
- [ ] The CPU implementation matches the documented ISA subset.
- [ ] A deterministic simulation test program executes to completion, and automated tests report pass/fail (e.g., via `$display`).
- [ ] Arithmetic/logic, memory access, and control-flow behavior needed by the selected minimal ISA subset are verified.
- [ ] The CPU can perform the memory transactions necessary for later memory-mapped system integration, without requiring a particular bus protocol or dedicated I/O instruction type at this stage.
- [ ] No caches, advanced optimization, speculative execution, or final performance tuning is required or implemented for this milestone.

### Non-Goals
- No exact register count, encoding layout, branch format, interrupt architecture, multiplier implementation, cache architecture, or clock frequency is mandated — these are design decisions made during ISA specification and implementation.
- No privilege levels are assumed; whether Jupiter has privilege levels is an ISA design decision deferred to the ISA specification.
- No exception architecture is required unless one is selected as necessary for the defined ISA subset.
- No dedicated I/O instruction is mandated; memory-mapped I/O via normal memory transactions remains valid.
- No mature register file with bypassing; a simple implementation suffices.
- No assembler, linker, or compiler tooling yet.
- No Quartus synthesis or timing analysis.

### Prerequisites for Next Milestone
- The CPU can execute a deterministic test program to completion and produce a confirmed pass.
- The ISA spec is written and documents all instructions the CPU supports.

---

## Milestone 3 — Internal Bus, Memory Map, and Basic Memory

### Objective
Define Jupiter's internal transaction mechanism, establish an initial non-overlapping memory map, connect the CPU to basic internal/test memory, and provide minimum memory-mapped functionality sufficient to verify system integration. External SDRAM implementation remains in Milestone 4. The bus protocol — request/acknowledge, valid/ready, arbitration structure, transaction phases, or other details — is a design decision selected and documented during this milestone.

### Concrete Deliverables
- Documented internal transaction/bus semantics covering the selected protocol, transfer phases, handshaking, and data/address widths at the implementation stage's discretion.
- Documented arbitration behavior appropriate to the masters present at this stage (CPU alone or CPU with any minimal additional master implemented).
- An initial documented memory map with non-overlapping regions; addresses are produced as part of this milestone's work rather than inherited from prior milestones.
- Basic internal/test memory sufficient for deterministic CPU integration tests, implemented in the existing `rtl/memory/` directory or another directory chosen during implementation.
- Minimum memory-mapped test functionality sufficient to demonstrate reads, writes, address decoding, and target selection — a simple test register or similarly minimal memory-mapped target may be used as an implementation decision.
- Simulation testbench(es) under `sim/` exercising read/write cycles across the memory map through the selected interconnect mechanism, accessing both internal memory and any test registers.

### Acceptance Criteria
- [ ] The documented memory-map regions do not overlap in address space.
- [ ] CPU reads and writes complete correctly through the selected internal transaction mechanism (simulation).
- [ ] Memory accesses return deterministic expected data.
- [ ] Memory-mapped test accesses select the correct target.
- [ ] Unmapped / invalid accesses have documented deterministic behavior.
- [ ] Bus/interconnect semantics and arbitration rules are fully documented.
- [ ] Automated tests under `sim/` report pass/fail clearly.

### Non-Goals
- No external SDRAM controller yet — external memory is reserved for a later milestone.
- No full DMA engine implementation.
- No GPU rendering hardware.
- No PCM audio mixing hardware.
- No particular burst mode, priority policy, peripheral type, or interconnect filename/directory structure is mandated (except that memory RTL should use the existing `rtl/memory/` directory unless a different organizational decision is made during implementation).

### Prerequisites for Next Milestone
- The CPU can read and write through the internal transaction mechanism to internal/test memory in simulation.
- The documented memory map reserves address space available for an external SDRAM region without conflict in later milestones.

---

## Milestone 4 — External SDRAM Integration

### Objective
Design, implement, simulate, and validate Jupiter's interface to the MiSTer board's external SDRAM. Demonstrate reliable CPU-visible external memory before graphics or audio depend heavily on it. At this milestone DMA is not implemented; a test/stub master may represent a future DMA-capable master but the final DMA engine does not exist here.

### Concrete Deliverables
- Documented analysis of the available MiSTer-facing SDRAM interface relevant to Jupiter (bus topology, pin mapping, signal conventions, constraints). Existing MiSTer SDRAM-related framework sources must be inspected to determine what, if anything, is applicable to Jupiter; no particular framework file is nominated as a prospective controller, bridge, or wrapper at this stage.
- Selected SDRAM-controller/interface architecture for Jupiter, documented before it is relied upon.
- RTL implementation of the selected SDRAM-controller/interface under `rtl/memory/` (not under `rtl/mem/`). No particular controller filename is mandated at this stage.
- Simulation model or behavioral test infrastructure under `sim/` exercising memory reads/writes from CPU and any other masters present in the milestone.
- Documented arbitration/scheduling rules for all masters actually used in this milestone.
- Integration with the internal transaction architecture established in Milestone 3.
- Data-integrity tests verifying correct round-trip behavior of external-memory accesses.
- Updated memory map reserving an external SDRAM address range (actual addresses selected during implementation, not predetermined).

### Acceptance Criteria
- [ ] Deterministic writes to external SDRAM followed by reads return expected data (verified in simulation).
- [ ] Multiple request sources present in the milestone are arbitrated according to documented behavior if more than one exists.
- [ ] Refresh/maintenance behavior required by the selected SDRAM architecture is verified where applicable.
- [ ] Sustained access does not produce data corruption in the tested scenarios.
- [ ] CPU-visible external-memory access works through the Milestone 3 interconnect.
- [ ] Tests automatically report pass/fail.
- [ ] No claim of hardware timing closure or real-hardware success unless actually tested on target hardware.

### Non-Goals
- No performance tuning beyond functional correctness.
- No SDRAM power-down modes or self-refresh optimizations.
- No DMA engine implementation (DMA is deferred to Milestone 6).

### Prerequisites for Next Milestone
- Functional external SDRAM read/write verified end-to-end from CPU through the controller and interconnect.
- Memory map has an established external-SDRAM region that does not conflict with register/ROM regions.
- Arbitration/scheduling policy for the masters present in this milestone is documented.

---

## Milestone 5 — Hardware 2D Graphics

### Objective
Implement the first useful Jupiter hardware-assisted 2D graphics subsystem. Prioritize tile/bandwidth-efficient rendering suitable for FPGA/external-memory constraints. Establish a deterministic CPU-controlled graphics path and verify through automated simulation testing. The following are Jupiter design targets but their exact organization is not predetermined: tile/background rendering, sprites, scrolling, blitting, RGB555/RGB565-style internal formats, blending, affine effects. Their inclusion at this milestone awaits documented selection of the initial feature subset during design.

### Concrete Deliverables
- Documented selection of the initial 2D feature subset (which features from the above targets are included in first implementation).
- 2D GPU RTL under `rtl/gpu/` (file organization TBD during implementation; no specific filename mandated).
- CPU-visible graphics control interface integrated with the system transaction architecture established in earlier milestones.
- Graphics-memory access integrated with the memory architecture selected in Milestone 4 (no particular SDRAM location for framebuffer, tiles, sprites, or graphics assets is mandated at this stage).
- Deterministic simulation tests under `sim/`.
- Known expected rendered image/pixel results suitable for automated comparison.

### Acceptance Criteria
- [ ] The selected initial 2D features are documented.
- [ ] CPU writes can configure and control the implemented graphics functions.
- [ ] Selected rendering operations generate deterministic expected pixel/image results in simulation.
- [ ] Address/memory accesses remain within documented regions.
- [ ] Graphics operation does not corrupt unrelated memory.
- [ ] Tests automatically report pass/fail.
- [ ] Features not selected for the first implementation are not required for milestone completion.

### Non-Goals
- No tile size is mandated at this stage.
- No palette RAM organization is mandated.
- No specific sprite format, sprite size, sprite count, flip behavior, priority model, or motion capability is mandated.
- No particular number of tile/background layers is required.
- No scrolling register organization is mandated.
- No framebuffer/tile/sprite/graphics asset memory locations are predetermined.
- No specific blitter feature set (e.g., color-keying, alpha handling, AND/OR/XOR operations, rectangular-copy semantics) is mandated unless selected during milestone design.
- RGB555/RGB565-style formats remain provisional targets, not mandatory implementation details until selected.
- No affine effects are required in the first 2D implementation merely because they are an architectural target.
- No pixel throughput, sprite counts, layer counts, VRAM sizes, clock rates, or other performance numbers are invented or guaranteed at this stage.
- No real-hardware video performance is required yet.

### Prerequisites for Next Milestone
- The selected CPU-visible graphics control interface and graphics-memory paths are proven in simulation.
- Selected 2D rendering produces deterministic expected-bitmap results when reading from/write to the memory regions established by prior milestones.

---

## Milestone 6 — DMA

### Objective
Implement Jupiter DMA for high-bandwidth data movement. Support graphics, audio, and general memory movement as required by measured system needs. Integrate DMA with the system transaction and memory architectures. Verify arbitration and data integrity. The number of channels, descriptors/registers, supported transfer modes, trigger mechanisms, completion signaling, arbitration, scheduling, and transfer granularity must be selected based on the system's actual requirements at this stage.

### Concrete Deliverables
- Documented DMA architecture selected based on measured/known needs (channels, transfer modes, triggers, completion mechanism, arbitration).
- DMA RTL under `rtl/dma/` (file organization TBD during implementation; no specific filename or channel count mandated).
- Documented CPU-visible control/status interface for the implemented DMA.
- Integration with the system transaction architecture established in earlier milestones.
- Integration with internal/external memory as appropriate.
- Deterministic tests under `sim/` exercising every supported transfer mode.
- Arbitration/contention tests relevant to the implemented masters.

### Acceptance Criteria
- [ ] Every implemented DMA transfer mode copies/moves data exactly as documented.
- [ ] Source data and unrelated memory are not corrupted during transfers.
- [ ] Contention with other implemented masters follows documented arbitration behavior.
- [ ] CPU-visible DMA state/control behaves deterministically.
- [ ] Completion behavior, whatever mechanism was selected, is testable.
- [ ] Tests automatically report pass/fail.

### Non-Goals
- No particular channel count or requirement that channels operate concurrently.
- No preselected cycle-steal versus burst behavior; no preselected source/destination auto-increment behavior.
- No overlapping-memory-copy semantics unless the selected DMA design intentionally supports them.
- No requirement for completion interrupts.
- No specific trigger mechanism mandated.
- No fixed arbitration priority relative to CPU/GPU/audio blocks at this stage.
- No invented throughput or latency requirements.
- No supported features beyond what is selected during design.

### Prerequisites for Next Milestone
- DMA transfers verified from source to destination with correct data across implemented modes.
- Contention behavior with other masters proven in simulation.
- DMA control/status documented and testable deterministically.

---

## Milestone 7 — PCM Audio

### Objective
Implement Jupiter hardware PCM playback and mixing. Support multiple hardware voices and integrate audio with the system transaction and memory architecture. Use FPGA DSP resources where advantageous. Determine final integration with the MiSTer-facing audio outputs from the actual template interface during implementation.

PCM refers to playback/mixing of sample data. Any synthesized waveform generation (e.g., sine waves) is an optional feature that may be selected during this milestone's design phase but is not required at this stage unless intentionally chosen as part of Jupiter's sound architecture decisions.

A roughly 32–64 voice range is a PROVISIONAL architectural target, not a mandatory milestone acceptance criterion until FPGA resource/timing/bandwidth testing establishes a practical value.

### Concrete Deliverables
- Documented audio architecture for PCM playback and mixing, including voice organization and sample format selections (made during design).
- RTL under `rtl/audio/` implementing the selected PCM playback/mixing subsystem — no particular RTL filename is mandated at this stage.
- Documented CPU-visible control/status interface accessible via Jupiter's bus.
- PCM sample storage and buffering approach documented; samples may reside in external memory, internal buffering, or another documented organization depending on design decisions made during implementation. No requirement that samples reside in SDRAM.
- Integration with the MiSTer-facing audio interface based on verified template signals (exact mechanism determined from the actual template).
- Deterministic simulation tests under `sim/` with reference audio/sample outputs suitable for automated checking.

### Acceptance Criteria
- [ ] Each implemented voice behaves according to the documented design.
- [ ] Multiple implemented voices mix deterministically as documented.
- [ ] CPU-visible control registers behave deterministically per documentation.
- [ ] Implemented looping/addressing/volume/pitch behavior, if selected during design, is verified against expected reference results.
- [ ] Output samples match expected reference results in simulation.
- [ ] Unrelated memory/state is not corrupted by audio operations.
- [ ] Tests automatically report pass/fail.

### Non-Goals
- No requirement for sine-wave generation, waveform synthesis, or ADSR envelopes unless intentionally selected during this milestone's design.
- No required sample rate or sample bit depth beyond whatever is documented as part of the selected architecture.
- No preset voice count until FPGA resource/timing/bandwidth testing establishes a practical value for the provisional 32–64 target.
- No particular FIFO organization, buffer-end interrupts, saturation behavior, or control register layout is mandated unless intentionally selected during this milestone's design.
- No specific CPU-visible control register layout is required beyond what is documented during implementation.

### Prerequisites for Next Milestone
- Implemented PCM voices produce deterministic mixed output at expected reference results in simulation.
- Audio integration with the MiSTer-facing audio interface works without port-signature mismatches (based on verified template signals).

---

## Milestone 8 — Controllers and Core Peripherals

### Objective
Implement Jupiter's CPU-visible controller/peripheral subsystem, integrate it with the input information available from the MiSTer framework, document the selected CPU-visible interface, and verify it deterministically in simulation.

### Concrete Deliverables
- Documented Jupiter controller/peripheral architecture including input state semantics and update behavior.
- RTL under `rtl/peripherals/` implementing the selected controller/peripheral subsystem — no particular RTL filename is mandated at this stage.
- Documented CPU-visible control/status/register interface accessible via Jupiter's bus, with register layout documented during implementation (exact addresses are not fixed in the roadmap).
- Integration with verified MiSTer input facilities actually selected for Jupiter (not all framework-provided input features need to be supported; only those intentionally chosen by design).
- Deterministic simulation tests under `sim/` exercising CPU reads of controller state and verifying correct propagation of documented input events.

### Acceptance Criteria
- [ ] Selected controller inputs are represented correctly to Jupiter software, per documentation.
- [ ] CPU reads return deterministic expected state from the selected interfaces.
- [ ] State changes propagate according to documented timing/behavior, as verified in simulation.
- [ ] Any implemented interrupt/status mechanism behaves as documented (if one is intentionally selected during design).
- [ ] Unsupported/unselected input features are not required by this milestone.
- [ ] Tests automatically report pass/fail.

### Non-Goals
- No analog input requirement merely because the MiSTer framework may expose it; analog support is only included if intentionally selected during design.
- No exact button count is mandated at this stage beyond what the selected architecture supports.
- No interrupt-on-state-change behavior is required; interrupt behavior is a design decision made during implementation.
- No keyboard, mouse, light-gun, steering-wheel, rotary-encoder, rumble, or HID requirements are invented at this milestone unless intentionally selected during design.
- No prescriptive analog-axis bit layouts or signal names are asserted beyond what the selected template provides and is intentionally adopted.

### Prerequisites for Next Milestone
- Controller/peripheral subsystem produces deterministic simulation results matching documented interface behavior.
- CPU-visible register reads return correct, verified state in simulation.

---

## Milestone 9 — BIOS and Host Development Tools

### Objective
Implement custom Jupiter boot firmware and the minimum host-side development tools needed to create and run Jupiter software, working under `software/bios/`, `software/devkit/`, and `software/tools/`.

Jupiter is a new fantasy console. No historical firmware is being reproduced. The exact boot architecture, firmware storage mechanisms, tool formats, and debugging approach are selected and documented during implementation.

### Concrete Deliverables
- Documented Jupiter boot/firmware architecture describing how the system initializes and begins execution.
- Custom boot firmware under `software/bios/` — no particular BIOS binary filename or image format is mandated before the boot architecture is finalized.
- Documented firmware storage/loading/entry process (how contents are stored, loaded, and where execution begins; exact mechanism is a design decision).
- Minimum assembler or equivalent program-generation tooling under `software/devkit/`, based on `docs/ISA_SPEC.md` from Milestone 2 as the source for ISA definitions. No requirement that the assembler be implemented in a particular host language.
- Any necessary linker/image-generation support determined by the selected software format (no prespecified executable or object format).
- Host-side support utilities under `software/tools/` where useful for building and debugging Jupiter programs.
- Documentation showing how to build and execute at least one Jupiter program from source.
- Automated tests for host-side tools where practical.

### Acceptance Criteria
- [ ] Simulated Jupiter can begin execution through the selected boot process.
- [ ] A host-built Jupiter test program can be produced using the devkit from Milestone 9.
- [ ] That program can be loaded using the selected mechanism and executed successfully in simulation.
- [ ] Generated machine code agrees with `docs/ISA_SPEC.md`.
- [ ] Tooling errors produce deterministic failure rather than silently generating invalid output.
- [ ] The complete build-to-execution path is documented and reproducible.

### Non-Goals
- No C compiler, full relocatable linker, runtime library, or mature development kit is required at this milestone unless later explicitly selected during design.
- No particular BIOS functionality (e.g., memory self-test, controller initialization, GPU initialization, audio initialization, vector-table layout) is required unless intentionally selected as part of the minimum boot firmware design.
- No requirement for firmware update over HPS or any HPS-based firmware update mechanism at this milestone.
- No prescriptive debugging transport or graphical debugger is required beyond what is intentionally designed.

### Prerequisites for Next Milestone
- The selected Jupiter boot process works deterministically in simulation.
- The selected firmware storage/loading/entry mechanism is documented.
- At least one program produced by the host development tools can be loaded through the selected mechanism and executed successfully.
- The build-to-execution workflow is reproducible.

---

## Milestone 10 — Fixed-Function 3D

### Objective
Implement Jupiter's later fixed-function 3D subsystem after CPU, memory, DMA, 2D graphics, and basic software infrastructure are stable. The roadmap does not invent exact implementation organization before Milestone 10 design work establishes it. This milestone selects and documents the 3D architecture, implements RTL, and verifies the selected 3D architecture deterministically in simulation.

Architectural targets for the 3D subsystem (to be confirmed during design) include: triangle rasterization, texture mapping, depth buffering, perspective-correct interpolation, blending, nearest and higher-quality texture sampling options, fixed-point mathematics, and bandwidth-efficient rendering. FPGA DSP resources may be used where advantageous for selected fixed-point operations.

### Concrete Deliverables
- Documented selected fixed-function 3D architecture, including triangle rasterization, texture mapping, depth buffering, perspective-correct interpolation, blending, texture-sampling options, and fixed-point approach.
- Documented command and control interface visible to Jupiter software.
- 3D RTL under `rtl/gpu/`, using module/file organization determined during design.
- Integration with the existing 2D graphics architecture — GPU register mapping and bus connections documented and tested.
- Integration with the selected system-memory and DMA architectures for texture, vertex, framebuffer, and Z-buffer data paths.
- Documented use of FPGA DSP resources where appropriate for fixed-point operations.
- Deterministic simulation tests under `sim/` exercising selected triangle rasterization, texture mapping, depth buffering, perspective-correct interpolation, blending, and graphics-memory access behavior.
- Reference rendered results suitable for automatic comparison in simulation.

### Acceptance Criteria
- [ ] Selected triangle rasterization behavior produces deterministic expected coverage.
- [ ] Selected texture-mapping behavior produces expected reference results.
- [ ] Selected depth-buffering behavior correctly resolves tested overlapping geometry.
- [ ] Perspective-correct interpolation behaves according to the documented design.
- [ ] Implemented blending behaves according to the documented design.
- [ ] Graphics-memory accesses remain within documented regions and do not corrupt unrelated state.
- [ ] 2D functionality from Milestone 5 continues to pass regression tests.
- [ ] Tests automatically report pass/fail.

### Non-Goals
- No unselected 3D features are required merely because they are long-term architectural targets (e.g., mipmap generation, anisotropic filtering).

### Prerequisites for Next Milestone
- Selected 3D architecture is documented and simulation tests verify rasterization, texture mapping, depth buffering, perspective-correct interpolation, blending, and memory behavior.
- Integration with existing 2D graphics and DMA/memories is verified in co-simulation without regression.

---

## Milestone 11 — Optional HPS Services, Integration, Optimization, and Release Validation

### Objective
Integrate the complete Jupiter system. Optionally add useful HPS-assisted storage/network/media functionality where actually adopted. Perform regression testing. Perform Quartus synthesis/resource/timing analysis when Quartus and the required device support are available. Validate on SuperStation One / MiSTer-compatible hardware. Prepare a coherent release.

The HPS must remain an optional I/O/network/media assistant and must not become Jupiter's normal game CPU.

### Concrete Deliverables
- Full-system integration: all previously implemented subsystems connected and tested together with no port-signature mismatches, address conflicts, or arbitration deadlocks.
- Optional HPS service integration under `rtl/peripherals/` where actually adopted (if any HPS services are selected during design). No particular HPS-services RTL filename is prescribed; adopted HPS services and their protocols (filesystem access, networking, media, save data, file loading, …) must be documented based on actual MiSTer interfaces.
- Regression test suite run across all milestones' simulation harnesses with all applicable previously passing tests remaining passing.
- Quartus synthesis/resource/timing analysis when available: if Quartus is available, synthesis and timing reports are performed as release-validation goals; if Quartus is unavailable on the development machine, document that limitation — no results are fabricated. Actual release hardware validation ultimately requires a successfully built FPGA image somewhere in the workflow.
- Hardware-validation procedure and results when performed on SuperStation One / MiSTer-compatible hardware.
- Documentation: ARCHITECTURE.md updated so provisional architecture decisions that became final are clearly recorded. Release-build instructions documented. Known limitations documented. Architectural revisions discovered during integration must be documented and regression-tested.

### Acceptance Criteria
- [ ] All required automated regressions pass.
- [ ] No unresolved address-map conflicts, arbitration deadlocks, or interface mismatches remain.
- [ ] Architectural changes discovered during integration are documented and tested.
- [ ] When synthesis is performed, reported results come from actual Quartus output.
- [ ] When hardware validation is performed, its results are documented.
- [ ] Optional HPS services do not perform normal Jupiter game logic.
- [ ] Release documentation accurately distinguishes verified behavior from untested or unavailable validation.

### Non-Goals
- HPS services must not supplant the game CPU for any gameplay-critical function — Jupiter's core architecture must operate as a standalone system without relying on the ARM host processor for running game logic.

### Prerequisites
- All previous milestones (0–10) have met their documented acceptance criteria.
