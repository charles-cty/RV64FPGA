"""Generate a deterministic structured-random RV64IMA core program and ISS trace."""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "iss"))

from rv64ima_iss import RV64IMAISS


def encode_i(opcode: int, rd: int, funct3: int, rs1: int, immediate: int) -> int:
    return ((immediate & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def encode_s(funct3: int, rs1: int, rs2: int, immediate: int) -> int:
    value = immediate & 0xFFF
    return ((value >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((value & 0x1F) << 7) | 0x23


def encode_atomic(operation: int, rd: int, rs1: int, rs2: int, word: bool = False) -> int:
    funct3 = 0x2 if word else 0x3
    return (operation << 27) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x2F


def generate_program(seed: int = 0x5256_3634, length: int = 96) -> list[int]:
    generator = random.Random(seed)
    program = [
        encode_i(0x13, 1, 0, 0, 0),
        encode_i(0x13, 2, 0, 0, 0x155),
        encode_i(0x13, 3, 0, 0, 5),
        encode_i(0x03, 7, 3, 1, 0),
        encode_atomic(0x02, 4, 1, 0),
        encode_atomic(0x03, 5, 1, 3),
        encode_atomic(0x00, 6, 1, 3),
        encode_i(0x03, 8, 3, 1, 0),
    ]
    if length <= len(program):
        return program[:length]
    registers = list(range(2, 32))
    operations = ("addi", "add", "sub", "xor", "or", "and", "sll", "srl", "sra", "slli", "srli", "srai", "store", "load", "mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu", "mulw", "divw", "divuw", "remw", "remuw")
    while len(program) < length:
        operation = generator.choice(operations)
        destination = generator.choice(registers)
        source = generator.choice(registers)
        if operation == "addi":
            program.append(encode_i(0x13, destination, 0, source, generator.randint(-2048, 2047)))
        elif operation in {"add", "sub", "xor", "or", "and", "sll", "srl", "sra"}:
            funct3 = {"add": 0, "sub": 0, "xor": 4, "or": 6, "and": 7, "sll": 1, "srl": 5, "sra": 5}[operation]
            funct7 = 0x20 if operation in {"sub", "sra"} else 0
            program.append(encode_r(funct7, generator.choice(registers), source, funct3, destination))
        elif operation in {"mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"}:
            funct3 = {"mul": 0, "mulh": 1, "mulhsu": 2, "mulhu": 3, "div": 4, "divu": 5, "rem": 6, "remu": 7}[operation]
            program.append(encode_r(1, generator.choice(registers), source, funct3, destination))
        elif operation in {"mulw", "divw", "divuw", "remw", "remuw"}:
            funct3 = {"mulw": 0, "divw": 4, "divuw": 5, "remw": 6, "remuw": 7}[operation]
            program.append((1 << 25) | (generator.choice(registers) << 20) | (source << 15) | (funct3 << 12) | (destination << 7) | 0x3B)
        elif operation in {"slli", "srli", "srai"}:
            funct3 = {"slli": 1, "srli": 5, "srai": 5}[operation]
            funct7 = 0x20 if operation == "srai" else 0
            immediate = (funct7 << 5) | generator.randrange(64)
            program.append(encode_i(0x13, destination, funct3, source, immediate))
        elif operation == "store":
            program.append(encode_s(3, 1, source, generator.randrange(16) * 8))
        else:
            program.append(encode_i(0x03, destination, 3, 1, generator.randrange(16) * 8))
    return program


def write_outputs(program: list[int], program_path: Path, trace_path: Path) -> None:
    iss = RV64IMAISS()
    trace: list[dict[str, int | str | None]] = []
    for instruction in program:
        commit = iss.step(instruction)
        trace.append({
            "pc": f"0x{commit.pc:016x}",
            "instruction": f"0x{commit.instruction:08x}",
            "next_pc": f"0x{commit.next_pc:016x}",
            "rd": commit.rd,
            "rd_value": None if commit.rd_value is None else f"0x{commit.rd_value:016x}",
        })
    program_path.parent.mkdir(parents=True, exist_ok=True)
    trace_path.parent.mkdir(parents=True, exist_ok=True)
    program_path.write_text("\n".join(f"{instruction:08x}" for instruction in program) + "\n", encoding="ascii")
    trace_path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in trace) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("program", type=Path)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x5256_3634)
    parser.add_argument("--length", type=int, default=96)
    arguments = parser.parse_args()
    write_outputs(generate_program(arguments.seed, arguments.length), arguments.program, arguments.trace)
    print(f"RANDOM_PROGRAM_WRITTEN\t{arguments.program}\tseed=0x{arguments.seed:x}")
    print(f"ISS_TRACE_WRITTEN\t{arguments.trace}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
