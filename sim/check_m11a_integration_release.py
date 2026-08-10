#!/usr/bin/env python3

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = 0
failures = 0


def check(condition, message):
    global checks, failures

    checks += 1

    if condition:
        print(f"PASS: {message}")
    else:
        failures += 1
        print(f"FAIL: {message}")


def read(rel):
    path = ROOT / rel

    check(path.is_file(), f"{rel} exists")

    if not path.is_file():
        return ""

    return path.read_text()


template_qsf = read("Template.qsf")
template_q13_qsf = read("Template_Q13.qsf")
sys_qip = read("sys/sys.qip")
sys_tcl = read("sys/sys.tcl")
files_qip = read("files.qip")

template = read("Template.sv")
system = read("rtl/jupiter_system.sv")
subsystem = read("rtl/jupiter_cpu_subsystem.sv")
interconnect = read("rtl/memory/jupiter_interconnect.sv")

bus_doc = read("docs/BUS_MEMORY_MAP.md")
architecture = read("docs/ARCHITECTURE.md")
development_rules = read("docs/DEVELOPMENT_RULES.md")

release_build = read("docs/RELEASE_BUILD.md")
release_validation = read("docs/RELEASE_VALIDATION.md")
known_limitations = read("docs/KNOWN_LIMITATIONS.md")
hardware_validation = read("docs/HARDWARE_VALIDATION.md")

# ============================================================
# Quartus / MiSTer source graph
# ============================================================

check(
    template_qsf.count(
        "set_global_assignment -name TOP_LEVEL_ENTITY sys_top"
    ) == 1,
    "Template.qsf selects sys_top exactly once",
)

check(
    template_q13_qsf.count(
        "set_global_assignment -name TOP_LEVEL_ENTITY sys_top"
    ) == 1,
    "Template_Q13.qsf selects sys_top exactly once",
)

check(
    "set_global_assignment -name QIP_FILE sys/sys.qip"
    in sys_tcl,
    "framework Tcl registers sys/sys.qip",
)

for token, label in [
    ("sys_top.v", "sys.qip registers sys_top"),
    ("hps_io.sv", "sys.qip registers hps_io"),
    ("emu_ports.vh", "sys.qip registers emu_ports"),
]:
    check(token in sys_qip, label)

production_sources = [
    "rtl/jupiter_core.sv",
    "rtl/jupiter_system.sv",
    "rtl/jupiter_cpu_subsystem.sv",
    "rtl/cpu/jupiter_cpu.sv",
    "rtl/memory/jupiter_interconnect.sv",
    "rtl/memory/jupiter_internal_ram.sv",
    "rtl/memory/jupiter_sdram_arbiter.sv",
    "rtl/memory/jupiter_sdram_frontend.sv",
    "rtl/memory/jupiter_sdram_controller.sv",
    "rtl/peripherals/jupiter_mmio_scratch.sv",
    "rtl/peripherals/jupiter_controllers.sv",
    "rtl/gpu/jupiter_gpu_2d3d_arbiter.sv",
    "rtl/gpu/jupiter_gpu_3d_raster.sv",
    "rtl/gpu/jupiter_gpu_3d.sv",
    "rtl/gpu/jupiter_gpu_2d.sv",
    "rtl/dma/jupiter_dma.sv",
    "rtl/audio/jupiter_audio.sv",
]

for source in production_sources:
    expected = (
        "set_global_assignment -name SYSTEMVERILOG_FILE "
        + source
    )

    check(
        files_qip.splitlines().count(expected) == 1,
        f"files.qip registers {source} exactly once",
    )

check(
    "_stub.sv" not in files_qip,
    "simulation stub RTL is absent from files.qip",
)

# ============================================================
# Production hierarchy
# ============================================================

check(
    len(
        re.findall(
            r"^\s*module\s+emu(?:\s|#|\(|;|$)",
            template,
            re.MULTILINE,
        )
    ) == 1,
    "Template exposes one emu module",
)

check(
    len(
        re.findall(
            r"^\s*hps_io\s*#\s*\(",
            template,
            re.MULTILINE,
        )
    ) == 1,
    "Template instantiates hps_io exactly once",
)

check(
    len(
        re.findall(
            r"^\s*jupiter_system\s+jupiter_system_inst\b",
            template,
            re.MULTILINE,
        )
    ) == 1,
    "Template instantiates jupiter_system exactly once",
)

check(
    len(
        re.findall(
            r"^\s*jupiter_cpu_subsystem\s+cpu_subsystem\b",
            system,
            re.MULTILINE,
        )
    ) == 1,
    "jupiter_system instantiates CPU subsystem exactly once",
)

for module in [
    "jupiter_cpu",
    "jupiter_sdram_arbiter",
    "jupiter_sdram_frontend",
    "jupiter_sdram_controller",
    "jupiter_gpu_2d",
    "jupiter_dma",
    "jupiter_audio",
    "jupiter_controllers",
]:
    pattern = (
        rf"^\s*{module}\s+"
        rf"[A-Za-z_][A-Za-z0-9_]*\b"
    )

    check(
        len(
            re.findall(
                pattern,
                subsystem,
                re.MULTILINE,
            )
        ) == 1,
        f"CPU subsystem instantiates {module} exactly once",
    )

# ============================================================
# Implemented address map
# ============================================================

