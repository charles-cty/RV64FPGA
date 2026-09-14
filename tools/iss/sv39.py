"""Independent Sv39 translation reference used by SoC differential tests."""

from __future__ import annotations


class PageFault(ValueError):
    """Sv39 translation failure with the architectural access classification."""

    def __init__(self, access: str, address: int, reason: str) -> None:
        self.access = access
        self.address = address
        self.cause = {"fetch": 12, "load": 13, "store": 15}[access]
        super().__init__(reason)


class Sv39Reference:
    """Byte-addressed physical memory with Sv39 translation and permission checks."""

    def __init__(self) -> None:
        self.memory: dict[int, int] = {}

    def read(self, address: int, width: int) -> int:
        return sum(self.memory.get(address + offset, 0) << (offset * 8) for offset in range(width))

    def write(self, address: int, value: int, width: int) -> None:
        for offset in range(width):
            self.memory[address + offset] = (value >> (offset * 8)) & 0xFF

    def write_u64(self, address: int, value: int) -> None:
        self.write(address, value, 8)

    @staticmethod
    def _canonical(address: int) -> bool:
        sign_extension = (1 << 25) - 1 if (address >> 38) & 1 else 0
        return (address >> 39) == sign_extension

    def translate(self, address: int, access: str, privilege: int, satp: int, sum_enabled: bool) -> int:
        if privilege == 3 or (satp >> 60) == 0:
            return address
        if (satp >> 60) != 8 or not self._canonical(address):
            raise PageFault(access, address, f"invalid Sv39 translation request at {address:#x}")

        table_base = (satp & ((1 << 44) - 1)) << 12
        for level in range(2, -1, -1):
            vpn = (address >> (12 + level * 9)) & 0x1FF
            entry = self.read(table_base + vpn * 8, 8)
            valid, readable, writable, executable = tuple((entry >> bit) & 1 for bit in range(4))
            accessed, dirty, user = tuple((entry >> bit) & 1 for bit in (6, 7, 4))
            ppn = (entry >> 10) & ((1 << 44) - 1)
            if not valid or (not readable and writable):
                raise PageFault(access, address, f"invalid PTE at level {level}")
            if readable or executable:
                if not accessed or (access == "store" and not dirty):
                    raise PageFault(access, address, f"missing accessed or dirty PTE bit at level {level}")
                if privilege == 0:
                    privilege_ok = bool(user)
                elif privilege == 1:
                    privilege_ok = not user or (access != "fetch" and sum_enabled)
                else:
                    privilege_ok = True
                access_ok = {
                    "fetch": bool(executable),
                    "load": bool(readable),
                    "store": bool(writable),
                }.get(access, False)
                if not privilege_ok or not access_ok:
                    raise PageFault(access, address, f"permission denied at level {level}")
                if level == 2 and (ppn & ((1 << 18) - 1)):
                    raise PageFault(access, address, "misaligned 1 GiB leaf PTE")
                if level == 1 and (ppn & ((1 << 9) - 1)):
                    raise PageFault(access, address, "misaligned 2 MiB leaf PTE")
                if level == 2:
                    return ((ppn >> 18) << 30) | (address & ((1 << 30) - 1))
                if level == 1:
                    return ((ppn >> 9) << 21) | (address & ((1 << 21) - 1))
                return (ppn << 12) | (address & 0xFFF)
            if level == 0:
                raise PageFault(access, address, "non-leaf PTE at level zero")
            table_base = ppn << 12

        raise PageFault(access, address, "page table walk did not resolve")
