#!/usr/bin/env python3
"""Build a sparse Verilog $readmemh image from binary segments."""

from __future__ import annotations

import argparse
from pathlib import Path


def build_sparse_image(segments: list[tuple[int, bytes]], word_bytes: int = 8) -> str:
    if word_bytes <= 0:
        raise ValueError("word_bytes must be positive")
    normalized = sorted(segments)
    previous_end = 0
    output: list[str] = []
    for offset, data in normalized:
        if offset < 0 or offset % word_bytes:
            raise ValueError("segment offsets must be non-negative and word-aligned")
        if not data:
            continue
        if offset < previous_end:
            raise ValueError("segments overlap")
        output.append(f"@{offset // word_bytes:x}")
        for start in range(0, len(data), word_bytes):
            word = data[start:start + word_bytes].ljust(word_bytes, b"\0")
            output.append(f"{int.from_bytes(word, 'little'):0{word_bytes * 2}x}")
        previous_end = offset + ((len(data) + word_bytes - 1) // word_bytes) * word_bytes
    return "\n".join(output) + ("\n" if output else "")


def parse_segment(value: str) -> tuple[int, Path]:
    try:
        offset, path = value.split("=", 1)
        return int(offset, 0), Path(path)
    except ValueError as error:
        raise argparse.ArgumentTypeError("segments must use OFFSET=PATH") from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("segments", nargs="+", type=parse_segment)
    parser.add_argument("--word-bytes", type=int, choices=(4, 8), default=8)
    arguments = parser.parse_args()
    image = build_sparse_image(
        [(offset, path.read_bytes()) for offset, path in arguments.segments],
        arguments.word_bytes,
    )
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(image, encoding="ascii")
    print(f"MEMHEX_IMAGE={arguments.output}")


if __name__ == "__main__":
    main()
