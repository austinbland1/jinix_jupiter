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


template = read("Template.sv")
system = read("rtl/jupiter_system.sv")
subsystem = read("rtl/jupiter_cpu_subsystem.sv")
files_qip = read("files.qip")

readme = read("Readme.md")
architecture = read("docs/ARCHITECTURE.md")
release_build = read("docs/RELEASE_BUILD.md")
release_validation = read("docs/RELEASE_VALIDATION.md")
known_limitations = read("docs/KNOWN_LIMITATIONS.md")
hardware_validation = read("docs/HARDWARE_VALIDATION.md")
milestones = read("docs/MILESTONES.md")
video_arch = read("docs/VIDEO_SCANOUT_ARCHITECTURE.md")

system_tb = read("sim/jupiter_system_tb.sv")
video_tb = read("sim/jupiter_system_video_tb.sv")
makefile = read("sim/Makefile")

# ============================================================
# Production visible-video boundary
# ============================================================

check(
    not re.search(
        r"^\s*mycore\s+video_demo\b",
        system,
        re.MULTILINE,
    ),
    "production jupiter_system no longer instantiates mycore video_demo",
)

for phrase in [
    "assign ce_pix = scanout_ce_pix;",
    "assign HBlank = scanout_hblank;",
    "assign HSync  = scanout_hsync;",
    "assign VBlank = scanout_vblank;",
    "assign VSync  = scanout_vsync;",
    "assign video_r = scanout_video_r;",
    "assign video_g = scanout_video_g;",
    "assign video_b = scanout_video_b;",
]:
    check(
        phrase in system,
        f"production system propagates scanout: {phrase}",
    )

for phrase in [
    "wire [7:0] video_r;",
    "wire [7:0] video_g;",
    "wire [7:0] video_b;",
    ".video_r(video_r),",
    ".video_g(video_g),",
    ".video_b(video_b),",
    "assign VGA_R = video_r;",
    "assign VGA_G = video_g;",
    "assign VGA_B = video_b;",
]:
    check(
        phrase in template,
        f"Template direct RGB boundary records: {phrase}",
    )

check(
    ".video(video)," not in template,
    "legacy single-channel Template video connection is absent",
)

check(
    "? video :" not in template,
    "legacy Template colorized-intensity mapping is absent",
)

# ============================================================
# Production integration / synthesis source graph
# ============================================================

for phrase in [
    "jupiter_video_scanout video_scanout",
    "jupiter_sdram_scanout_arbiter scanout_sdram_arbiter",
]:
    check(
        phrase in subsystem,
        f"subsystem integrates production scanout component: {phrase}",
    )

for phrase in [
    "rtl/video/jupiter_video_scanout.sv",
    "rtl/memory/jupiter_sdram_scanout_arbiter.sv",
    "rtl/jupiter_cpu_subsystem.sv",
    "rtl/jupiter_system.sv",
]:
    check(
        phrase in files_qip,
        f"files.qip registers production source: {phrase}",
    )

check(
    "sim/" not in files_qip,
    "files.qip contains no simulation-only source path",
)

# ============================================================
# Deterministic simulation evidence
# ============================================================

for phrase in [
    "wrapper timing and RGB outputs follow integrated scanout for 320000 cycles",
    "disabled framebuffer scanout remains deterministic black",
]:
    check(
        phrase in system_tb,
        f"system regression records: {phrase}",
    )

for phrase in [
    "known RGB565 red propagates through production system boundary",
    "known RGB565 green propagates through production system boundary",
    "known RGB565 blue propagates through production system boundary",
    "known RGB565 white propagates through production system boundary",
    "all production system timing outputs are direct scanout timing",
]:
    check(
        phrase in video_tb,
        f"production video regression records: {phrase}",
    )

# ============================================================
# Documentation synchronized with M11B
# ============================================================

for phrase in [
    "M11B integrates production framebuffer scanout",
    "RGB888 channels and timing directly to the MiSTer-facing video outputs",
]:
    check(
        phrase in readme,
        f"Readme records current integration: {phrase}",
    )

for stale in [
    "existing template/demo video path is still preserved",
    "presenting that framebuffer as the final live display is a later integration step",
]:
    check(
        stale not in readme,
        f"Readme stale phrase removed: {stale}",
    )

for phrase in [
    "### Production Video Path",
    "Milestone 11B integrates Jupiter framebuffer scanout",
    "`jupiter_system` propagates `ce_pix`, blanking, sync, and `video_r/g/b`",
    "`Template.sv` connects the Jupiter RGB888 channels directly",
    "The integrated video path is simulation-verified.",
]:
    check(
        phrase in architecture,
        f"architecture records M11B video truth: {phrase}",
    )

