#!/usr/bin/env python3
"""Build and validate Jinix Jupiter Milestone-12 .jup cartridge images."""

from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys

import build_system_image


HEADER_BYTES = 32
MAGIC_BYTES = b"JUP1"
MAGIC_WORD = 0x3150554A
FORMAT_VERSION = 1
DEFAULT_ENTRY_OFFSET = 0x20
UINT32_MASK = 0xFFFFFFFF
RESERVED_WORD_COUNT = 3


class CartridgeError(ValueError):
    """Deterministic cartridge input/format error."""


def _validate_entry_offset(
    entry_offset: int,
    image_length_bytes: int,
) -> None:
    if not isinstance(entry_offset, int):
        raise CartridgeError("ENTRY_OFFSET must be an integer")

    if not 0 <= entry_offset < image_length_bytes:
        raise CartridgeError(
            f"ENTRY_OFFSET 0x{entry_offset:X} is outside "
            f"the {image_length_bytes}-byte image"
        )


def payload_words_to_bytes(
    words: list[int],
) -> bytes:
    payload = bytearray()

    for index, word in enumerate(words):
        if not isinstance(word, int):
            raise CartridgeError(
                f"payload word {index} is not an integer"
            )

        if not 0 <= word <= UINT32_MASK:
            raise CartridgeError(
                f"payload word {index} is outside 32-bit range"
            )

        payload.extend(
            struct.pack("<I", word)
        )

    return bytes(payload)


def payload_bytes_to_words(
    payload: bytes,
) -> list[int]:
    if len(payload) & 0x3:
        raise CartridgeError(
            "payload length must be a whole number "
            "of 32-bit words"
        )

    return [
        value[0]
        for value in struct.iter_unpack("<I", payload)
    ]


def checksum_words(
    words: list[int],
) -> int:
    # CHECKSUM is a 32-bit header field. The additive checksum therefore
    # wraps modulo 2^32 when mathematical addition exceeds 32 bits.
    return sum(words) & UINT32_MASK


def build_cartridge_from_words(
    words: list[int],
    *,
    entry_offset: int = DEFAULT_ENTRY_OFFSET,
) -> bytes:
    payload = payload_words_to_bytes(words)
    image_length_bytes = HEADER_BYTES + len(payload)

    _validate_entry_offset(
        entry_offset,
        image_length_bytes,
    )

    checksum = checksum_words(words)

    header = struct.pack(
        "<8I",
        MAGIC_WORD,
        FORMAT_VERSION,
        image_length_bytes,
        entry_offset,
        checksum,
        0,
        0,
        0,
    )

    if len(header) != HEADER_BYTES:
        raise CartridgeError(
            "internal header size error"
        )

    return header + payload


def build_cartridge(
    payload: bytes,
    *,
    entry_offset: int = DEFAULT_ENTRY_OFFSET,
) -> bytes:
    words = payload_bytes_to_words(payload)

    return build_cartridge_from_words(
        words,
        entry_offset=entry_offset,
    )


def validate_cartridge(
    image: bytes,
) -> dict[str, object]:
    if len(image) < HEADER_BYTES:
        raise CartridgeError(
            "cartridge image is shorter than the 32-byte header"
        )

    payload = image[HEADER_BYTES:]

    if len(payload) & 0x3:
        raise CartridgeError(
            "payload length must be a whole number "
            "of 32-bit words"
        )

    (
        magic,
        format_version,
        image_length_bytes,
        entry_offset,
        declared_checksum,
        reserved0,
        reserved1,
        reserved2,
    ) = struct.unpack(
        "<8I",
        image[:HEADER_BYTES],
    )

    if magic != MAGIC_WORD:
        raise CartridgeError(
            "bad cartridge magic"
        )

    if format_version != FORMAT_VERSION:
        raise CartridgeError(
            f"unsupported cartridge format version "
            f"{format_version}"
        )

    if image_length_bytes != len(image):
        raise CartridgeError(
            f"declared image length {image_length_bytes} "
            f"does not match actual length {len(image)}"
        )

    _validate_entry_offset(
        entry_offset,
        image_length_bytes,
    )

    if any((reserved0, reserved1, reserved2)):
        raise CartridgeError(
            "reserved header words must be zero"
        )

    words = payload_bytes_to_words(payload)
    computed_checksum = checksum_words(words)

    if declared_checksum != computed_checksum:
        raise CartridgeError(
            f"checksum mismatch: declared 0x{declared_checksum:08X}, "
            f"computed 0x{computed_checksum:08X}"
        )

    return {
        "magic": MAGIC_BYTES,
        "format_version": format_version,
        "image_length_bytes": image_length_bytes,
        "entry_offset": entry_offset,
        "checksum": declared_checksum,
        "payload_words": words,
    }


def _cli_int(
    text: str,
) -> int:
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
            "Build a Jinix Jupiter Milestone-12 "
            ".jup cartridge image."
        ),
    )

    parser.add_argument(
        "--payload",
        required=True,
        type=Path,
        help=(
            "flat Jupiter word stream: exactly eight "
            "hexadecimal digits per line"
        ),
    )

    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="binary .jup output path",
    )

    parser.add_argument(
        "--entry-offset",
        type=_cli_int,
        default=DEFAULT_ENTRY_OFFSET,
        help=(
            "byte offset from LOAD_BASE to first instruction "
            "(default: 0x20)"
        ),
    )

    args = parser.parse_args(argv)

    try:
        # Deliberately reuse the existing M9 image-builder parser so M12
        # accepts exactly the established eight-hex-digit word-text form.
        words = build_system_image.read_word_stream(
            args.payload
        )

        image = build_cartridge_from_words(
            words,
            entry_offset=args.entry_offset,
        )

        # Reassembly-check the exact bytes before any output is emitted.
        validate_cartridge(image)

        args.output.write_bytes(image)

    except (
        build_system_image.ImageError,
        CartridgeError,
        OSError,
    ) as exc:
        print(
            f"error: {exc}",
            file=sys.stderr,
        )

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