expected_ranges = {
    "RAM": (0x00000000, 0x00000FFF),
    "MMIO": (0x00001000, 0x00001003),
    "GPU": (0x00001100, 0x000011FF),
    "DMA": (0x00001200, 0x000012FF),
    "AUDIO": (0x00001300, 0x000013FF),
    "CONTROLLER": (0x00001400, 0x000014FF),
    "SDRAM": (0x10000000, 0x17FFFFFF),
}

parsed = {}

for prefix in expected_ranges:
    for suffix in ("START", "END"):
        name = f"{prefix}_{suffix}"

        match = re.search(
            rf"\blocalparam\s+\[31:0\]\s+"
            rf"{name}\s*=\s*32'h([0-9A-Fa-f]+)",
            interconnect,
        )

        check(
            match is not None,
            f"interconnect defines {name}",
        )

        if match is not None:
            parsed[name] = int(
                match.group(1),
                16,
            )

for prefix, expected in expected_ranges.items():
    actual = (
        parsed.get(f"{prefix}_START"),
        parsed.get(f"{prefix}_END"),
    )

    check(
        actual == expected,
        f"{prefix} decode matches selected range",
    )

sorted_ranges = sorted(
    (start, end, name)
    for name, (start, end)
    in expected_ranges.items()
)

for (
    _,
    previous_end,
    previous_name,
), (
    current_start,
    _,
    current_name,
) in zip(
    sorted_ranges,
    sorted_ranges[1:],
):
    check(
        previous_end < current_start,
        f"{previous_name} and {current_name} do not overlap",
    )

for start, end, name in sorted_ranges:
    start_text = f"0x{start:08X}"
    end_text = f"0x{end:08X}"

    check(
        start_text in bus_doc and
        end_text in bus_doc,
        f"BUS_MEMORY_MAP documents {name}",
    )

# ============================================================
# Architecture finalization
# ============================================================

stale_phrases = [
    "No functional CPU RTL exists in the current repository",
    "Strong hardware-assisted 2D graphics are a design target",
    (
        "What is the exact instruction set architecture for "
        "the proposed custom 32-bit CPU?"
    ),
    (
        "Where should later controller, firmware, and other "
        "still-unselected regions"
    ),
    (
        "What exact row/bank/column transformation should "
        "the controller use for"
    ),
    (
        "How are tilemaps, sprite engines, palettes, scroll "
        "registers, and priority logic organized"
    ),
    (
        "When/if implemented, which host-facing services "
        "the MiSTer HPS processor provides"
    ),
]

for phrase in stale_phrases:
    check(
        phrase not in architecture,
        f"stale architecture phrase removed: {phrase}",
    )

for phrase in [
    "MILESTONE 2 SELECTED AND IMPLEMENTED",
    "MILESTONE 5 SELECTED AND IMPLEMENTED",
    "M11A selects no new optional HPS-assisted service",
    "current 20 MHz controller clock",
    "docs/ISA_SPEC.md",
    "docs/GPU_2D_ARCHITECTURE.md",
    "docs/SDRAM_ARCHITECTURE.md",
]:
    check(
        phrase in architecture,
        f"architecture records: {phrase}",
    )

# ============================================================
# HPS boundary
# ============================================================

check(
    (
        "Normal Jupiter game logic must execute in the "
        "FPGA-side Jupiter architecture"
    )
    in development_rules,
    "development rules keep game logic FPGA-side",
)

check(
    "Normal Jupiter game logic remains FPGA-side"
    in release_validation,
    "release validation preserves HPS boundary",
)

check(
    "adopts no new HPS-assisted storage"
    in known_limitations,
    "known limitations record no new HPS service",
)

# ============================================================
# Release evidence discipline
# ============================================================

for phrase in [
    "quartus_sh --flow compile Template",
    "Template.qpf",
    "sys_top",
    "files.qip",
    "must never be added to the synthesis source list",
]:
    check(
        phrase in " ".join(release_build.split()),
        f"release build documents: {phrase}",
    )

for phrase in [
    "Quartus availability: UNAVAILABLE",
    "M11A regression result:",
    "Hardware validation status: NOT PERFORMED",
    "build_id.v",
]:
    check(
        phrase in release_validation,
        f"release validation records: {phrase}",
    )

for phrase in [
    "no verified Quartus synthesis",
    "framebuffer scanout is integrated and verified in simulation",
    "generated `build_id.v`",
]:
    check(
        phrase in known_limitations,
        f"known limitations record: {phrase}",
    )

check(
    (
        "Hardware validation status: NOT PERFORMED"
        in hardware_validation
    ),
    "hardware procedure records unperformed status",
)

check(
    (
        "Do not change this document to claim hardware PASS"
        in hardware_validation
    ),
    "hardware procedure prevents unsupported PASS claims",
)

video_demo_present = bool(
    re.search(
        r"^\s*mycore\s+video_demo\b",
        system,
        re.MULTILINE,
    )
)

if video_demo_present:
    check(
        (
            "not yet a scanout of Jupiter's rendered framebuffer"
            in known_limitations
        ),
        "current demo-video path is explicitly documented",
    )

print("")
print("==============================")

if failures == 0:
    print(f"RESULT: PASS  ({checks} checks)")
else:
    print(
        f"RESULT: FAIL  ({failures} failures / {checks} checks)"
    )

print("==============================")

sys.exit(1 if failures else 0)
