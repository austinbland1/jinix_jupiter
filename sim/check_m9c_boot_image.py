#!/usr/bin/env python3
"""Validate deterministic M9C BIOS/application/system-image artifacts."""

from pathlib import Path
import sys

EXPECTED_APP = [
    "10081000",
    "1010002A",
    "21104000",
    "FF000000",
]
RAM_WORDS = 1024
APP_WORD_INDEX = 0x400 // 4


class CheckError(ValueError):
    pass


def read_lines(path):
    try:
        return Path(path).read_text().splitlines()
    except OSError as exc:
        raise CheckError(f"{path}: {exc}") from exc
EXPECTED_BIOS = read_lines(Path("m9c_bios.hex"))


def check_artifacts(bios_path, app_path, image_path):
    bios = read_lines(bios_path)
    app = read_lines(app_path)
    image = read_lines(image_path)

    if bios != EXPECTED_BIOS:
        raise CheckError(
            f"unexpected BIOS words: {bios!r}; expected {EXPECTED_BIOS!r}"
        )

    if app != EXPECTED_APP:
        raise CheckError(
            f"unexpected application words: {app!r}; expected {EXPECTED_APP!r}"
        )

    if len(image) != RAM_WORDS:
        raise CheckError(
            f"system image has {len(image)} words; expected {RAM_WORDS}"
        )

    if image[0] != EXPECTED_BIOS[0]:
        raise CheckError("system image BIOS entry word is wrong")

    if any(word != "00000000" for word in image[len(EXPECTED_BIOS):APP_WORD_INDEX]):
        raise CheckError("system image BIOS padding is not zero-filled")

    app_end = APP_WORD_INDEX + len(EXPECTED_APP)

    if image[APP_WORD_INDEX:app_end] != EXPECTED_APP:
        raise CheckError("system image application placement is wrong")

    if any(word != "00000000" for word in image[app_end:]):
        raise CheckError("system image trailing padding is not zero-filled")


def main():
    if len(sys.argv) != 4:
        print(
            "usage: check_m9c_boot_image.py BIOS_HEX APP_HEX SYSTEM_MEM",
            file=sys.stderr,
        )
        return 2

    try:
        check_artifacts(sys.argv[1], sys.argv[2], sys.argv[3])
    except CheckError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print("PASS: BIOS assembler output is exact")
    print("PASS: application assembler output is exact")
    print("PASS: system image contains exactly 1024 words")
    print("PASS: BIOS is placed at 0x00000000")
    print("PASS: application is placed at 0x00000400")
    print("PASS: unused system-image words are zero-filled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
