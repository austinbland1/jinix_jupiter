#!/usr/bin/env python3

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent

template_path = ROOT / "Template.sv"
system_path = ROOT / "rtl" / "jupiter_system.sv"
subsystem_path = ROOT / "rtl" / "jupiter_cpu_subsystem.sv"
audio_path = ROOT / "rtl" / "audio" / "jupiter_audio.sv"


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
audio = audio_path.read_text()


compact_template = re.sub(r"\s+", "", template)
compact_system = re.sub(r"\s+", "", system)
compact_subsystem = re.sub(r"\s+", "", subsystem)
compact_audio = re.sub(r"\s+", "", audio)


# ------------------------------------------------------------
# Template.sv must no longer hard-wire MiSTer audio to silence.
# ------------------------------------------------------------

check(
    re.search(
        r"assign\s+AUDIO_L\s*=",
        template,
    ) is None,
    "Template has no competing AUDIO_L continuous assignment",
)

check(
    re.search(
        r"assign\s+AUDIO_R\s*=",
        template,
    ) is None,
    "Template has no competing AUDIO_R continuous assignment",
)

check(
    re.search(
        r"assign\s+AUDIO_S\s*=",
        template,
    ) is None,
    "Template has no competing AUDIO_S continuous assignment",
)

check(
    re.search(
        r"assign\s+AUDIO_MIX\s*=",
        template,
    ) is None,
    "Template has no competing AUDIO_MIX continuous assignment",
)


# ------------------------------------------------------------
# Production jupiter_system instance drives all MiSTer ports.
# ------------------------------------------------------------

for port in [
    "AUDIO_L",
    "AUDIO_R",
    "AUDIO_S",
    "AUDIO_MIX",
]:
    check(
        compact_template.count(
            f".{port}({port})"
        ) == 1,
        f"Template connects jupiter_system {port} exactly once",
    )


# ------------------------------------------------------------
# jupiter_system owns the selected interface interpretation.
# ------------------------------------------------------------

check(
    "outputwiresigned[15:0]AUDIO_L" in compact_system,
    "jupiter_system exposes signed 16-bit AUDIO_L",
)

check(
    "outputwiresigned[15:0]AUDIO_R" in compact_system,
    "jupiter_system exposes signed 16-bit AUDIO_R",
)

check(
    "assignAUDIO_S=1'b1;" in compact_system,
    "jupiter_system selects signed MiSTer audio",
)

check(
    "assignAUDIO_MIX=2'b00;" in compact_system,
    "jupiter_system selects native stereo mode",
)

check(
    ".audio_l(AUDIO_L)" in compact_system,
    "jupiter_system receives left sample from CPU subsystem",
)

check(
    ".audio_r(AUDIO_R)" in compact_system,
    "jupiter_system receives right sample from CPU subsystem",
)


# ------------------------------------------------------------
# Lower hierarchy exposes the already-validated mixer registers.
# ------------------------------------------------------------

check(
    "outputwiresigned[15:0]audio_l" in compact_subsystem,
    "CPU subsystem exposes signed left PCM sample",
)

check(
    "outputwiresigned[15:0]audio_r" in compact_subsystem,
    "CPU subsystem exposes signed right PCM sample",
)

check(
    ".audio_l(audio_l)" in compact_subsystem,
    "CPU subsystem connects jupiter_audio left output",
)

check(
    ".audio_r(audio_r)" in compact_subsystem,
    "CPU subsystem connects jupiter_audio right output",
)

check(
    "outputwiresigned[15:0]audio_l" in compact_audio,
    "jupiter_audio exposes signed left mixer output",
)

check(
    "outputwiresigned[15:0]audio_r" in compact_audio,
    "jupiter_audio exposes signed right mixer output",
)

check(
    "assignaudio_l=output_l_reg;" in compact_audio,
    "left production output is the validated left mixer register",
)

check(
    "assignaudio_r=output_r_reg;" in compact_audio,
    "right production output is the validated right mixer register",
)


print()
print("==============================")


if failures == 0:

    print(
        f"RESULT: PASS  ({checks} checks)"
    )

    print("==============================")
    sys.exit(0)


print(
    f"RESULT: FAIL  ({failures} failures / {checks} checks)"
)

print("==============================")
sys.exit(1)
