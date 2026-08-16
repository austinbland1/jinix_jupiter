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

    check(
        path.is_file(),
        f"{rel} exists",
    )

    if not path.is_file():
        return ""

    return path.read_text()


readme = read("Readme.md")
milestones = read("docs/MILESTONES.md")
release_validation = read("docs/RELEASE_VALIDATION.md")
release_build = read("docs/RELEASE_BUILD.md")
known_limitations = read("docs/KNOWN_LIMITATIONS.md")
hardware_validation = read("docs/HARDWARE_VALIDATION.md")
architecture = read("docs/ARCHITECTURE.md")

template = read("Template.sv")
system = read("rtl/jupiter_system.sv")
system_tb = read("sim/jupiter_system_tb.sv")
video_tb = read("sim/jupiter_system_video_tb.sv")

m11a_checker = read("sim/check_m11a_integration_release.py")
m11c_checker = read("sim/check_m11c_release_acceptance.py")
makefile = read("sim/Makefile")

# ============================================================
# Exact M11 acceptance completion
# ============================================================

match = re.search(
    r"^## Milestone 11\b.*?(?=^## Milestone 12\b|\Z)",
    milestones,
    re.MULTILINE | re.DOTALL,
)

check(
    match is not None,
    "Milestone 11 section exists",
)

if match is not None:
    section = match.group(0)

    open_count = len(
        re.findall(
            r"^- \[ \] ",
            section,
            re.MULTILINE,
        )
    )

    done_count = len(
        re.findall(
            r"^- \[x\] ",
            section,
            re.MULTILINE,
        )
    )

    check(
        open_count == 0,
        "Milestone 11 has zero open acceptance criteria",
    )

    check(
        done_count == 7,
        "Milestone 11 has exactly seven completed acceptance criteria",
    )

criteria = [
    "All required automated regressions pass.",
    "No unresolved address-map conflicts, arbitration deadlocks, or interface mismatches remain.",
    "Architectural changes discovered during integration are documented and tested.",
    "When synthesis is performed, reported results come from actual Quartus output.",
    "When hardware validation is performed, its results are documented.",
    "Optional HPS services do not perform normal Jupiter game logic.",
    "Release documentation accurately distinguishes verified behavior from untested or unavailable validation.",
]

for criterion in criteria:
    check(
        f"- [x] {criterion}" in milestones,
        f"M11 acceptance complete: {criterion}",
    )

# ============================================================
# Closeout documentation
# ============================================================

check(
    '> **Release status:** `v0.1-alpha` — First Public Developer Preview'
    in readme,
    'README records current public developer-preview release status',
)

check(
    'Synthesis, timing closure, resource usage, and physical-hardware operation are not claimed unless they are actually measured or tested.'
    in readme,
    'README keeps synthesis and physical-hardware claims evidence-gated',
)

for phrase in [
    "## Milestone 11 Acceptance Closeout",
    "Milestone 11 acceptance adjudication: PASS.",
    "All seven documented Milestone 11 acceptance criteria are satisfied",
    "The conditional synthesis criterion was",
    "therefore not triggered",
    "The conditional hardware-results criterion was therefore not",
    "No new optional HPS service was selected",
    "Release documentation explicitly distinguishes simulation-verified behavior",
]:
    check(
        phrase in release_validation,
        f"release validation closeout records: {phrase}",
    )

# ============================================================
# Conditional criteria remain evidence-bounded
# ============================================================

check(
    "Quartus availability: UNAVAILABLE"
    in release_validation,
    "Quartus remains explicitly unavailable",
)

check(
    "current development machine does not have Intel Quartus installed"
    in release_build,
    "release-build instructions preserve Quartus-unavailable evidence",
)

check(
    "no verified Quartus synthesis"
    in known_limitations,
    "known limitations do not invent synthesis success",
)

check(
    'Hardware validation status: PARTIAL — selected 2D, audio, controller, and bring-up paths have physical evidence; fixed-function 3D physical output remains unresolved.'
    in hardware_validation,
    'hardware validation records partial physical-validation status',
)

check(
    "Do not change this document to claim hardware PASS"
    in hardware_validation,
    "hardware policy forbids unsupported PASS claims",
)

# ============================================================
# Integrated production evidence remains present
# ============================================================

check(
    "### Production Video Path"
    in architecture,
    "architecture records production framebuffer video path",
)

check(
    "assign video_r = scanout_video_r;"
    in system,
    "system propagates production scanout RGB",
)

check(
    "assign VGA_R = video_r;"
    in template,
    "Template propagates Jupiter red channel",
)

check(
    "known RGB565 red propagates through production system boundary"
    in video_tb,
    "production framebuffer pixel propagation regression exists",
)

check(
    "wrapper timing and RGB outputs follow integrated scanout for 320000 cycles"
    in system_tb,
    "system integration timing/RGB regression exists",
)

# ============================================================
# HPS boundary
# ============================================================

check(
    "Normal Jupiter game logic remains FPGA-side"
    in release_validation,
    "normal game logic remains FPGA-side",
)

check(
    "must not become Jupiter's normal game CPU"
    in architecture,
    "architecture preserves optional-HPS boundary",
)

# ============================================================
# Prior release gates remain part of current regression chain
# ============================================================

check(
    "RESULT: PASS"
    in m11a_checker,
    "historical M11A checker retains PASS result machinery",
)

check(
    "RESULT: PASS"
    in m11c_checker,
    "M11C checker retains PASS result machinery",
)

check(
    "m11d-test: m11c-test"
    in makefile,
    "Makefile chains M11D after M11C",
)

check(
    "python3 -B check_m11d_closeout.py"
    in makefile,
    "Makefile executes M11D closeout checker",
)

print("")
print("==============================")

if failures == 0:
    print(f"RESULT: PASS  ({checks} checks)")
    print("==============================")
    sys.exit(0)

print(
    f"RESULT: FAIL  ({failures} failures / {checks} checks)"
)
print("==============================")
sys.exit(1)
