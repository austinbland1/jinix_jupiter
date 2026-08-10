#!/usr/bin/env python3
"""Build the Milestone-9 Jupiter 4 KiB system image."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


RAM_BYTES = 4096
RAM_WORDS = 1024

BIOS_DEFAULT_BASE = 0x00000000
APP_DEFAULT_BASE = 0x00000400

BIOS_MAX_WORDS = 256
APP_MAX_WORDS = 768

WORD_RE = re.compile(
    r"[0-9A-Fa-f]{8}\Z"
)


class ImageError(ValueError):
    """Deterministic image input/layout error."""


def read_word_stream(
    path: Path,
) -> list[int]:
    try:
        text = path.read_text()
    except OSError as exc:
        raise ImageError(
            f"{path}: {exc}"
        ) from exc

    if text == "":
        return []

    words = []

    for line_no, line in enumerate(
        text.splitlines(),
        start=1,
    ):
        if WORD_RE.fullmatch(line) is None:
            raise ImageError(
                f"{path}: line {line_no}: expected exactly "
                "eight hexadecimal digits"
            )

        words.append(
            int(line, 16)
        )

    return words


def _validate_base(
    name: str,
    base: int,
) -> int:
    if not isinstance(base, int):
        raise ImageError(
            f"{name} base must be an integer"
        )

    if base & 0x3:
        raise ImageError(
            f"{name} base 0x{base:X} is not 4-byte aligned"
        )

    if not 0 <= base < RAM_BYTES:
        raise ImageError(
            f"{name} base 0x{base:X} is outside "
            "the 4 KiB RAM aperture"
        )

    return base // 4


def build_image(
    bios_words: list[int],
    app_words: list[int],
    *,
    bios_base: int = BIOS_DEFAULT_BASE,
    app_base: int = APP_DEFAULT_BASE,
) -> list[int]:

    if len(bios_words) > BIOS_MAX_WORDS:
        raise ImageError(
            f"BIOS has {len(bios_words)} words; "
            f"maximum is {BIOS_MAX_WORDS}"
        )

    if len(app_words) > APP_MAX_WORDS:
        raise ImageError(
            f"application has {len(app_words)} words; "
            f"maximum is {APP_MAX_WORDS}"
        )

    bios_index = _validate_base(
        "BIOS",
        bios_base,
    )

    app_index = _validate_base(
        "application",
        app_base,
    )

    bios_end = bios_index + len(bios_words)
    app_end = app_index + len(app_words)

    if bios_end > RAM_WORDS:
        raise ImageError(
            "BIOS content extends outside "
            "the 4 KiB RAM aperture"
        )

    if app_end > RAM_WORDS:
        raise ImageError(
            "application content extends outside "
            "the 4 KiB RAM aperture"
        )

    if (
        bios_words
        and app_words
        and bios_index < app_end
        and app_index < bios_end
    ):
        raise ImageError(
            "BIOS and application regions overlap"
        )

    image = [0] * RAM_WORDS

    for offset, word in enumerate(
        bios_words
    ):
        if not 0 <= word <= 0xFFFFFFFF:
            raise ImageError(
                f"BIOS word {offset} is outside "
                "the 32-bit range"
            )

        image[bios_index + offset] = word

    for offset, word in enumerate(
        app_words
    ):
        if not 0 <= word <= 0xFFFFFFFF:
            raise ImageError(
                f"application word {offset} is outside "
                "the 32-bit range"
            )

        image[app_index + offset] = word

    return image


def format_image(
    words: list[int],
) -> str:
    if len(words) != RAM_WORDS:
        raise ImageError(
            "system image must contain "
            f"exactly {RAM_WORDS} words"
        )

    return "".join(
        f"{word:08X}\n"
        for word in words
    )


def _cli_int(text: str) -> int:
    try:
        return int(text, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"invalid integer: {text}"
        ) from exc


def main(
    argv: list[str] | None = None,
) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Build the 1024-word Milestone-9 "
            "Jupiter internal-RAM image."
        ),
    )

    parser.add_argument(
        "--bios",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--app",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--output",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--bios-base",
        type=_cli_int,
        default=BIOS_DEFAULT_BASE,
    )

    parser.add_argument(
        "--app-base",
        type=_cli_int,
        default=APP_DEFAULT_BASE,
    )

    args = parser.parse_args(argv)

    try:
        image = build_image(
            read_word_stream(args.bios),
            read_word_stream(args.app),
            bios_base=args.bios_base,
            app_base=args.app_base,
        )

        args.output.write_text(
            format_image(image)
        )

    except (ImageError, OSError) as exc:
        print(
            f"error: {exc}",
            file=sys.stderr,
        )

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
