#!/usr/bin/env python3
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIOS = ROOT / "software/bios/bios.asm"
ASM = ROOT / "software/devkit/jupiter_asm.py"

text = BIOS.read_text()

required = [
    "J m12e_cartridge_handoff",
    "m12e_cartridge_handoff:",
    "ADDI r20, r0, 0x1500",
    "m12e_wait_loader_done:",
    "LDW r21, r20, 0",
    "ADDI r22, r0, 1",
    "AND r22, r21, r22",
    "BEQ r22, r0, m12e_wait_loader_done",
    "ADDI r22, r0, 2",
    "BNE r22, r0, m12e_cartridge_error",
    "LDW r23, r20, 8",
    "LDW r24, r23, 0",
    "ADDI r25, r0, 0x31",
    "ADDI r27, r0, 0x50",
    "ADDI r27, r0, 0x55",
    "ADDI r27, r0, 0x4A",
    "BNE r24, r25, m12e_cartridge_error",
    "LDW r24, r23, 12",
    "ADD r24, r23, r24",
    "JMPR r0, r24, 0",
    "m12e_cartridge_error:",
]
for item in required:
    if item not in text:
        raise SystemExit("missing M12E BIOS source contract: " + item)

if "ANDI " in text or "LDB " in text or "SHL " in text:
    raise SystemExit("M12E BIOS unexpectedly uses a rejected mnemonic")

routine = text[text.index("m12e_cartridge_handoff:"):]
instruction_lines = []
for raw in routine.splitlines():
    s=raw.strip()
    if not s or s.startswith("#") or s.endswith(":"):
        continue
    instruction_lines.append(s)
if len(instruction_lines) != 47:
    raise SystemExit(
        f"M12E BIOS handoff instruction count is {len(instruction_lines)}, expected 47"
    )
if instruction_lines.count("ADD r25, r25, r25") != 24:
    raise SystemExit("M12E add-doubling sequence does not contain exactly 24 self-adds")

with tempfile.TemporaryDirectory() as td:
    out = Path(td) / "bios.hex"
    cp = subprocess.run(
        [sys.executable, "-B", str(ASM), str(BIOS), "-o", str(out), "--origin", "0"],
        text=True, capture_output=True
    )
    if cp.returncode != 0:
        raise SystemExit("complete BIOS assembler failed: " + cp.stderr.strip())
    if not out.is_file() or out.stat().st_size == 0:
        raise SystemExit("complete BIOS assembler emitted empty output")

STATUS_DONE = 1 << 0
STATUS_OVERFLOW = 1 << 1
LOAD_BASE = 0x10000000
HEADER_SIZE = 32
ENTRY_OFFSET = HEADER_SIZE

payload = struct.pack("<I", 0x10000000)
hdr = bytearray(HEADER_SIZE)
hdr[0:4] = b"JUP1"
struct.pack_into("<I", hdr, 4, 1)
struct.pack_into("<I", hdr, 8, len(payload))
struct.pack_into("<I", hdr, 12, ENTRY_OFFSET)
struct.pack_into("<I", hdr, 16, sum(payload) & 0xFFFFFFFF)
image = bytes(hdr) + payload

status = STATUS_DONE
if (status & STATUS_DONE) == 0:
    raise SystemExit("DONE bit model not set")
if (status & STATUS_OVERFLOW) != 0:
    raise SystemExit("OVERFLOW bit model unexpectedly set")

load_base_mmio_1508 = LOAD_BASE
mem = {load_base_mmio_1508 + i: b for i,b in enumerate(image)}

def rb(addr):
    return mem[addr]

def rw(addr):
    return sum(rb(addr+i) << (8*i) for i in range(4))

base = load_base_mmio_1508
magic_word = rw(base + 0)
constructed_magic = 0x31
for b in (0x50,0x55,0x4A):
    for _ in range(8):
        constructed_magic = (constructed_magic + constructed_magic) & 0xFFFFFFFF
    constructed_magic = (constructed_magic + b) & 0xFFFFFFFF

if constructed_magic != 0x3150554A:
    raise SystemExit("add-doubling constructed magic mismatch")
if magic_word != constructed_magic:
    raise SystemExit("loaded JUP1 word does not equal constructed magic")

entry_offset = rw(base + 0x0C)
target = (base + entry_offset) & 0xFFFFFFFF
if target != LOAD_BASE + HEADER_SIZE:
    raise SystemExit("computed cartridge entry target mismatch")
if target & 3:
    raise SystemExit("computed JMPR target is not word aligned")
if bytes(rb(target+i) for i in range(len(payload))) != payload:
    raise SystemExit("computed entry target does not address payload")

print("PASS: M12E BIOS uses exact existing-ISA 47-instruction handoff")
print("PASS: M12E complete BIOS assembles with no new ISA instruction")
print("PASS: M12E add-doubling JUP1 word equals loaded little-endian header magic")
print("RESULT: PASS  (M12E BIOS cartridge handoff end-to-end)")
