#!/usr/bin/env python3
"""Static M12C integration audit for the candidate tree."""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text()


def sha(rel: str) -> str:
    return hashlib.sha256(
        (ROOT / rel).read_bytes()
    ).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(
            "M12C topology audit failed: " + message
        )


PROTECTED_SHA = {
    "sys/hps_io.sv":
        "f4a085fc23bdcefb57c600866a39a448c749cd3c93910f7005316e8df9019bec",
    "rtl/cpu/jupiter_cpu.sv":
        "cdf6af92cf25539d8bcf43b4a023853be1c18eacebad0c363c0b6df58d2261bd",
    "rtl/gpu/jupiter_gpu_2d.sv":
        "ee9759e6b5dded1d41e88d079ffcc32b3f72e996508772d3626a5bc26185d914",
    "rtl/dma/jupiter_dma.sv":
        "643c54f929373c904cb7f7a43e288a879ea3cf14b97bfd8968d8b881f8b9125d",
    "rtl/audio/jupiter_audio.sv":
        "1ccf3779f0999093cef6fa7f4bfa5db71bbfe3e1f3fa4a02ccb337660511d4b9",
    "rtl/video/jupiter_video_scanout.sv":
        "78f6b86935f941c5c94dc5cebe87be246cd97ec98027140c43688731fca6f6c5",
    "rtl/memory/jupiter_sdram_arbiter.sv":
        "54814bb653c426bcf35d76ad5988fe5356482d5ab33a74414f867ce637034f59",
    "rtl/memory/jupiter_sdram_scanout_arbiter.sv":
        "5b49b8e44ad8f124d0c2d583cc9a2ae370e9e5465316b7f4a30f6d2fa2c5ec2b",
    "rtl/memory/jupiter_sdram_frontend.sv":
        "55cfb7c60125b51712481b9fc51360aeec349b506c5741a78db746e0dc013fe0",
    "rtl/memory/jupiter_sdram_controller.sv":
        "b7008adeff428cfceb5f3b464e042198fdd536f7d6615b86aad18a6e9bfb065f",
    "rtl/memory/jupiter_internal_ram.sv":
        "ce935b378f70e9c18f22ad638fc54b14dd9c4528641f45ebbdcbe71a4a05c179",
}

for rel, expected in PROTECTED_SHA.items():
    require(
        sha(rel) == expected,
        f"protected source changed: {rel}",
    )

template = read("Template.sv")
system = read("rtl/jupiter_system.sv")
subsystem = read("rtl/jupiter_cpu_subsystem.sv")
interconnect = read("rtl/memory/jupiter_interconnect.sv")
loader = read("rtl/memory/jupiter_loader.sv")
loader_arbiter = read(
    "rtl/memory/jupiter_sdram_loader_arbiter.sv"
)
qip = read("files.qip")
makefile = read("sim/Makefile")
architecture = read("docs/CARTRIDGE_LOADING_ARCHITECTURE.md")

require(
    "M12C exact-source boundary correction" in architecture and
    "`jupiter_sdram_arbiter` and" in architecture and
    "`jupiter_sdram_scanout_arbiter` with `core_reset`" in architecture,
    "M12C reset-boundary architecture correction missing",
)

require(
    '"F1,JUP;"' in template,
    "top-level F1,JUP CONF_STR entry missing",
)
require(
    '"d0P1F1,BIN;"' not in template,
    "disabled inherited BIN placeholder still present",
)

for port in (
    ".ioctl_download(ioctl_download)",
    ".ioctl_index(ioctl_index)",
    ".ioctl_wr(ioctl_wr)",
    ".ioctl_addr(ioctl_addr)",
    ".ioctl_dout(ioctl_dout)",
    ".ioctl_wait(ioctl_wait)",
):
    require(
        port in template,
        f"hps_io connection missing: {port}",
    )

for port in (
    ".ioctl_download (ioctl_download)",
    ".ioctl_index    (ioctl_index)",
    ".ioctl_wr       (ioctl_wr)",
    ".ioctl_addr     (ioctl_addr)",
    ".ioctl_dout     (ioctl_dout)",
    ".ioctl_wait     (ioctl_wait)",
):
    require(
        port in system,
        f"jupiter_system propagation missing: {port}",
    )

require(
    "wire core_reset =" in subsystem and
    "reset ||\n        loader_active;" in subsystem,
    "core_reset expression missing",
)

for instance in (
    "jupiter_cpu cpu",
    "jupiter_video_scanout video_scanout",
    "jupiter_gpu_2d gpu",
    "jupiter_dma dma",
    "jupiter_audio audio",
):
    start = subsystem.find(instance)
    require(
        start >= 0,
        f"core-master instance missing: {instance}",
    )
    end = subsystem.find(");", start)
    require(
        end >= 0 and "core_reset" in subsystem[start:end],
        f"{instance} is not driven by core_reset",
    )

