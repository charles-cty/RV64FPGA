import unittest

from tools.bin_to_memhex import convert_binary


class BinToMemhexTests(unittest.TestCase):
    def test_little_endian_words_and_padding(self) -> None:
        self.assertEqual(
            convert_binary(bytes.fromhex("930070006f"), 4),
            "00700093\n0000006f\n",
        )

    def test_eight_byte_word(self) -> None:
        self.assertEqual(
            convert_binary(bytes.fromhex("8877665544332211"), 8),
            "1122334455667788\n",
        )

    def test_word_limit(self) -> None:
        with self.assertRaises(ValueError):
            convert_binary(b"\0" * 9, 8, 1)


if __name__ == "__main__":
    unittest.main()
