"""Generate an independent Sv39 TLB invalidation and satp-switch trace."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import RV64IMAISS, sign_extend
from sv39 import Sv39Reference


MACHINE_PROGRAM = {
    0x000: 0x800000B7,
    0x004: 0x02009093,
    0x008: 0x00208093,
    0x00C: 0x18009073,
    0x010: 0x00100093,
    0x014: 0x00B09093,
    0x018: 0x30009073,
    0x01C: 0x10000093,
    0x020: 0x34109073,
    0x024: 0x30200073,
}

SUPERVISOR_PROGRAM = {
    0x100: 0x000021B7,
    0x104: 0x0001B203,
    0x108: 0x000032B7,
    0x10C: 0x00002337,
    0x110: 0x8C730313,
    0x114: 0x0062B823,
    0x118: 0x12018073,
    0x11C: 0x0001B383,
    0x120: 0x00800493,
    0x124: 0x03C49493,
    0x128: 0x00748493,
    0x12C: 0x18049073,
    0x130: 0x12000073,
    0x134: 0x0001B503,
    0x138: 0x0000006F,
}


def make_pte(ppn: int, flags: int) -> int:
    return (ppn << 10) | flags


class Sv39TlbSoCISS(RV64IMAISS):
    def __init__(self, memory: Sv39Reference) -> None:
        super().__init__()
        self.physical_memory = memory

    def _physical_address(self, address: int, access: str) -> int:
        return self.physical_memory.translate(
            address,
            access,
            self.privilege,
            self._read_csr(0x180),
            bool((self._read_csr(0x300) >> 18) & 1),
        )

    def _load(self, address: int, width: int, is_unsigned: bool) -> int:
        raw = self.physical_memory.read(self._physical_address(address, "load"), width)
        if is_unsigned:
            return raw
        return raw if width == 8 else sign_extend(raw, width * 8)

    def _store(self, address: int, value: int, width: int) -> None:
        self.physical_memory.write(self._physical_address(address, "store"), value, width)

    def step(self, instruction: int):
        if (instruction >> 25) == 0x09 and ((instruction >> 12) & 0x7) == 0:
            commit = super().step(0x10500073)
            return type(commit)(commit.pc, instruction, commit.next_pc, 0, None)
        return super().step(instruction)


def generate_trace(commit_count: int = 25) -> list[dict[str, int | str | None]]:
    physical_memory = Sv39Reference()
    physical_memory.write_u64(0x2000, make_pte(3, 0x01))
    physical_memory.write_u64(0x3000, make_pte(4, 0x01))
    physical_memory.write_u64(0x4000, make_pte(0, 0x49))
    physical_memory.write_u64(0x4010, make_pte(5, 0xC7))
    physical_memory.write_u64(0x4018, make_pte(4, 0xC7))
    physical_memory.write_u64(0x7000, make_pte(8, 0x01))
    physical_memory.write_u64(0x8000, make_pte(9, 0x01))
    physical_memory.write_u64(0x9000, make_pte(0, 0x49))
    physical_memory.write_u64(0x9010, make_pte(10, 0xC7))
    physical_memory.write_u64(0x5000, 0x1111_1111_1111_1111)
    physical_memory.write_u64(0x6000, 0x2222_2222_2222_2222)
    physical_memory.write_u64(0xA000, 0x3333_3333_3333_3333)

    iss = Sv39TlbSoCISS(physical_memory)
    trace: list[dict[str, int | str | None]] = []
    for _ in range(commit_count):
        if iss.privilege == 3:
            instruction = MACHINE_PROGRAM[iss.pc]
        else:
            iss._physical_address(iss.pc, "fetch")
            instruction = SUPERVISOR_PROGRAM[iss.pc]
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
