import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "differential"))

from compare_trace import TraceCommit, compare


class TraceComparisonTest(unittest.TestCase):
    def setUp(self) -> None:
        self.commit = TraceCommit(0x100, 0x13, 0x104, 1, 42)

    def test_equal_traces_pass(self) -> None:
        compare([self.commit], [self.commit])

    def test_first_mismatch_is_reported(self) -> None:
        actual = TraceCommit(0x100, 0x13, 0x104, 1, 43)
        with self.assertRaisesRegex(AssertionError, "commit 0"):
            compare([self.commit], [actual])

    def test_length_mismatch_is_reported(self) -> None:
        with self.assertRaisesRegex(AssertionError, "length mismatch"):
            compare([self.commit], [])

    def test_trap_fields_participate_in_comparison(self) -> None:
        expected = TraceCommit(0x104, 0x1B203, 0x40, 4, None, 13, 0x2000, 3)
        actual = TraceCommit(0x104, 0x1B203, 0x40, 4, None, 13, 0x2001, 3)

        with self.assertRaisesRegex(AssertionError, "commit 0"):
            compare([expected], [actual])

    def test_instruction_fetch_fault_can_omit_instruction(self) -> None:
        fetch_fault = TraceCommit(0x2000, None, 0x40, 0, None, 12, 0x2000, 3)

        compare([fetch_fault], [fetch_fault])
