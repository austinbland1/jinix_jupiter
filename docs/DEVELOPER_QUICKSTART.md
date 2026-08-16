# Jinix Jupiter — Developer Quick Start

This document describes the low-level developer entry points available in the `v0.1-alpha` developer preview.

## 1. Read the architecture first

Recommended starting documents:

- `docs/ARCHITECTURE.md`
- `docs/BUS_MEMORY_MAP.md`
- `docs/CONTROLLER_ARCHITECTURE.md`
- `docs/AUDIO_ARCHITECTURE.md`
- the ISA documentation under `docs/`

## 2. Jupiter assembler

The minimum assembler is:

```text
software/devkit/jupiter_asm.py
```

Inspect its supported command-line interface directly:

```bash
python3 software/devkit/jupiter_asm.py --help
```

The assembler implements the currently documented Jupiter ISA. Do not assume GNU assembler syntax or ELF tooling unless the repository explicitly documents it.

## 3. BIOS and example software

Useful source locations include:

```text
software/bios/
software/hardware_boot/
```

These contain the minimal BIOS/integration software and hardware-test programs used during bring-up.

## 4. System-image builder

The host-side system-image tool is:

```text
software/tools/build_system_image.py
```

Inspect its supported command-line interface with:

```bash
python3 software/tools/build_system_image.py --help
```

## 5. Simulation

The `sim/` directory contains deterministic regression testbenches for the implemented Jupiter subsystems. Inspect `sim/Makefile` for the currently supported targets.

Before treating a change as release-quality, run the relevant focused tests and the complete regression set used by the repository.

## 6. Physical-development boundary

For `v0.1-alpha`, target the verified **2D** physical path.

Fixed-function 3D remains experimental for hardware use. You may develop against its documented/simulated interface, but do not assume the current 3D path will produce a stable physical HDMI output.

## 7. Controller model

Jupiter initially exposes raw digital controller state rather than a polished semantic input API. Homebrew should avoid assuming a universal face-button mapping until mappings are documented for the intended controller/core configuration.

## 8. Contributing

Useful early contributions include:

- 2D homebrew programs and demos;
- developer examples;
- assembler/tooling improvements;
- controller mapping reports;
- additional SuperStation One / MiSTer hardware validation;
- reproducible 3D bring-up diagnostics.

Keep hardware claims tied to exact commits/RBF hashes and recorded test conditions.
