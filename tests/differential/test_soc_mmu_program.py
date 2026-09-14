from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "differential"))
sys.path.insert(0, str(ROOT / "tools" / "iss"))

from soc_mmu_program import generate_trace, make_pte
from sv39 import PageFault, Sv39Reference


class Sv39ReferenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.memory = Sv39Reference()
        self.memory.write_u64(0x1000, make_pte(2, 0x01))
        self.memory.write_u64(0x2000, make_pte(3, 0x01))
        self.memory.write_u64(0x3000, make_pte(0, 0x49))
        self.memory.write_u64(0x3010, make_pte(4, 0xC7))
        self.satp = 0x8000_0000_0000_0001

    def test_supervisor_fetch_and_data_translate_independently(self) -> None:
        self.assertEqual(self.memory.translate(0x100, "fetch", 1, self.satp, False), 0x100)
        self.assertEqual(self.memory.translate(0x2000, "load", 1, self.satp, False), 0x4000)
        self.assertEqual(self.memory.translate(0x2000, "store", 1, self.satp, False), 0x4000)

    def test_fetch_rejects_non_executable_data_page(self) -> None:
        with self.assertRaises(PageFault):
            self.memory.translate(0x2000, "fetch", 1, self.satp, False)


class SocMmuProgramTraceTest(unittest.TestCase):
    def test_program_has_expected_mret_and_supervisor_commits(self) -> None:
        trace = generate_trace()

        self.assertEqual(len(trace), 15)
        self.assertEqual(trace[9]["next_pc"], "0x0000000000000100")
        self.assertEqual(trace[10]["pc"], "0x0000000000000100")
        self.assertEqual(trace[13]["rd_value"], "0x0000000000000002")
        self.assertEqual(trace[14]["next_pc"], "0x0000000000000110")


if __name__ == "__main__":
    unittest.main()
