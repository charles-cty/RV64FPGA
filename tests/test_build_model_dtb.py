import struct
import tempfile
import unittest
from pathlib import Path

from tools.build_model_dtb import FDT_MAGIC, FDT_VERSION
from tools.build_model_dtb import main as build_dtb_main


class ModelDtbTests(unittest.TestCase):
    def test_fdt_header_and_required_strings(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "model.dtb"
            arguments = ["build_model_dtb.py", str(output_path), "--memory-size", "0x30000000"]
            import sys

            original_arguments = sys.argv
            try:
                sys.argv = arguments
                build_dtb_main()
            finally:
                sys.argv = original_arguments

            image = output_path.read_bytes()
            header = struct.unpack(">10I", image[:40])
            self.assertEqual(header[0], FDT_MAGIC)
            self.assertEqual(header[5], FDT_VERSION)
            self.assertEqual(header[1], len(image))
            strings = image[header[3]:header[3] + header[8]]
            structure = image[header[2]:header[2] + header[9]]
            self.assertIn(b"memory@80000000\0", structure)
            self.assertIn(struct.pack(">I", 0x30000000), structure)
            for required_name in (
                b"compatible\0", b"interrupts-extended\0", b"clock-frequency\0",
                b"riscv,isa-base\0", b"riscv,isa-extensions\0",
            ):
                self.assertIn(required_name, strings)
            # Linux with ISA fallback disabled needs both the base and the
            # mandatory I/M/A extensions to accept the boot hart.
            self.assertIn(b"rv64i\0", structure)
            self.assertIn(b"i\0m\0a\0zicsr\0zifencei\0", structure)
            self.assertNotIn(b"riscv,isa\0", strings)


if __name__ == "__main__":
    unittest.main()
