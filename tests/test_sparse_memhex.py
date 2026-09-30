import unittest

from tools.build_sparse_memhex import build_sparse_image


class SparseMemhexTests(unittest.TestCase):
    def test_segments_emit_readmemh_addresses_and_little_endian_words(self) -> None:
        image = build_sparse_image([(0, b"\x93\x00\x70\x00"), (8, b"\x88\x77")], 4)
        self.assertEqual(image, "@0\n00700093\n@2\n00007788\n")

    def test_overlapping_segments_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            build_sparse_image([(0, b"12345678"), (4, b"abcd")], 4)


if __name__ == "__main__":
    unittest.main()
