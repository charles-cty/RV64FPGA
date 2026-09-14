"""Independent architectural model for the RV64 integer and M arithmetic subset."""

from __future__ import annotations

from dataclasses import dataclass

MASK_32 = (1 << 32) - 1
MASK_64 = (1 << 64) - 1


def unsigned(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def signed(value: int, width: int) -> int:
    value = unsigned(value, width)
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value


def sign_extend(value: int, width: int) -> int:
    return unsigned(signed(value, width), 64)


def truncating_dividend(dividend: int, divisor: int) -> int:
    quotient = abs(dividend) // abs(divisor)
    return -quotient if (dividend < 0) != (divisor < 0) else quotient


@dataclass(frozen=True)
class Commit:
    pc: int
    instruction: int
    next_pc: int
    rd: int
    rd_value: int | None


class IllegalInstruction(ValueError):
    pass


class RV64IMAISS:
    """Independent sequential model, expanded alongside the CPU commit interface."""

    def __init__(self, start_pc: int = 0) -> None:
        self.pc = unsigned(start_pc, 64)
        self.registers = [0] * 32
        self.memory: dict[int, int] = {}

    def _load(self, address: int, width: int, is_unsigned: bool) -> int:
        raw = sum(self.memory.get(address + offset, 0) << (offset * 8) for offset in range(width))
        return raw if is_unsigned else sign_extend(raw, width * 8)

    def _store(self, address: int, value: int, width: int) -> None:
        for offset in range(width):
            self.memory[address + offset] = (value >> (offset * 8)) & 0xFF

    @staticmethod
    def _branch_immediate(instruction: int) -> int:
        value = (((instruction >> 31) & 1) << 12) | (((instruction >> 7) & 1) << 11)
        value |= (((instruction >> 25) & 0x3F) << 5) | (((instruction >> 8) & 0xF) << 1)
        return signed(value, 13)

    @staticmethod
    def _jump_immediate(instruction: int) -> int:
        value = (((instruction >> 31) & 1) << 20) | (((instruction >> 12) & 0xFF) << 12)
        value |= (((instruction >> 20) & 1) << 11) | (((instruction >> 21) & 0x3FF) << 1)
        return signed(value, 21)

    def _read_register(self, index: int) -> int:
        return 0 if index == 0 else self.registers[index]

    def _write_register(self, index: int, value: int) -> int | None:
        if index == 0:
            return None
        result = unsigned(value, 64)
        self.registers[index] = result
        return result

    def step(self, instruction: int) -> Commit:
        instruction = unsigned(instruction, 32)
        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 0x7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        funct7 = (instruction >> 25) & 0x7F
        lhs = self._read_register(rs1)
        next_pc = unsigned(self.pc + 4, 64)
        write_value: int | None

        if opcode == 0x37:
            write_value = self._write_register(rd, sign_extend(instruction & 0xFFFFF000, 32))
        elif opcode == 0x17:
            write_value = self._write_register(rd, self.pc + sign_extend(instruction & 0xFFFFF000, 32))
        elif opcode == 0x6F:
            write_value = self._write_register(rd, self.pc + 4)
            next_pc = unsigned(self.pc + self._jump_immediate(instruction), 64)
        elif opcode == 0x67:
            if funct3 != 0:
                raise IllegalInstruction(f"unsupported JALR funct3: {instruction:#010x}")
            write_value = self._write_register(rd, self.pc + 4)
            next_pc = unsigned((lhs + signed(instruction >> 20, 12)) & ~1, 64)
        elif opcode == 0x63:
            if funct3 == 0:
                taken = lhs == self._read_register(rs2)
            elif funct3 == 1:
                taken = lhs != self._read_register(rs2)
            elif funct3 == 4:
                taken = signed(lhs, 64) < signed(self._read_register(rs2), 64)
            elif funct3 == 5:
                taken = signed(lhs, 64) >= signed(self._read_register(rs2), 64)
            elif funct3 == 6:
                taken = lhs < self._read_register(rs2)
            elif funct3 == 7:
                taken = lhs >= self._read_register(rs2)
            else:
                raise IllegalInstruction(f"unsupported branch funct3: {instruction:#010x}")
            if taken:
                next_pc = unsigned(self.pc + self._branch_immediate(instruction), 64)
            write_value = None
        elif opcode == 0x03:
            if funct3 not in (0, 1, 2, 3, 4, 5, 6):
                raise IllegalInstruction(f"unsupported load funct3: {instruction:#010x}")
            width = {0: 1, 1: 2, 2: 4, 3: 8, 4: 1, 5: 2, 6: 4}[funct3]
            write_value = self._write_register(rd, self._load(lhs + signed(instruction >> 20, 12), width, funct3 in (4, 5, 6)))
        elif opcode == 0x23:
            if funct3 not in (0, 1, 2, 3):
                raise IllegalInstruction(f"unsupported store funct3: {instruction:#010x}")
            immediate = signed(((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F), 12)
            self._store(lhs + immediate, self._read_register(rs2), {0: 1, 1: 2, 2: 4, 3: 8}[funct3])
            write_value = None
        elif opcode == 0x13:
            immediate = signed(instruction >> 20, 12)
            if funct3 == 0x0:
                write_value = self._write_register(rd, lhs + immediate)
            elif funct3 == 0x2:
                write_value = self._write_register(rd, int(signed(lhs, 64) < immediate))
            elif funct3 == 0x3:
                write_value = self._write_register(rd, int(lhs < unsigned(immediate, 64)))
            elif funct3 == 0x4:
                write_value = self._write_register(rd, lhs ^ unsigned(immediate, 64))
            elif funct3 == 0x6:
                write_value = self._write_register(rd, lhs | unsigned(immediate, 64))
            elif funct3 == 0x7:
                write_value = self._write_register(rd, lhs & unsigned(immediate, 64))
            elif funct3 == 0x1 and funct7 == 0x00:
                write_value = self._write_register(rd, lhs << ((instruction >> 20) & 0x3F))
            elif funct3 == 0x5 and funct7 == 0x00:
                write_value = self._write_register(rd, lhs >> ((instruction >> 20) & 0x3F))
            elif funct3 == 0x5 and funct7 == 0x20:
                write_value = self._write_register(rd, signed(lhs, 64) >> ((instruction >> 20) & 0x3F))
            else:
                raise IllegalInstruction(f"unsupported OP-IMM: {instruction:#010x}")
        elif opcode == 0x1B:
            immediate = signed(instruction >> 20, 12)
            if funct3 == 0x0:
                write_value = self._write_register(rd, sign_extend(lhs + immediate, 32))
            elif funct3 == 0x1 and funct7 == 0x00:
                write_value = self._write_register(rd, sign_extend(lhs << ((instruction >> 20) & 0x1F), 32))
            elif funct3 == 0x5 and funct7 == 0x00:
                write_value = self._write_register(rd, sign_extend((lhs & MASK_32) >> ((instruction >> 20) & 0x1F), 32))
            elif funct3 == 0x5 and funct7 == 0x20:
                write_value = self._write_register(rd, sign_extend(signed(lhs, 32) >> ((instruction >> 20) & 0x1F), 32))
            else:
                raise IllegalInstruction(f"unsupported OP-IMM-32: {instruction:#010x}")
        elif opcode in (0x33, 0x3B):
            rhs = self._read_register(rs2)
            write_value = self._execute_register(rd, funct3, funct7, lhs, rhs, 64 if opcode == 0x33 else 32)
        else:
            raise IllegalInstruction(f"unsupported opcode: {instruction:#010x}")

        commit = Commit(self.pc, instruction, next_pc, rd, write_value)
        self.pc = next_pc
        self.registers[0] = 0
        return commit

    def _execute_register(self, rd: int, funct3: int, funct7: int, lhs: int, rhs: int, width: int) -> int | None:
        mask = MASK_64 if width == 64 else MASK_32
        shift_mask = 0x3F if width == 64 else 0x1F
        lhs_u, rhs_u = lhs & mask, rhs & mask
        lhs_s, rhs_s = signed(lhs_u, width), signed(rhs_u, width)

        if funct7 == 0x00:
            if width == 32 and funct3 not in (0x0, 0x1, 0x5):
                raise IllegalInstruction("unsupported OP-32 funct3")
            operations = {
                0x0: lhs_u + rhs_u,
                0x1: lhs_u << (rhs_u & shift_mask),
                0x2: int(lhs_s < rhs_s),
                0x3: int(lhs_u < rhs_u),
                0x4: lhs_u ^ rhs_u,
                0x5: lhs_u >> (rhs_u & shift_mask),
                0x6: lhs_u | rhs_u,
                0x7: lhs_u & rhs_u,
            }
        elif funct7 == 0x20 and funct3 == 0x0:
            operations = {0x0: lhs_u - rhs_u}
        elif funct7 == 0x20 and funct3 == 0x5:
            operations = {0x5: lhs_s >> (rhs_u & shift_mask)}
        elif funct7 == 0x01:
            if width == 32 and funct3 not in (0x0, 0x4, 0x5, 0x6, 0x7):
                raise IllegalInstruction("unsupported M OP-32 funct3")
            operations = self._multiply_divide(funct3, lhs_u, rhs_u, lhs_s, rhs_s, width)
        else:
            raise IllegalInstruction("unsupported OP funct7")

        if funct3 not in operations:
            raise IllegalInstruction("unsupported OP funct3")
        value = operations[funct3]
        return self._write_register(rd, sign_extend(value, 32) if width == 32 else value)

    @staticmethod
    def _multiply_divide(funct3: int, lhs_u: int, rhs_u: int, lhs_s: int, rhs_s: int, width: int) -> dict[int, int]:
        mask = (1 << width) - 1
        signed_min = -(1 << (width - 1))
        if funct3 == 0x0:
            return {funct3: lhs_u * rhs_u}
        if width == 64:
            if funct3 == 0x1:
                return {funct3: (lhs_s * rhs_s) >> 64}
            if funct3 == 0x2:
                return {funct3: (lhs_s * rhs_u) >> 64}
            if funct3 == 0x3:
                return {funct3: (lhs_u * rhs_u) >> 64}
        if funct3 == 0x4:
            if rhs_u == 0:
                return {funct3: mask}
            if lhs_s == signed_min and rhs_s == -1:
                return {funct3: lhs_u}
            return {funct3: truncating_dividend(lhs_s, rhs_s)}
        if funct3 == 0x5:
            return {funct3: mask if rhs_u == 0 else lhs_u // rhs_u}
        if funct3 == 0x6:
            if rhs_u == 0:
                return {funct3: lhs_u}
            if lhs_s == signed_min and rhs_s == -1:
                return {funct3: 0}
            return {funct3: lhs_s - truncating_dividend(lhs_s, rhs_s) * rhs_s}
        if funct3 == 0x7:
            return {funct3: lhs_u if rhs_u == 0 else lhs_u % rhs_u}
        raise IllegalInstruction("unsupported M-extension funct3")
