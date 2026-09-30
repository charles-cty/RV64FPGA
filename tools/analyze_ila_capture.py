"""Decode hex Vivado RV64 commit captures without mistaking idle cycles for traps."""

from __future__ import annotations

import argparse
import bisect
import collections
import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Sample:
    index: int
    status: int
    pc: int
    instruction: int
    cause: int
    mode: int
    satp: int

    @property
    def committed(self) -> bool:
        return bool(self.status & (1 << 3))

    @property
    def trapped(self) -> bool:
        return bool(self.status & (1 << 4))


def decode_sample(row: dict[str, str]) -> Sample:
    trace = int(row["debug_commit_trace[225:0]"], 16)
    mask = (1 << 64) - 1
    return Sample(
        index=int(row["Sample in Buffer"]),
        status=int(row["debug_status[5:0]"], 16),
        pc=trace & mask,
        instruction=(trace >> 64) & 0xFFFFFFFF,
        cause=(trace >> 96) & mask,
        mode=(trace >> 160) & 3,
        satp=(trace >> 162) & mask,
    )


def read_capture(path: Path) -> list[Sample]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = csv.DictReader(stream)
        samples = []
        for row in rows:
            if row["Sample in Buffer"].startswith("Radix"):
                if row["debug_commit_trace[225:0]"] != "HEX":
                    raise ValueError("export the trace with HEX radix")
                continue
            samples.append(decode_sample(row))
    return samples


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--symbols", type=Path, help="System.map matching the payload")
    args = parser.parse_args()
    symbols = []
    if args.symbols:
        for line in args.symbols.read_text().splitlines():
            address, _, name = line.split()[:3]
            symbols.append((int(address, 16), name))
    symbols.sort()
    addresses = [address for address, _ in symbols]

    def label(pc: int) -> tuple[str, int]:
        index = bisect.bisect_right(addresses, pc) - 1
        if index < 0:
            return f"0x{pc:x}", 0
        address, name = symbols[index]
        return name, pc - address

    samples = read_capture(args.capture)
    commits = [sample for sample in samples if sample.committed]
    print(f"samples={len(samples)} commits={len(commits)} "
          f"trap_samples={sum(sample.trapped for sample in samples)}")
    if commits:
        gaps = [b.index - a.index for a, b in zip(commits, commits[1:])]
        print(f"max_inter_commit_samples={max(gaps, default=0)} "
              f"tail_samples={samples[-1].index - commits[-1].index}")
        print("functions:", dict(collections.Counter(label(s.pc)[0] for s in commits)))
    for sample in commits:
        name, offset = label(sample.pc)
        print(f"{sample.index:4d} pc={sample.pc:016x} insn={sample.instruction:08x} "
              f"mode={sample.mode} status={sample.status:02x} "
              f"trap={int(sample.trapped)} cause={sample.cause:016x} "
              f"satp={sample.satp:016x} {name}+0x{offset:x}")
    print("Mode is sampled live; on privilege transitions it may reflect the destination.")
    print("Cause is meaningful only when trap-valid is asserted.")


if __name__ == "__main__":
    main()
