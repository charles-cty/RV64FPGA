import unittest

from tools.analyze_ila_capture import decode_sample


class CaptureDecodeTests(unittest.TestCase):
    def test_fields_and_status_bits(self):
        # Independently concatenate the RTL fields from most to least significant.
        fields = ((0x8000000000020481, 64), (1, 2),
                  (0x8000000000000005, 64), (0xC01026F3, 32),
                  (0xFFFFFFFF80C96DE0, 64))
        bits = "".join(f"{value:0{width}b}" for value, width in fields)
        row = {"Sample in Buffer": "37", "debug_status[5:0]": "0d",
               "debug_commit_trace[225:0]": f"{int(bits, 2):x}"}
        sample = decode_sample(row)
        self.assertEqual(sample.pc, fields[-1][0])
        self.assertEqual(sample.instruction, fields[-2][0])
        self.assertEqual(sample.cause, fields[-3][0])
        self.assertEqual(sample.mode, 1)
        self.assertEqual(sample.satp, fields[0][0])
        self.assertTrue(sample.committed)
        self.assertFalse(sample.trapped)
        for status, committed, trapped in (("05", False, False),
                                            ("1d", True, True),
                                            ("3d", True, True)):
            row["debug_status[5:0]"] = status
            sample = decode_sample(row)
            self.assertEqual(sample.committed, committed)
            self.assertEqual(sample.trapped, trapped)


if __name__ == "__main__":
    unittest.main()
