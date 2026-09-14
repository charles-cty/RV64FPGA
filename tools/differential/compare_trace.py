"""Compare architectural commit traces without depending on RTL internals."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TraceCommit:
    pc: int
    instruction: int
    next_pc: int
    rd: int
    rd_value: int | None
    trap_cause: int | None = None
    trap_value: int | None = None
    privilege: int | None = None

    @classmethod
    def from_json(cls, record: dict[str, object]) -> "TraceCommit":
        required = ("pc", "instruction", "next_pc", "rd", "rd_value")
        missing = [name for name in required if name not in record]
        if missing:
            raise ValueError(f"trace record is missing fields: {', '.join(missing)}")
        return cls(
            pc=int(record["pc"], 0) if isinstance(record["pc"], str) else int(record["pc"]),
            instruction=int(record["instruction"], 0) if isinstance(record["instruction"], str) else int(record["instruction"]),
            next_pc=int(record["next_pc"], 0) if isinstance(record["next_pc"], str) else int(record["next_pc"]),
            rd=int(record["rd"]),
            rd_value=None if record["rd_value"] is None else (int(record["rd_value"], 0) if isinstance(record["rd_value"], str) else int(record["rd_value"])),
            trap_cause=None if record.get("trap_cause") is None else (
                int(record["trap_cause"], 0) if isinstance(record["trap_cause"], str) else int(record["trap_cause"])
            ),
            trap_value=None if record.get("trap_value") is None else (
                int(record["trap_value"], 0) if isinstance(record["trap_value"], str) else int(record["trap_value"])
            ),
            privilege=None if record.get("privilege") is None else int(record["privilege"]),
        )


def read_trace(path: Path) -> list[TraceCommit]:
    commits: list[TraceCommit] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
            commits.append(TraceCommit.from_json(record))
        except (TypeError, ValueError, json.JSONDecodeError) as error:
            raise ValueError(f"{path}:{line_number}: invalid trace record: {error}") from error
    return commits


def compare(expected: list[TraceCommit], actual: list[TraceCommit]) -> None:
    shared_count = min(len(expected), len(actual))
    for index in range(shared_count):
        if expected[index] != actual[index]:
            raise AssertionError(
                f"trace mismatch at commit {index}: expected={expected[index]} actual={actual[index]}"
            )
    if len(expected) != len(actual):
        raise AssertionError(
            f"trace length mismatch: expected {len(expected)} commits, actual {len(actual)}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expected", type=Path)
    parser.add_argument("actual", type=Path)
    arguments = parser.parse_args()
    compare(read_trace(arguments.expected), read_trace(arguments.actual))
    print(f"DIFF PASS: {arguments.expected} == {arguments.actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
