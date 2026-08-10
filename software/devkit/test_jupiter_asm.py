#!/usr/bin/env python3

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import jupiter_asm


class AssemblerTests(unittest.TestCase):

    def test_all_golden_encodings(self):
        source = """
            NOP
            ADD r1, r2, r3
            SUB r4, r5, r6
            AND r7, r8, r9
            OR r10, r11, r12
            XOR r13, r14, r15
            ADDI r1, r0, 5
            ADDI r2, r1, -1
            LDW r3, r4, 12
            STW r5, r6, -4
            BEQ r1, r2, 2
            BNE r3, r4, -3
            J 4
            J -2
            HALT
        """

        self.assertEqual(
            jupiter_asm.assemble(source),
            [
                0x00000000,
                0x01088600,
                0x02214C00,
                0x033A1200,
                0x0452D800,
                0x056B9E00,
                0x10080005,
                0x10107FFF,
                0x2019000C,
                0x2129BFFC,
                0x30088002,
                0x31193FFD,
                0x32000004,
                0x32FFFFFE,
                0xFF000000,
            ],
        )


    def test_forward_and_backward_labels(self):
        self.assertEqual(
            jupiter_asm.assemble(
                """
start:
    BEQ r1, r1, forward
    NOP
forward:
    BNE r2, r3, start
    J forward
    HALT
"""
            ),
            [
                0x30084001,
                0x00000000,
                0x3110FFFD,
                0x32FFFFFE,
                0xFF000000,
            ],
        )


    def test_origin_label_resolution(self):
        self.assertEqual(
            jupiter_asm.assemble(
                """
    J target
    NOP
target:
    HALT
""",
                origin=0x400,
            ),
            [
                0x32000001,
                0x00000000,
                0xFF000000,
            ],
        )


    def test_signed_14_bit_boundaries(self):
        words = jupiter_asm.assemble(
            """
    ADDI r1, r0, 8191
    ADDI r1, r0, -8192
    BEQ r0, r0, 8191
    BNE r0, r0, -8192
"""
        )

        self.assertEqual(
            [word & 0x3FFF for word in words],
            [
                0x1FFF,
                0x2000,
                0x1FFF,
                0x2000,
            ],
        )


    def test_signed_24_bit_boundaries(self):
        self.assertEqual(
            jupiter_asm.assemble(
                """
    J 8388607
    J -8388608
"""
            ),
            [
                0x327FFFFF,
                0x32800000,
            ],
        )


    def test_r31_and_case_insensitivity(self):
        self.assertEqual(
            jupiter_asm.assemble(
                """
    xor R31, r31, R31
    halt
"""
            ),
            [
                0x05FFFE00,
                0xFF000000,
            ],
        )


    def test_comments(self):
        self.assertEqual(
            jupiter_asm.assemble(
                """
    ADD r1, r2, r3 # hash
    HALT ; semicolon
"""
            ),
            [
                0x01088600,
                0xFF000000,
            ],
        )


    def test_deterministic_failures(self):
        cases = [
            (
                "MUL r1, r2, r3",
                "unknown mnemonic",
            ),
            (
                "ADD x1, r2, r3",
                "invalid register",
            ),
            (
                "ADD r32, r2, r3",
                "register out of range",
            ),
            (
                "ADD r1, r2",
                "expects 3 operand",
            ),
            (
                "ADD r1,,r3",
                "malformed comma-separated",
            ),
            (
                "J missing",
                "unknown label",
            ),
            (
                "ADDI r1, r0, 8192",
                "signed 14-bit",
            ),
            (
                "ADDI r1, r0, -8193",
                "signed 14-bit",
            ),
            (
                "BEQ r1, r2, 8192",
                "signed 14-bit",
            ),
            (
                "J 8388608",
                "signed 24-bit",
            ),
            (
                "J -8388609",
                "signed 24-bit",
            ),
        ]

        for source, pattern in cases:
            with self.subTest(source=source):
                with self.assertRaisesRegex(
                    jupiter_asm.AssemblerError,
                    pattern,
                ):
                    jupiter_asm.assemble(
                        source
                    )


    def test_duplicate_label(self):
        with self.assertRaisesRegex(
            jupiter_asm.AssemblerError,
            "duplicate label",
        ):
            jupiter_asm.assemble(
                """
same:
    NOP
same:
    HALT
"""
            )


    def test_unaligned_origin_rejected(self):
        with self.assertRaisesRegex(
            jupiter_asm.AssemblerError,
            "4-byte aligned",
        ):
            jupiter_asm.assemble(
                "HALT",
                origin=2,
            )


    def test_cli_exact_hex_output(self):
        script = Path(__file__).with_name(
            "jupiter_asm.py"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)

            source = temp / "program.asm"
            output = temp / "program.hex"

            source.write_text(
                """
start:
    ADDI r1, r0, 5
    J done
    ADDI r1, r0, 99
done:
    HALT
"""
            )

            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(script),
                    str(source),
                    "-o",
                    str(output),
                    "--origin",
                    "0x400",
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(
                result.returncode,
                0,
                result.stderr,
            )

            self.assertEqual(
                output.read_text(),
                "10080005\n"
                "32000001\n"
                "10080063\n"
                "FF000000\n",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