for stale in [
    "### Existing Video Path (as instantiated in the template)",
    "**Core output:** `mycore.v` drives an 8-bit parallel video bus",
    "Jupiter SDRAM controller has not yet reached top-level",
    "Both `AUDIO_L` and `AUDIO_R` are tied to `'0`",
]:
    check(
        stale not in architecture,
        f"architecture stale phrase removed: {stale}",
    )

for phrase in [
    "M11B framebuffer-scanout integration result: PASS.",
    "This is simulation evidence only.",
    "Quartus availability: UNAVAILABLE",
    "Hardware validation status: NOT PERFORMED",
    "Normal Jupiter game logic remains FPGA-side",
]:
    check(
        phrase in release_validation,
        f"release validation records: {phrase}",
    )

check(
    "Production framebuffer scanout is integrated and verified in simulation."
    in known_limitations,
    "known limitations record integrated simulated framebuffer scanout",
)

check(
    "The remaining limitation is validation rather than missing RTL integration:"
    in known_limitations,
    "known limitations distinguish validation from integration",
)

for stale in [
    "still preserves the inherited `mycore",
    "not yet a scanout of Jupiter's rendered framebuffer",
]:
    check(
        stale not in known_limitations,
        f"known limitations stale phrase removed: {stale}",
    )

for stale in [
    "When Jupiter framebuffer scanout is integrated",
    "After physical framebuffer scanout exists",
]:
    check(
        stale not in hardware_validation,
        f"hardware procedure stale conditional removed: {stale}",
    )

check(
    "Hardware validation status: NOT PERFORMED."
    in hardware_validation,
    "hardware validation remains explicitly unperformed",
)

check(
    "Do not change this document to claim hardware PASS"
    in hardware_validation,
    "hardware-validation policy prevents unsupported PASS claims",
)

# ============================================================
# Release claims remain evidence-bounded
# ============================================================

for phrase in [
    "current development machine does not have Intel Quartus installed",
    "synthesis success only when an actual Quartus run",
    "Physical SuperStation One / MiSTer-compatible operation may be claimed only",
]:
    check(
        phrase in release_build,
        f"release-build evidence policy records: {phrase}",
    )

check(
    "no verified Quartus synthesis" in known_limitations,
    "known limitations retain unavailable Quartus evidence",
)

check(
    "has not yet been exercised on physical" in known_limitations,
    "known limitations retain absent physical-video validation",
)

# ============================================================
# HPS boundary
# ============================================================

check(
    "Milestone 11 currently selects no new optional HPS"
    in release_validation,
    "release validation records no newly selected optional HPS service",
)

check(
    "Normal Jupiter game logic remains FPGA-side"
    in release_validation,
    "release validation keeps normal game logic off HPS",
)

check(
    "must not become Jupiter's normal game CPU"
    in architecture,
    "architecture keeps HPS optional and non-game-CPU",
)

# ============================================================
# Selected scanout architecture still documented
# ============================================================

for phrase in [
    "0x1180",
    "0x11BF",
    "RGB565",
    "UNDERFLOW",
]:
    check(
        phrase in video_arch,
        f"scanout architecture records: {phrase}",
    )

check(
    re.search(
        r"(?:"
        r"two.{0,160}320.{0,160}line[- ]buffers?"
        r"|"
        r"two.{0,160}line[- ]buffers?.{0,160}320"
        r")",
        video_arch,
        re.IGNORECASE | re.DOTALL,
    )
    is not None,
    "scanout architecture records two 320-pixel line buffers",
)

# ============================================================
# M11C is documentation/checker synchronization only.
# Acceptance boxes remain untouched for later adjudication.
# ============================================================

m11 = re.search(
    r"^## Milestone 11\b.*?(?=^## Milestone 12\b|\Z)",
    milestones,
    re.MULTILINE | re.DOTALL,
)

check(
    m11 is not None,
    "Milestone 11 section exists",
)

if m11 is not None:
    section = m11.group(0)

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
        open_count == 7,
        "M11C leaves all seven acceptance criteria open",
    )

    check(
        done_count == 0,
        "M11C does not prematurely mark acceptance complete",
    )

# ============================================================
# Regression registration
# ============================================================

check(
    "m11c-test: m11b3b-test" in makefile,
    "Makefile registers M11C after M11B-3b",
)

check(
    "python3 -B check_m11c_release_acceptance.py" in makefile,
    "Makefile executes M11C release checker",
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
