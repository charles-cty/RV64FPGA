"""Generate an independent ISS trace for the modelled DDR3 SoC program."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import RV64IMAISS


PROGRAM = {
    0: 0x80000537,
    1: 0x02051513,
    2: 0x02055513,
    3: 0x00500093,
    4: 0x00153023,
    5: 0x00053103,
    6: 0x00053183,
    7: 0x00708093,
    8: 0x00153423,
    9: 0x00853203,
    10: 0x004102B3,
    11: 0x00553823,
    12: 0x01053303,
    13: 0x00628463,
    14: 0x06300393,
    15: 0x02A00393,
    16: 0x0000006F,
}


def generate_trace(commit_count: int = 16) -> list[dict[str, int | str | None]]:
    iss = RV64IMAISS()
    trace: list[dict[str, int | str | None]] = []
    for _ in range(commit_count):
        instruction = PROGRAM.get(iss.pc // 4, 0x00000013)
        commit = iss.step(instruction)
        trace.append(
            {
                "pc": f"0x{commit.pc:016x}",
                "instruction": f"0x{commit.instruction:08x}",
                "next_pc": f"0x{commit.next_pc:016x}",
                "rd": commit.rd,
                "rd_value": None if commit.rd_value is None else f"0x{commit.rd_value:016x}",
            }
        )
    return trace


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("w", encoding="utf-8") as output:
        for record in generate_trace():
            output.write(json.dumps(record, separators=(",", ":")) + "\n")
    print(f"ISS_TRACE_WRITTEN\t{arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
