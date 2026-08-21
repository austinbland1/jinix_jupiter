#!/usr/bin/env python3
# Deterministic M12D JMPR assembler encoding regression.

from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ASSEMBLER = HERE.parent / "software" / "devkit" / "jupiter_asm.py"
SOURCE = 'JMPR r0, r5, 0\nJMPR r0, r5, -16\n'

def encode_i(opcode, rd, rs1, imm14):
    return (
        ((opcode & 0xff) << 24)
        | ((rd & 0x1f) << 19)
        | ((rs1 & 0x1f) << 14)
        | (imm14 & 0x3fff)
    )

EXPECTED = [
    encode_i(0x33, 0, 5, 0),
    encode_i(0x33, 0, 5, -16),
]

def parse_words(path):
    words = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        match = re.fullmatch(r"(?:0x)?([0-9a-fA-F]{8})", line)
        if not match:
            raise SystemExit(f"FAIL: unexpected assembler output line: {raw!r}")
        words.append(int(match.group(1), 16))
    return words

with tempfile.TemporaryDirectory() as td:
    temp = Path(td)
    src = temp / "jmpr.asm"
    out = temp / "jmpr.hex"
    src.write_text(SOURCE)

    proc = subprocess.run(
        [
            sys.executable,
            str(ASSEMBLER),
            str(src),
            "-o",
            str(out),
            "--origin",
            "0x00000000",
        ],
        cwd=HERE.parent / "software" / "devkit",
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        print(proc.stdout, end="")
        print(proc.stderr, end="", file=sys.stderr)
        raise SystemExit("FAIL: JMPR assembler invocation returned nonzero")

    words = parse_words(out)
    if words != EXPECTED:
        raise SystemExit(
            "FAIL: JMPR encoding mismatch: "
            f"expected={[f'0x{w:08X}' for w in EXPECTED]!r} "
            f"got={[f'0x{w:08X}' for w in words]!r}"
        )

print("PASS: JMPR assembler emits exact positive and negative imm14 encodings")
