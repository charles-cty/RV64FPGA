import unittest

from tools.differential.random_core_program import generate_program
from tools.iss.rv64ima_iss import IllegalInstruction, RV64IMAISS


class RandomCoreProgramTest(unittest.TestCase):
    def test_seed_is_reproducible_and_program_is_executable(self) -> None:
        first = generate_program()
        second = generate_program()
        self.assertEqual(first, second)
        self.assertEqual(len(first), 96)

        iss = RV64IMAISS()
        for instruction in first:
            try:
                iss.step(instruction)
            except IllegalInstruction as error:
                self.fail(f"generated instruction is illegal: {instruction:#010x}: {error}")

    def test_program_length_can_be_bounded(self) -> None:
        self.assertEqual(len(generate_program(seed=7, length=4)), 4)

    def test_multiple_seeds_remain_legal(self) -> None:
        for seed in range(16):
            iss = RV64IMAISS()
            for instruction in generate_program(seed=seed, length=32):
                try:
                    iss.step(instruction)
                except IllegalInstruction as error:
                    self.fail(f"seed {seed} generated an illegal instruction: {error}")


if __name__ == "__main__":
    unittest.main()
