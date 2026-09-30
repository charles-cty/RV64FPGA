"""Convert a flat binary image into Verilog $readmemh words."""

from __future__ import annotations

import argparse
from pathlib import Path


def convert_binary(data: bytes, word_bytes: int, max_words: int | None = None) -> str:
    if word_bytes <= 0:
        raise ValueError("word_bytes must be positive")
    if max_words is not None and max_words <= 0:
        raise ValueError("max_words must be positive")
    word_count = (len(data) + word_bytes - 1) // word_bytes
    if max_words is not None and word_count > max_words:
        raise ValueError(f"image needs {word_count} words, limit is {max_words}")
    lines = []
    for offset in range(0, len(data), word_bytes):
        word = data[offset : offset + word_bytes].ljust(word_bytes, b"\0")
        lines.append(f"{int.from_bytes(word, 'little'):0{word_bytes * 2}x}")
    return "\n".join(lines) + ("\n" if lines else "")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--word-bytes", type=int, required=True, choices=(4, 8))
    parser.add_argument("--max-words", type=int)
    args = parser.parse_args()
    output = convert_binary(args.input.read_bytes(), args.word_bytes, args.max_words)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="ascii")


if __name__ == "__main__":
    main()
