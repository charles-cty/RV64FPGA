import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "iss"))

from rv64ima_iss import IllegalInstruction, MisalignedAddress, RV64IMAISS


def encode_r_type(rd: int, rs1: int, rs2: int, funct3: int, funct7: int, opcode: int = 0x33) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i_type(rd: int, rs1: int, immediate: int, funct3: int, opcode: int = 0x13) -> int:
    return ((immediate & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s_type(rs1: int, rs2: int, immediate: int, funct3: int) -> int:
    return (((immediate >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((immediate & 0x1F) << 7) | 0x23


class RV64IMAISSTest(unittest.TestCase):
    def test_x0_ignores_writes_and_commit_marks_no_writeback(self) -> None:
        iss = RV64IMAISS(start_pc=0x8000_0000)
        commit = iss.step(encode_i_type(rd=0, rs1=0, immediate=123, funct3=0))
        self.assertEqual(commit.pc, 0x8000_0000)
        self.assertEqual(commit.next_pc, 0x8000_0004)
        self.assertIsNone(commit.rd_value)
        self.assertEqual(iss.registers[0], 0)

    def test_addiw_sign_extends_its_32_bit_result(self) -> None:
        iss = RV64IMAISS()
        iss.registers[1] = 0x7fff_ffff
        commit = iss.step(encode_i_type(rd=2, rs1=1, immediate=1, funct3=0, opcode=0x1B))
        self.assertEqual(commit.rd_value, 0xffff_ffff_8000_0000)
        self.assertEqual(iss.registers[2], 0xffff_ffff_8000_0000)

    def test_slli_accepts_a_six_bit_shift_amount(self) -> None:
        iss = RV64IMAISS()
        iss.registers[1] = 1
        commit = iss.step(encode_i_type(rd=2, rs1=1, immediate=32, funct3=1))

        self.assertEqual(commit.rd_value, 1 << 32)
        self.assertEqual(iss.registers[2], 1 << 32)

    def test_signed_division_truncates_toward_zero(self) -> None:
        iss = RV64IMAISS()
        iss.registers[1] = (-7) & ((1 << 64) - 1)
        iss.registers[2] = 3
        iss.step(encode_r_type(rd=3, rs1=1, rs2=2, funct3=4, funct7=1))
        iss.step(encode_r_type(rd=4, rs1=1, rs2=2, funct3=6, funct7=1))
        self.assertEqual(iss.registers[3], (-2) & ((1 << 64) - 1))
        self.assertEqual(iss.registers[4], (-1) & ((1 << 64) - 1))

    def test_divw_by_zero_and_mulhsu_high_bit_operand(self) -> None:
        iss = RV64IMAISS()
        iss.registers[1] = 7
        iss.registers[2] = 0
        iss.step(encode_r_type(rd=3, rs1=1, rs2=2, funct3=4, funct7=1, opcode=0x3B))
        iss.registers[1] = (-1) & ((1 << 64) - 1)
        iss.registers[2] = (1 << 64) - 1
        iss.step(encode_r_type(rd=4, rs1=1, rs2=2, funct3=2, funct7=1))
        self.assertEqual(iss.registers[3], (1 << 64) - 1)
        self.assertEqual(iss.registers[4], (1 << 64) - 1)

    def test_op32_rejects_non_word_integer_operations(self) -> None:
        iss = RV64IMAISS()
        instruction = encode_r_type(rd=3, rs1=1, rs2=2, funct3=2, funct7=0, opcode=0x3B)

        with self.assertRaises(IllegalInstruction):
            iss.step(instruction)

    def test_misaligned_load_preserves_registers_and_program_counter(self) -> None:
        iss = RV64IMAISS(start_pc=0x100)
        iss.registers[1] = 1

        with self.assertRaises(MisalignedAddress) as context:
            iss.step(encode_i_type(rd=2, rs1=1, immediate=0, funct3=2, opcode=0x03))

        self.assertEqual(context.exception.cause, 4)
        self.assertEqual(context.exception.address, 1)
        self.assertEqual(iss.registers[2], 0)
        self.assertEqual(iss.pc, 0x100)

    def test_misaligned_store_preserves_memory_and_program_counter(self) -> None:
        iss = RV64IMAISS(start_pc=0x104)
        iss.registers[1] = 2
        iss.registers[2] = 0xdead_beef
        iss.memory[0] = 0x5a

        with self.assertRaises(MisalignedAddress) as context:
            iss.step(encode_s_type(rs1=1, rs2=2, immediate=0, funct3=2))

        self.assertEqual(context.exception.cause, 6)
        self.assertEqual(context.exception.address, 2)
        self.assertEqual(iss.memory, {0: 0x5A})
        self.assertEqual(iss.pc, 0x104)


if __name__ == "__main__":
    unittest.main()
