#!/usr/bin/env python3
"""Tests for the Jinix Jupiter Milestone-12 .jup cartridge builder."""

from __future__ import annotations

from contextlib import redirect_stderr
import io
from pathlib import Path
import struct
import tempfile
import unittest

import build_cartridge


class CartridgeBuilderTests(unittest.TestCase):
    def test_exact_header_and_little_endian_payload(self) -> None:
        words = [
            0x11223344,
            0xAABBCCDD,
        ]

        image = build_cartridge.build_cartridge_from_words(
            words
        )

        self.assertEqual(
            len(image),
            40,
        )
        self.assertEqual(
            image[:4],
            b"JUP1",
        )
        self.assertEqual(
            image[32:],
            bytes.fromhex(
                "44 33 22 11 "
                "DD CC BB AA"
            ),
        )

        header = struct.unpack(
            "<8I",
            image[:32],
        )

        self.assertEqual(
            header,
            (
                0x3150554A,
                1,
                40,
                0x20,
                0xBBDE0021,
                0,
                0,
                0,
            ),
        )

    def test_checksum_wraps_in_32_bit_field(self) -> None:
        self.assertEqual(
            build_cartridge.checksum_words(
                [
                    0xFFFFFFFF,
                    0x00000002,
                ]
            ),
            0x00000001,
        )

    def test_round_trip_reassembly_check(self) -> None:
        words = [
            0x01020304,
            0x05060708,
            0xFFFFFFFF,
        ]

        image = build_cartridge.build_cartridge_from_words(
            words,
            entry_offset=0x24,
        )

        parsed = build_cartridge.validate_cartridge(
            image
        )

        self.assertEqual(
            parsed["magic"],
            b"JUP1",
        )
        self.assertEqual(
            parsed["format_version"],
            1,
        )
        self.assertEqual(
            parsed["image_length_bytes"],
            44,
        )
        self.assertEqual(
            parsed["entry_offset"],
            0x24,
        )
        self.assertEqual(
            parsed["payload_words"],
            words,
        )

    def test_payload_bytes_must_be_word_aligned(self) -> None:
        with self.assertRaises(
            build_cartridge.CartridgeError,
        ):
            build_cartridge.build_cartridge(
                b"\x00\x01\x02",
            )

    def test_entry_offset_outside_image_rejected(self) -> None:
        with self.assertRaises(
            build_cartridge.CartridgeError,
        ):
            build_cartridge.build_cartridge_from_words(
                [0x00000000],
                entry_offset=0x24,
            )

    def test_bad_magic_rejected_on_reassembly(self) -> None:
        image = bytearray(
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
        )
        image[0] ^= 0x01

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "bad cartridge magic",
        ):
            build_cartridge.validate_cartridge(
                bytes(image)
            )

    def test_declared_length_mismatch_rejected(self) -> None:
        image = bytearray(
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
        )
        struct.pack_into(
            "<I",
            image,
            0x08,
            len(image) + 4,
        )

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "declared image length",
        ):
            build_cartridge.validate_cartridge(
                bytes(image)
            )

    def test_non_word_aligned_binary_payload_rejected(self) -> None:
        image = (
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
            + b"\x00"
        )

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "whole number of 32-bit words",
        ):
            build_cartridge.validate_cartridge(
                image
            )

    def test_reserved_header_word_must_be_zero(self) -> None:
        image = bytearray(
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
        )
        struct.pack_into(
            "<I",
            image,
            0x14,
            1,
        )

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "reserved header words must be zero",
        ):
            build_cartridge.validate_cartridge(
                bytes(image)
            )

    def test_checksum_mismatch_rejected(self) -> None:
        image = bytearray(
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
        )
        struct.pack_into(
            "<I",
            image,
            0x10,
            0,
        )

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "checksum mismatch",
        ):
            build_cartridge.validate_cartridge(
                bytes(image)
            )

    def test_unsupported_format_version_rejected(self) -> None:
        image = bytearray(
            build_cartridge.build_cartridge_from_words(
                [0x12345678]
            )
        )
        struct.pack_into(
            "<I",
            image,
            0x04,
            2,
        )

        with self.assertRaisesRegex(
            build_cartridge.CartridgeError,
            "unsupported cartridge format version",
        ):
            build_cartridge.validate_cartridge(
                bytes(image)
            )

    def test_cli_reuses_existing_word_text_validation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            payload = temp / "bad.hex"
            output = temp / "bad.jup"

            payload.write_text(
                "1234\n"
            )

            stderr = io.StringIO()

            with redirect_stderr(stderr):
                status = build_cartridge.main(
                    [
                        "--payload",
                        str(payload),
                        "--output",
                        str(output),
                    ]
                )

            self.assertEqual(
                status,
                1,
            )
            self.assertIn(
                "expected exactly eight hexadecimal digits",
                stderr.getvalue(),
            )
            self.assertFalse(
                output.exists()
            )

    def test_cli_builds_exact_binary_and_reassembly_validates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            payload = temp / "program.hex"
            output = temp / "program.jup"

            payload.write_text(
                "11223344\n"
                "aabbccdd\n"
            )

            status = build_cartridge.main(
                [
                    "--payload",
                    str(payload),
                    "--output",
                    str(output),
                ]
            )

            self.assertEqual(
                status,
                0,
            )

            image = output.read_bytes()

            self.assertEqual(
                image[:4],
                b"JUP1",
            )
            self.assertEqual(
                image[32:],
                bytes.fromhex(
                    "44 33 22 11 "
                    "DD CC BB AA"
                ),
            )

            parsed = build_cartridge.validate_cartridge(
                image
            )

            self.assertEqual(
                parsed["payload_words"],
                [
                    0x11223344,
                    0xAABBCCDD,
                ],
            )

    def test_rejected_cli_does_not_modify_existing_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            payload = temp / "bad.hex"
            output = temp / "existing.jup"

            payload.write_text(
                "NOTAWORD\n"
            )
            output.write_bytes(
                b"sentinel"
            )

            stderr = io.StringIO()

            with redirect_stderr(stderr):
                status = build_cartridge.main(
                    [
                        "--payload",
                        str(payload),
                        "--output",
                        str(output),
                    ]
                )

            self.assertEqual(
                status,
                1,
            )
            self.assertEqual(
                output.read_bytes(),
                b"sentinel",
            )


if __name__ == "__main__":
    unittest.main()

