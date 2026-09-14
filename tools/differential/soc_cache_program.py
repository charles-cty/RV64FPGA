"""Generate an independent ISS trace for the cacheable BRAM SoC program."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import RV64IMAISS


PROGRAM = {
    0: 0x00500093,
    1: 0x00103023,
    2: 0x00003103,
    3: 0x00003183,
    4: 0x00708093,
    5: 0x00103423,
    6: 0x00803203,
    7: 0x004102B3,
    8: 0x00503823,
    9: 0x01003303,
    10: 0x00628463,
    11: 0x06300393,
    12: 0x02A00393,
}


def generate_trace(commit_count: int = 12) -> list[dict[str, int | str | None]]:
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
