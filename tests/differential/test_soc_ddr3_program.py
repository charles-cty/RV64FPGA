from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "differential"))

from soc_ddr3_program import generate_trace


class SocDdr3ProgramTraceTest(unittest.TestCase):
    def test_program_constructs_platform_address_and_round_trips_ddr3_values(self) -> None:
        trace = generate_trace()

        self.assertEqual(len(trace), 16)
        self.assertEqual(trace[0]["rd_value"], "0xffffffff80000000")
        self.assertEqual(trace[2]["rd_value"], "0x0000000080000000")
        self.assertEqual(trace[5]["rd_value"], "0x0000000000000005")
        self.assertEqual(trace[6]["rd_value"], "0x0000000000000005")
        self.assertEqual(trace[9]["rd_value"], "0x000000000000000c")
        self.assertEqual(trace[12]["rd_value"], "0x0000000000000011")
        self.assertEqual(trace[13]["next_pc"], "0x000000000000003c")
        self.assertEqual(trace[14]["rd_value"], "0x000000000000002a")


if __name__ == "__main__":
    unittest.main()
