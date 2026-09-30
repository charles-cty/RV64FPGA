"""Acceptance must fail closed on absent markers, broken dumps, and panic traces."""
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from verify_linux_acceptance import MARKER, verify_printk, verify_runtime
from check_linux_baseline import check


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def dump(self, text):
        data = text.encode()
        data += b'\0' * (-len(data) % 4)
        path = self.root / 'words.txt'
        path.write_text('80000000 ' + ' '.join(f'{int.from_bytes(data[i:i+4], "little"):08x}' for i in range(0, len(data), 4)))
        return path

    def test_complete_selftest(self):
        self.assertIn(MARKER, verify_printk(self.dump(MARKER))[1])

    def test_entry_alone_is_not_acceptance(self):
        with self.assertRaises(ValueError):
            verify_printk(self.dump('Run /init as init process'))

    def test_panic_after_pass_is_failure(self):
        with self.assertRaises(ValueError):
            verify_printk(self.dump(MARKER + '\0Kernel panic - not syncing'))

    def test_truncated_or_discontinuous_dump(self):
        path = self.dump(MARKER)
        with path.open('a') as f:
            f.write('\n80010000 00000000\n')
        with self.assertRaises(ValueError):
            verify_printk(path)

    def capture(self, path, pc, mode=1, status=8):
        trace = (mode << 160) | pc
        path.write_text('Sample in Buffer,debug_commit_trace[225:0],debug_status[5:0]\n0,' + f'{trace:x},{status:x}\n')

    def test_runtime_requires_committed_user_and_nonpanic_progress(self):
        symbols = self.root / 'System.map'
        symbols.write_text('ffffffff80001000 T hrtimer_interrupt\nffffffff80002000 T panic\n')
        progress = self.root / 'progress'
        progress.mkdir()
        self.capture(self.root / 'user.csv', 0x10144, mode=0)
        for i in range(1, 4):
            self.capture(progress / f'current{i}.csv', 0xffffffff80001000)
        self.assertEqual(verify_runtime(self.root, symbols, 0x10144), ['hrtimer_interrupt'])
        self.capture(self.root / 'user.csv', 0x10144, mode=0, status=0)
        with self.assertRaises(ValueError):
            verify_runtime(self.root, symbols, 0x10144)
        self.capture(self.root / 'user.csv', 0x10144, mode=0)
        self.capture(progress / 'current3.csv', 0xffffffff80002000)
        with self.assertRaises(ValueError):
            verify_runtime(self.root, symbols, 0x10144)

    def test_source_drift_rejected(self):
        with self.assertRaises(ValueError):
            check({'source_sha256': {'rtl/rv64_core.sv': '0' * 64}})
