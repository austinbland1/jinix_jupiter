#!/usr/bin/env python3
"""Minimum Jinix Jupiter assembler selected by Milestone 9."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


OPCODES = {
    "NOP": 0x00,
    "ADD": 0x01,
    "SUB": 0x02,
    "AND": 0x03,
    "OR": 0x04,
    "XOR": 0x05,
    "ADDI": 0x10,
    "LDW": 0x20,
    "STW": 0x21,
    "BEQ": 0x30,
    "BNE": 0x31,
    "J": 0x32,
    "HALT": 0xFF,
}

R_MNEMONICS = {"ADD", "SUB", "AND", "OR", "XOR"}
I_MNEMONICS = {"ADDI", "LDW"}
B_MNEMONICS = {"BEQ", "BNE"}
N_MNEMONICS = {"NOP", "HALT"}

LABEL_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
REGISTER_RE = re.compile(r"[rR]([0-9]+)\Z")


class AssemblerError(ValueError):
    """Deterministic source error."""


def _error(line_no: int, message: str) -> AssemblerError:
    return AssemblerError(f"line {line_no}: {message}")


def _strip_comment(line: str) -> str:
    positions = [
        pos
        for marker in ("#", ";")
        if (pos := line.find(marker)) >= 0
    ]

    if positions:
        return line[:min(positions)]

    return line


def _parse_register(token: str, line_no: int) -> int:
    match = REGISTER_RE.fullmatch(token.strip())

    if match is None:
        raise _error(
            line_no,
            f"invalid register {token!r}; expected r0..r31",
        )

    value = int(match.group(1), 10)

    if not 0 <= value <= 31:
        raise _error(
            line_no,
            f"register out of range: r{value}",
        )

    return value


def _parse_integer(
    token: str,
    line_no: int,
    what: str,
) -> int:
    try:
        return int(token.strip(), 0)
    except ValueError as exc:
        raise _error(
            line_no,
            f"invalid {what} {token!r}",
        ) from exc


def _require_signed(
    value: int,
    bits: int,
    line_no: int,
    what: str,
) -> int:
    minimum = -(1 << (bits - 1))
    maximum = (1 << (bits - 1)) - 1

    if not minimum <= value <= maximum:
        raise _error(
            line_no,
            f"{what} {value} does not fit signed {bits}-bit "
            f"range [{minimum}, {maximum}]",
        )

    return value & ((1 << bits) - 1)


def _split_operands(
    rest: str,
    line_no: int,
) -> list[str]:
    if not rest.strip():
        return []

    operands = [
        part.strip()
        for part in rest.split(",")
    ]

    if any(not operand for operand in operands):
        raise _error(
            line_no,
            "malformed comma-separated operand list",
        )

    return operands


def _expect_operands(
    mnemonic: str,
    operands: list[str],
    count: int,
    line_no: int,
) -> None:
    if len(operands) != count:
        raise _error(
            line_no,
            f"{mnemonic} expects {count} operand(s), "
            f"got {len(operands)}",
        )


def _resolve_pc_relative(
    token: str,
    labels: dict[str, int],
    pc: int,
    bits: int,
    line_no: int,
) -> int:
    if token in labels:
        delta = labels[token] - (pc + 4)

        if delta % 4 != 0:
            raise _error(
                line_no,
                f"label {token!r} is not word-aligned "
                "relative to PC + 4",
            )

        offset = delta // 4

    elif LABEL_RE.fullmatch(token):
        raise _error(
            line_no,
            f"unknown label {token!r}",
        )

    else:
        offset = _parse_integer(
            token,
            line_no,
            "PC-relative word offset",
        )

    return _require_signed(
        offset,
        bits,
        line_no,
        f"PC-relative word offset for {token!r}",
    )


def _encode_instruction(
    text: str,
    line_no: int,
    pc: int,
    labels: dict[str, int],
) -> int:
    fields = text.split(None, 1)

    mnemonic = fields[0].upper()
    rest = fields[1] if len(fields) == 2 else ""

    operands = _split_operands(
        rest,
        line_no,
    )

    if mnemonic not in OPCODES:
        raise _error(
            line_no,
            f"unknown mnemonic {fields[0]!r}",
        )

    opcode = OPCODES[mnemonic]


    if mnemonic in N_MNEMONICS:
        _expect_operands(
            mnemonic,
            operands,
            0,
            line_no,
        )

        return opcode << 24


    if mnemonic in R_MNEMONICS:
        _expect_operands(
            mnemonic,
            operands,
            3,
            line_no,
        )

        rd = _parse_register(
            operands[0],
            line_no,
        )

        rs1 = _parse_register(
            operands[1],
            line_no,
        )

        rs2 = _parse_register(
            operands[2],
            line_no,
        )

        return (
            (opcode << 24)
            | (rd << 19)
            | (rs1 << 14)
            | (rs2 << 9)
        )


    if mnemonic in I_MNEMONICS:
        _expect_operands(
            mnemonic,
            operands,
            3,
            line_no,
        )

        rd = _parse_register(
            operands[0],
            line_no,
        )

        rs1 = _parse_register(
            operands[1],
            line_no,
        )

        imm14 = _require_signed(
            _parse_integer(
                operands[2],
                line_no,
                "immediate",
            ),
            14,
            line_no,
            "immediate",
        )

        return (
            (opcode << 24)
            | (rd << 19)
            | (rs1 << 14)
            | imm14
        )


    if mnemonic == "STW":
        _expect_operands(
            mnemonic,
            operands,
            3,
            line_no,
        )

        rs2 = _parse_register(
            operands[0],
            line_no,
        )

        rs1 = _parse_register(
            operands[1],
            line_no,
        )

        imm14 = _require_signed(
            _parse_integer(
                operands[2],
                line_no,
                "store byte offset",
            ),
            14,
            line_no,
            "store byte offset",
        )

        return (
            (opcode << 24)
            | (rs2 << 19)
            | (rs1 << 14)
            | imm14
        )


    if mnemonic in B_MNEMONICS:
        _expect_operands(
            mnemonic,
            operands,
            3,
            line_no,
        )

        rs1 = _parse_register(
            operands[0],
            line_no,
        )

        rs2 = _parse_register(
            operands[1],
            line_no,
        )

        off14 = _resolve_pc_relative(
            operands[2],
            labels,
            pc,
            14,
            line_no,
        )

        return (
            (opcode << 24)
            | (rs1 << 19)
            | (rs2 << 14)
            | off14
        )


    if mnemonic == "J":
        _expect_operands(
            mnemonic,
            operands,
            1,
            line_no,
        )

        off24 = _resolve_pc_relative(
            operands[0],
            labels,
            pc,
            24,
            line_no,
        )

        return (
            (opcode << 24)
            | off24
        )


    raise _error(
        line_no,
        f"internal assembler format error for {mnemonic}",
    )


def assemble(
    source: str,
    origin: int = 0,
) -> list[int]:
    if not isinstance(origin, int):
        raise AssemblerError(
            "origin must be an integer"
        )

    if not 0 <= origin <= 0xFFFFFFFF:
        raise AssemblerError(
            "origin must fit the 32-bit address space"
        )

    if origin & 0x3:
        raise AssemblerError(
            "origin must be 4-byte aligned"
        )

    labels: dict[str, int] = {}
    records: list[tuple[int, int, str]] = []

    pc = origin


    for line_no, raw_line in enumerate(
        source.splitlines(),
        start=1,
    ):
        text = _strip_comment(
            raw_line
        ).strip()

        if not text:
            continue


        if ":" in text:
            label_text, separator, remainder = text.partition(":")
            label = label_text.strip()

            if (
                not separator
                or not LABEL_RE.fullmatch(label)
            ):
                raise _error(
                    line_no,
                    f"invalid label syntax {label_text!r}",
                )

            if label in labels:
                raise _error(
                    line_no,
                    f"duplicate label {label!r}",
                )

            labels[label] = pc

            text = remainder.strip()

            if ":" in text:
                raise _error(
                    line_no,
                    "multiple labels on one source line "
                    "are not supported",
                )

            if not text:
                continue


        if pc > 0xFFFFFFFC:
            raise _error(
                line_no,
                "instruction address exceeds "
                "32-bit word-aligned space",
            )

        records.append(
            (
                line_no,
                pc,
                text,
            )
        )

        pc += 4


    return [
        _encode_instruction(
            text,
            line_no,
            instruction_pc,
            labels,
        )
        for line_no, instruction_pc, text in records
    ]


def format_words(
    words: list[int],
) -> str:
    return "".join(
        f"{word & 0xFFFFFFFF:08X}\n"
        for word in words
    )


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
            "Assemble Milestone-2 Jinix Jupiter "
            "assembly source."
        ),
    )

    parser.add_argument(
        "input",
        type=Path,
        help="assembly source file",
    )

    parser.add_argument(
        "-o",
        "--output",
        required=True,
        type=Path,
        help="flat eight-hex-digit-per-word output",
    )

    parser.add_argument(
        "--origin",
        type=_cli_int,
        default=0,
        help="byte origin used for label resolution",
    )

    args = parser.parse_args(argv)

    try:
        words = assemble(
            args.input.read_text(),
            origin=args.origin,
        )

        args.output.write_text(
            format_words(words)
        )

    except (AssemblerError, OSError) as exc:
        print(
            f"error: {exc}",
            file=sys.stderr,
        )

        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
