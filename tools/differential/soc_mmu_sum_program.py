"""Generate independent Sv39 S-mode SUM permission commit traces."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import Commit
from soc_mmu_program import Sv39SoCISS, make_pte
from sv39 import PageFault, Sv39Reference


MACHINE_PROGRAM_SUM_OFF = {
    0x000: 0x800000B7,
    0x004: 0x02009093,
    0x008: 0x00108093,
    0x00C: 0x18009073,
    0x010: 0x04000093,
    0x014: 0x30509073,
    0x018: 0x00100093,
    0x01C: 0x00B09093,
    0x020: 0x30009073,
    0x024: 0x10000093,
    0x028: 0x34109073,
    0x02C: 0x30200073,
}
MACHINE_PROGRAM_SUM_ON = MACHINE_PROGRAM_SUM_OFF | {
    0x018: 0x000410B7,
    0x01C: 0x80008093,
}
SUPERVISOR_PROGRAM = {
    0x100: 0x000021B7,
    0x104: 0x0001B203,
}
DATA_VALUE = 0x1122_3344_5566_7788


def format_commit(commit: Commit, privilege: int) -> dict[str, int | str | None]:
    return {
        "pc": f"0x{commit.pc:016x}",
        "instruction": f"0x{commit.instruction:08x}",
        "next_pc": f"0x{commit.next_pc:016x}",
        "rd": commit.rd,
        "rd_value": None if commit.rd_value is None else f"0x{commit.rd_value:016x}",
        "trap_cause": None,
        "trap_value": None,
        "privilege": privilege,
    }


def generate_phase(machine_program: dict[int, int]) -> list[dict[str, int | str | None]]:
    physical_memory = Sv39Reference()
    physical_memory.write_u64(0x1000, make_pte(2, 0x01))
    physical_memory.write_u64(0x2000, make_pte(3, 0x01))
    physical_memory.write_u64(0x3000, make_pte(0, 0x4B))
    physical_memory.write_u64(0x3010, make_pte(4, 0xD7))
    physical_memory.write_u64(0x4000, DATA_VALUE)
    iss = Sv39SoCISS(physical_memory)
    trace: list[dict[str, int | str | None]] = []

    while len(trace) < 14:
        instruction: int | None = None
        try:
            if iss.privilege == 3:
                instruction = machine_program[iss.pc]
            else:
                iss._physical_address(iss.pc, "fetch")
                instruction = SUPERVISOR_PROGRAM[iss.pc]
            commit = iss.step(instruction)
        except PageFault as fault:
            trace.append(
                {
                    "pc": f"0x{iss.pc:016x}",
                    "instruction": None if instruction is None else f"0x{instruction:08x}",
                    "next_pc": "0x0000000000000040",
                    "rd": 0 if instruction is None else (instruction >> 7) & 0x1F,
                    "rd_value": None,
                    "trap_cause": f"0x{fault.cause:016x}",
                    "trap_value": f"0x{fault.address:016x}",
                    "privilege": 3,
                }
            )
            break
        trace.append(format_commit(commit, iss.privilege))

    return trace


def generate_sum_off_trace() -> list[dict[str, int | str | None]]:
    return generate_phase(MACHINE_PROGRAM_SUM_OFF)


def generate_sum_on_trace() -> list[dict[str, int | str | None]]:
    return generate_phase(MACHINE_PROGRAM_SUM_ON)


def generate_trace() -> list[dict[str, int | str | None]]:
    return generate_sum_off_trace() + generate_sum_on_trace()


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