for instance in (
    "jupiter_sdram_arbiter sdram_arbiter",
    "jupiter_sdram_scanout_arbiter scanout_sdram_arbiter",
):
    start = subsystem.find(instance)
    require(
        start >= 0,
        f"game-path arbiter instance missing: {instance}",
    )
    end = subsystem.find(");", start)
    require(
        end >= 0 and "core_reset" in subsystem[start:end],
        f"{instance} must join core_reset to prevent stale held grants",
    )

for instance in (
    "jupiter_loader loader",
    "jupiter_sdram_loader_arbiter loader_sdram_arbiter",
    "jupiter_sdram_frontend sdram_frontend",
    "jupiter_sdram_controller sdram_controller",
):
    start = subsystem.find(instance)
    require(
        start >= 0,
        f"ordinary-reset instance missing: {instance}",
    )
    end = subsystem.find(");", start)
    require(
        end >= 0 and "(reset)" in subsystem[start:end],
        f"{instance} must remain on ordinary reset",
    )

require(
    ".sdram_valid    (game_sdram_valid)" in subsystem and
    "jupiter_sdram_loader_arbiter loader_sdram_arbiter" in subsystem and
    ".sdram_valid  (frontend_sdram_valid)" in subsystem,
    "third-stage loader arbitration topology missing",
)

require(
    "LOADER_START = 32'h00001500" in interconnect and
    "LOADER_END   = 32'h000015FF" in interconnect and
    "(m_addr[31:8] == 24'h000015)" in interconnect,
    "0x1500-0x15FF loader decode missing",
)

for token in (
    "8'h00:",
    "8'h04:",
    "8'h08:",
    "LOAD_BASE",
    "matching_download",
    "pending_valid",
    "ioctl_wait",
    "finish_pending",
):
    require(
        token in loader,
        f"loader feature missing: {token}",
    )

require(
    "(ioctl_index == 16'h0001)" in loader,
    "loader index-1 gate missing",
)
require(
    "next_write_addr <= (sdram_max_addr - 32'd3)" in loader,
    "loader capacity ceiling check missing",
)
require(
    "loader_valid" in loader_arbiter and
    "!loader_valid &&" in loader_arbiter and
    "GRANT_LOADER" in loader_arbiter and
    "GRANT_GAME" in loader_arbiter,
    "loader-priority non-preemptive arbiter structure missing",
)

for rel in (
    "rtl/memory/jupiter_sdram_loader_arbiter.sv",
    "rtl/memory/jupiter_loader.sv",
):
    require(
        qip.count(rel) == 1,
        f"files.qip must contain exactly one {rel}",
    )

for token in (
    "SDRAM_LOADER_ARBITER_RTL",
    "LOADER_RTL",
    "m12c-test",
    "loader-test",
    "sdram-loader-arbiter-test",
    "interconnect-loader-test",
    "loader-boundary-chain-test",
    "core-reset-test",
):
    require(
        token in makefile,
        f"simulation graph missing: {token}",
    )

# M12C is not the ISA/BIOS checkpoint.
for rel in (
    "rtl/jupiter_cpu_subsystem.sv",
    "rtl/memory/jupiter_interconnect.sv",
    "rtl/memory/jupiter_loader.sv",
    "rtl/memory/jupiter_sdram_loader_arbiter.sv",
    "rtl/jupiter_system.sv",
    "Template.sv",
):
    require(
        "JMPR" not in read(rel),
        f"JMPR leaked into M12C source: {rel}",
    )

print("M12C_TOPOLOGY_AUDIT=PASS")
print("PROTECTED_EXISTING_SDRAM_ARBITER_SHA256=PASS")
print("PROTECTED_EXISTING_SCANOUT_ARBITER_SHA256=PASS")
print("PROTECTED_SDRAM_FRONTEND_SHA256=PASS")
print("PROTECTED_SDRAM_CONTROLLER_SHA256=PASS")
print("PROTECTED_HPS_IO_SHA256=PASS")
print("TOP_LEVEL_F1_JUP_WIRING=PASS")
print("CORE_RESET_SPLIT=PASS")
print("EXISTING_GAME_ARBITERS_CORE_RESET_BOUNDARY_CORRECTION=PASS")
print("IN_FLIGHT_GAME_TRANSACTION_DRAIN_TOPOLOGY=PASS")
print("LOADER_MMIO_1500_APERTURE=PASS")
print("THIRD_STAGE_LOADER_ARBITER_TOPOLOGY=PASS")
print("M12D_JMPR_IMPLEMENTED=NO")
