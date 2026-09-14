from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "differential"))
sys.path.insert(0, str(ROOT / "tools" / "iss"))

from soc_mmu_fault_program import generate_fetch_trace, generate_load_trace, generate_store_trace
from soc_mmu_program import generate_trace, make_pte
from soc_mmu_sum_program import DATA_VALUE, generate_sum_off_trace, generate_sum_on_trace
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
        with self.assertRaises(PageFault) as context:
            self.memory.translate(0x2000, "fetch", 1, self.satp, False)

        self.assertEqual(context.exception.cause, 12)
        self.assertEqual(context.exception.address, 0x2000)


class SocMmuProgramTraceTest(unittest.TestCase):
    def test_program_has_expected_mret_and_supervisor_commits(self) -> None:
        trace = generate_trace()

        self.assertEqual(len(trace), 15)
        self.assertEqual(trace[9]["next_pc"], "0x0000000000000100")
        self.assertEqual(trace[10]["pc"], "0x0000000000000100")
        self.assertEqual(trace[13]["rd_value"], "0x0000000000000002")
        self.assertEqual(trace[14]["next_pc"], "0x0000000000000110")

    def test_execute_only_load_fault_trace_is_precise(self) -> None:
        trace = generate_load_trace()

        self.assertEqual(len(trace), 14)
        self.assertEqual(trace[-1]["pc"], "0x0000000000000104")
        self.assertEqual(trace[-1]["instruction"], "0x0001b203")
        self.assertEqual(trace[-1]["next_pc"], "0x0000000000000040")
        self.assertEqual(trace[-1]["trap_cause"], "0x000000000000000d")
        self.assertEqual(trace[-1]["trap_value"], "0x0000000000002000")
        self.assertEqual(trace[-1]["privilege"], 3)

    def test_execute_only_store_fault_trace_has_no_writeback(self) -> None:
        trace = generate_store_trace()

        self.assertEqual(len(trace), 15)
        self.assertEqual(trace[-1]["pc"], "0x0000000000000108")
        self.assertEqual(trace[-1]["instruction"], "0x0021b023")
        self.assertEqual(trace[-1]["next_pc"], "0x0000000000000040")
        self.assertEqual(trace[-1]["rd_value"], None)
        self.assertEqual(trace[-1]["trap_cause"], "0x000000000000000f")
        self.assertEqual(trace[-1]["trap_value"], "0x0000000000002000")
        self.assertEqual(trace[-1]["privilege"], 3)

    def test_invalid_supervisor_fetch_fault_has_no_instruction(self) -> None:
        trace = generate_fetch_trace()

        self.assertEqual(len(trace), 13)
        self.assertEqual(trace[-1]["pc"], "0x0000000000002000")
        self.assertIsNone(trace[-1]["instruction"])
        self.assertEqual(trace[-1]["next_pc"], "0x0000000000000040")
        self.assertEqual(trace[-1]["rd"], 0)
        self.assertEqual(trace[-1]["trap_cause"], "0x000000000000000c")
        self.assertEqual(trace[-1]["trap_value"], "0x0000000000002000")
        self.assertEqual(trace[-1]["privilege"], 3)

    def test_sum_controls_supervisor_loads_from_user_pages(self) -> None:
        sum_off_trace = generate_sum_off_trace()
        sum_on_trace = generate_sum_on_trace()

        self.assertEqual(len(sum_off_trace), 14)
        self.assertEqual(sum_off_trace[-1]["pc"], "0x0000000000000104")
        self.assertEqual(sum_off_trace[-1]["trap_cause"], "0x000000000000000d")
        self.assertEqual(sum_off_trace[-1]["trap_value"], "0x0000000000002000")
        self.assertEqual(sum_off_trace[-1]["privilege"], 3)
        self.assertEqual(len(sum_on_trace), 14)
        self.assertEqual(sum_on_trace[-1]["pc"], "0x0000000000000104")
        self.assertEqual(sum_on_trace[-1]["rd_value"], f"0x{DATA_VALUE:016x}")
        self.assertIsNone(sum_on_trace[-1]["trap_cause"])
        self.assertEqual(sum_on_trace[-1]["privilege"], 1)


if __name__ == "__main__":
    unittest.main()
