from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "differential"))

from soc_cache_program import generate_trace


class SocCacheProgramTraceTest(unittest.TestCase):
    def test_program_has_expected_cacheable_memory_results(self) -> None:
        trace = generate_trace()

        self.assertEqual(len(trace), 12)
        self.assertEqual([record["pc"] for record in trace], [
            "0x0000000000000000",
            "0x0000000000000004",
            "0x0000000000000008",
            "0x000000000000000c",
            "0x0000000000000010",
            "0x0000000000000014",
            "0x0000000000000018",
            "0x000000000000001c",
            "0x0000000000000020",
            "0x0000000000000024",
            "0x0000000000000028",
            "0x0000000000000030",
        ])
        self.assertEqual(trace[2]["rd_value"], "0x0000000000000005")
        self.assertEqual(trace[3]["rd_value"], "0x0000000000000005")
        self.assertEqual(trace[6]["rd_value"], "0x000000000000000c")
        self.assertEqual(trace[9]["rd_value"], "0x0000000000000011")
        self.assertEqual(trace[11]["rd_value"], "0x000000000000002a")
        self.assertIsNone(trace[1]["rd_value"])
        self.assertIsNone(trace[5]["rd_value"])
        self.assertIsNone(trace[8]["rd_value"])


if __name__ == "__main__":
    unittest.main()
