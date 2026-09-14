import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "differential"))

from core_program import generate_trace


class CoreProgramTraceTest(unittest.TestCase):
    def test_program_has_expected_control_flow_and_memory_results(self) -> None:
        trace = generate_trace()

        self.assertEqual(len(trace), 10)
        self.assertEqual([record["pc"] for record in trace[:8]], [
            "0x0000000000000000",
            "0x0000000000000004",
            "0x0000000000000008",
            "0x000000000000000c",
            "0x0000000000000010",
            "0x0000000000000014",
            "0x000000000000001c",
            "0x0000000000000024",
        ])
        self.assertEqual(trace[4]["rd_value"], "0x000000000000000c")
        self.assertEqual(trace[7]["rd_value"], "0x000000000000002a")
        self.assertIsNone(trace[3]["rd_value"])

