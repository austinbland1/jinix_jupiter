#!/usr/bin/env python3

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent

template_path = ROOT / "Template.sv"
system_path = ROOT / "rtl" / "jupiter_system.sv"
subsystem_path = ROOT / "rtl" / "jupiter_cpu_subsystem.sv"
hps_io_path = ROOT / "sys" / "hps_io.sv"


checks = 0
failures = 0


def check(condition, message):
    global checks, failures

    checks += 1

    if condition:
        print(f"PASS: {message}")
    else:
        failures += 1
        print(f"FAIL: {message}")


template = template_path.read_text()
system = system_path.read_text()
subsystem = subsystem_path.read_text()
hps_io = hps_io_path.read_text()

compact_template = re.sub(r"\s+", "", template)
compact_system = re.sub(r"\s+", "", system)
compact_subsystem = re.sub(r"\s+", "", subsystem)


# hps_io exposes all six selected digital words.
for index in range(6):

    check(
        re.search(
            rf"output\s+reg\s*\[31:0\]\s*joystick_{index}\b",
            hps_io,
        ) is not None,
        f"hps_io exposes 32-bit joystick_{index}",
    )


# Template declares and receives each word.
for index in range(6):

    check(
        re.search(
            rf"wire\s*\[31:0\]\s*joystick_{index}\s*;",
            template,
        ) is not None,
        f"Template declares joystick_{index}",
    )

    check(
        compact_template.count(
            f".joystick_{index}(joystick_{index})"
        ) == 1,
        f"Template connects hps_io joystick_{index} exactly once",
    )


# Template forwards each raw word to the matching Jupiter port.
for index in range(6):

    check(
        compact_template.count(
            f".controller_{index}_state(joystick_{index})"
        ) == 1,
        (
            f"Template forwards joystick_{index} to "
            f"controller_{index}_state exactly once"
        ),
    )


# jupiter_system forwards each matching input.
for index in range(6):

    check(
        (
            f"inputwire[31:0]controller_{index}_state"
            in compact_system
        ),
        f"jupiter_system exposes controller_{index}_state",
    )

    check(
        compact_system.count(
            f".controller_{index}_state(controller_{index}_state)"
        ) == 1,
        f"jupiter_system forwards controller_{index}_state exactly once",
    )

    check(
        (
            f".controller_{index}_state(32'h00000000)"
            not in compact_system
        ),
        f"controller {index} is no longer tied to zero",
    )


# Existing lower boundary remains intact.
for index in range(6):

    check(
        (
            f"inputwire[31:0]controller_{index}_state"
            in compact_subsystem
        ),
        f"CPU subsystem exposes controller_{index}_state",
    )

    check(
        compact_subsystem.count(
            f".controller_{index}_state(controller_{index}_state)"
        ) == 1,
        (
            f"CPU subsystem connects controller_{index}_state "
            "to controller peripheral"
        ),
    )


# Initial M8 remains digital-controller-only.
for unselected in [
    "joystick_l_analog",
    "joystick_r_analog",
    "paddle_0",
    "spinner_0",
]:

    check(
        re.search(
            rf"\.{unselected}\s*\(",
            template,
        ) is None,
        f"Template does not add unselected {unselected} wiring",
    )


print()
print("==============================")


if failures == 0:
    print(f"RESULT: PASS  ({checks} checks)")
    print("==============================")
    sys.exit(0)


print(
    f"RESULT: FAIL  ({failures} failures / {checks} checks)"
)

print("==============================")
sys.exit(1)
