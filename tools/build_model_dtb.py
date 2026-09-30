#!/usr/bin/env python3
"""Build the RV64FPGA model device tree without requiring dtc."""

from __future__ import annotations

import argparse
import struct
from dataclasses import dataclass, field
from pathlib import Path


FDT_MAGIC = 0xD00DFEED
FDT_VERSION = 17
FDT_LAST_COMP_VERSION = 16
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_END = 9


def cells(*values: int) -> bytes:
    return b"".join(struct.pack(">I", value & 0xFFFFFFFF) for value in values)


def string_value(value: str) -> bytes:
    return value.encode("ascii") + b"\0"


@dataclass
class DeviceTreeNode:
    name: str
    properties: list[tuple[str, bytes]] = field(default_factory=list)
    children: list["DeviceTreeNode"] = field(default_factory=list)


class DeviceTreeBuilder:
    def __init__(self) -> None:
        self.strings = bytearray()
        self.string_offsets: dict[str, int] = {}

    def string_offset(self, name: str) -> int:
        if name not in self.string_offsets:
            self.string_offsets[name] = len(self.strings)
            self.strings.extend(string_value(name))
        return self.string_offsets[name]

    def encode_node(self, node: DeviceTreeNode) -> bytes:
        structure = bytearray()
        structure.extend(cells(FDT_BEGIN_NODE))
        structure.extend(string_value(node.name))
        structure.extend(b"\0" * ((-len(structure)) % 4))
        for property_name, property_value in node.properties:
            structure.extend(cells(FDT_PROP, len(property_value),
                                   self.string_offset(property_name)))
            structure.extend(property_value)
            structure.extend(b"\0" * ((-len(structure)) % 4))
        for child in node.children:
            structure.extend(self.encode_node(child))
        structure.extend(cells(FDT_END_NODE))
        return bytes(structure)

    def build(self, root: DeviceTreeNode) -> bytes:
        structure = self.encode_node(root) + cells(FDT_END)
        reserve_map = cells(0, 0)
        header_size = 10 * 4
        off_mem_rsvmap = header_size
        off_dt_struct = off_mem_rsvmap + len(reserve_map)
        off_dt_strings = off_dt_struct + len(structure)
        totalsize = off_dt_strings + len(self.strings)
        header = struct.pack(
            ">10I",
            FDT_MAGIC,
            totalsize,
            off_dt_struct,
            off_dt_strings,
            off_mem_rsvmap,
            FDT_VERSION,
            FDT_LAST_COMP_VERSION,
            0,
            len(self.strings),
            len(structure),
        )
        return header + reserve_map + structure + bytes(self.strings)


def build_model_tree(memory_size: int) -> DeviceTreeNode:
    cpu_intc = DeviceTreeNode(
        "interrupt-controller",
        [
            ("compatible", string_value("riscv,cpu-intc")),
            ("#interrupt-cells", cells(1)),
            ("interrupt-controller", b""),
            ("phandle", cells(1)),
        ],
    )
    cpu = DeviceTreeNode(
        "cpu@0",
        [
            ("device_type", string_value("cpu")),
            ("compatible", string_value("riscv")),
            ("reg", cells(0)),
            ("status", string_value("okay")),
            ("riscv,isa-base", string_value("rv64i")),
            ("riscv,isa-extensions", b"i\0m\0a\0zicsr\0zifencei\0"),
            ("mmu-type", string_value("riscv,sv39")),
        ],
        [cpu_intc],
    )
    return DeviceTreeNode(
        "",
        [
            ("model", string_value("RV64FPGA xsim model")),
            ("compatible", string_value("rv64fpga,rv64ima")),
            ("#address-cells", cells(2)),
            ("#size-cells", cells(2)),
        ],
        [
            DeviceTreeNode(
                "chosen",
                [
                    ("stdout-path", string_value("/serial@10000000:115200")),
                    ("bootargs", string_value("console=ttyS0,115200 earlycon=sbi")),
                ],
            ),
            DeviceTreeNode(
                "memory@80000000",
                [
                    ("device_type", string_value("memory")),
                    ("reg", cells(0, 0x80000000, 0, memory_size)),
                ],
            ),
            DeviceTreeNode(
                "cpus",
                [("#address-cells", cells(1)), ("#size-cells", cells(0)),
                 ("timebase-frequency", cells(50_000_000))],
                [cpu],
            ),
            DeviceTreeNode(
                "clint@2000000",
                [
                    ("compatible", string_value("riscv,clint0")),
                    ("reg", cells(0, 0x02000000, 0, 0x10000)),
                    ("interrupts-extended", cells(1, 3, 1, 7)),
                ],
            ),
            DeviceTreeNode(
                "interrupt-controller@c000000",
                [
                    ("compatible", string_value("sifive,plic-1.0.0")),
                    ("reg", cells(0, 0x0C000000, 0, 0x00400000)),
                    ("#interrupt-cells", cells(1)),
                    ("interrupt-controller", b""),
                    ("interrupts-extended", cells(1, 11, 1, 9)),
                    ("riscv,max-priority", cells(7)),
                ],
            ),
            DeviceTreeNode(
                "serial@10000000",
                [
                    ("compatible", string_value("ns16550a")),
                    ("reg", cells(0, 0x10000000, 0, 0x1000)),
                    ("clock-frequency", cells(50_000_000)),
                    ("current-speed", cells(115200)),
                    ("reg-io-width", cells(1)),
                    ("reg-shift", cells(0)),
                    ("status", string_value("okay")),
                ],
            ),
        ],
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--memory-size", type=lambda value: int(value, 0),
                        default=0x20000000)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    if arguments.memory_size <= 0 or arguments.memory_size % 0x1000:
        raise SystemExit("--memory-size must be a positive 4 KiB multiple")
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_bytes(DeviceTreeBuilder().build(
        build_model_tree(arguments.memory_size)))
    print(f"DTB_IMAGE={arguments.output}")


if __name__ == "__main__":
    main()
