"""Generate the independent ISS trace for the rv64_core BRAM smoke program."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import RV64IMAISS


PROGRAM = {
    0: 0x00500093,
    1: 0x00700113,
    2: 0x002081B3,
    3: 0x00302023,
    4: 0x00002203,
    5: 0x00418463,
    6: 0x06300293,
    7: 0x0080006F,
    8: 0x04D00293,
    9: 0x02A00293,
}


def generate_trace(commit_count: int = 10) -> list[dict[str, int | str | None]]:
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
