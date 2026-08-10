#!/usr/bin/env python3

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import build_system_image


class SystemImageTests(unittest.TestCase):

    def test_default_layout(self):
        image = build_system_image.build_image(
            [
                0x320000FF,
                0x00000000,
            ],
            [
                0x10080005,
                0xFF000000,
            ],
        )

        self.assertEqual(
            len(image),
            1024,
        )

        self.assertEqual(
            image[0:2],
            [
                0x320000FF,
                0x00000000,
            ],
        )

        self.assertEqual(
            image[256:258],
            [
                0x10080005,
                0xFF000000,
            ],
        )

        self.assertTrue(
            all(
                word == 0
                for word in image[2:256]
            )
        )

        self.assertTrue(
            all(
                word == 0
                for word in image[258:]
            )
        )


    def test_maximum_default_regions(self):
        image = build_system_image.build_image(
            [0] * 256,
            [0xFFFFFFFF] * 768,
        )

        self.assertEqual(
            len(image),
            1024,
        )

        self.assertEqual(
            image[255],
            0,
        )

        self.assertEqual(
            image[256],
            0xFFFFFFFF,
        )

        self.assertEqual(
            image[1023],
            0xFFFFFFFF,
        )


    def test_layout_failures(self):
        cases = [
            (
                lambda: build_system_image.build_image(
                    [0] * 257,
                    [],
                ),
                "BIOS has 257 words",
            ),
            (
                lambda: build_system_image.build_image(
                    [],
                    [0] * 769,
                ),
                "application has 769 words",
            ),
            (
                lambda: build_system_image.build_image(
                    [0],
                    [],
                    bios_base=2,
                ),
                "not 4-byte aligned",
            ),
            (
                lambda: build_system_image.build_image(
                    [],
                    [0],
                    app_base=0x1000,
                ),
                "outside the 4 KiB RAM aperture",
            ),
            (
                lambda: build_system_image.build_image(
                    [],
                    [0, 0],
                    app_base=0x0FFC,
                ),
                "extends outside",
            ),
            (
                lambda: build_system_image.build_image(
                    [0, 0],
                    [0],
                    app_base=4,
                ),
                "overlap",
            ),
            (
                lambda: build_system_image.build_image(
                    [0x1_00000000],
                    [],
                ),
                "outside the 32-bit range",
            ),
        ]

        for function, pattern in cases:
            with self.subTest(pattern=pattern):
                with self.assertRaisesRegex(
                    build_system_image.ImageError,
                    pattern,
                ):
                    function()


    def test_word_stream_validation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)

            good = temp / "good.hex"

            good.write_text(
                "00000000\n"
                "deadBEEF\n"
                "FFFFFFFF\n"
            )

            self.assertEqual(
                build_system_image.read_word_stream(
                    good
                ),
                [
                    0,
                    0xDEADBEEF,
                    0xFFFFFFFF,
                ],
            )

            bad_values = [
                "1234567\n",
                "123456789\n",
                "GGGGGGGG\n",
                "00000000 \n",
                "00000000\n\nFF000000\n",
            ]

            for index, text in enumerate(
                bad_values
            ):
                bad = (
                    temp
                    / f"bad_{index}.hex"
                )

                bad.write_text(text)

                with self.assertRaisesRegex(
                    build_system_image.ImageError,
                    "expected exactly eight hexadecimal digits",
                ):
                    build_system_image.read_word_stream(
                        bad
                    )


    def test_empty_stream(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = (
                Path(temp_dir)
                / "empty.hex"
            )

            path.write_text("")

            self.assertEqual(
                build_system_image.read_word_stream(
                    path
                ),
                [],
            )


    def test_exact_output_format(self):
        text = build_system_image.format_image(
            [0] * 1024
        )

        self.assertEqual(
            len(text.splitlines()),
            1024,
        )

        self.assertTrue(
            text.endswith("\n")
        )

        self.assertTrue(
            all(
                line == "00000000"
                for line in text.splitlines()
            )
        )


    def test_cli(self):
        script = Path(__file__).with_name(
            "build_system_image.py"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)

            bios = temp / "bios.hex"
            app = temp / "app.hex"
            output = temp / "system.mem"

            bios.write_text(
                "320000FF\n"
                "00000000\n"
            )

            app.write_text(
                "10080005\n"
                "FF000000\n"
            )

            result = subprocess.run(
                [
                    sys.executable,
                    "-B",
                    str(script),
                    "--bios",
                    str(bios),
                    "--app",
                    str(app),
                    "--output",
                    str(output),
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

            lines = output.read_text().splitlines()

            self.assertEqual(
                len(lines),
                1024,
            )

            self.assertEqual(
                lines[0],
                "320000FF",
            )

            self.assertEqual(
                lines[256],
                "10080005",
            )

            self.assertEqual(
                lines[1023],
                "00000000",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
