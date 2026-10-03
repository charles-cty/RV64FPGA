import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('tclsh'), 'tclsh required')
class ConsoleBridgeTests(unittest.TestCase):
    def run_bridge(self, mode='normal'):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            (root / 'input.bin').write_bytes(b'A\0\xffB')
            (root / 'heartbeat').write_text('1')
            script = r'''
set session [lindex $argv 0]
set mode [lindex $argv 1]
set bridge [lindex $argv 2]
set writes {}
set output {0 255 65}
set iteration 0
set attach 0
set result 0
proc set_msg_config {args} {}
proc open_hw_manager {} {}
proc connect_hw_server {args} {}
proc open_hw_target {} {}
proc get_hw_devices {args} {return dev}
proc current_hw_device {args} {}
proc set_property {args} {}
proc refresh_hw_device {args} {}
proc get_hw_axis {args} {return axi}
proc get_hw_axi_txns {name} {return $name}
proc close_hw_target {} {}
proc disconnect_hw_server {} {}
proc close_hw_manager {} {}
proc create_hw_axi_txn {name axi args} {
  global transactions
  set transactions($name) [dict create {*}$args]
}
proc delete_hw_axi_txn {name} {global transactions; unset transactions($name)}
proc get_property {args} {return OKAY}
proc run_hw_axi {name} {
  global transactions writes output iteration attach result mode
  set t $transactions($name)
  set addr [dict get $t -address]
  set write [expr {[dict get $t -type] eq "WRITE"}]
  if {$write} {
    set data [expr {0 + "0x[lindex [dict get $t -data] 0]"}]
    switch $addr {
      7ffffe14 {set attach $data}
      7ffffe0c {
        if {!$attach || $iteration == 0} {error "write without attachment/credit"}
        lappend writes $data
      }
      default {error "unexpected write to $addr (CPU/DDR must not be touched)"}
    }
  } else {
    switch $addr {
      7ffffe00 {set result [expr {$mode eq "old" ? 0 : 0x4a544331}]}
      7fffff00 {set result [expr {$mode eq "held" ? 3 : 6}]}
      7ffffe04 {set result [expr {$iteration == 0 ? 0 : 2}]}
      7ffffe08 {set result [llength $output]}
      7ffffe0c {
        if {![llength $output]} {error "empty TX pop"}
        set result [expr {0x80000000 | [lindex $output 0]}]
        set output [lrange $output 1 end]
      }
      7ffffe10 {set result 7}
      default {error "unexpected read $addr"}
    }
  }
}
proc report_hw_axi_txn {name args} {
  global result mode
  if {$mode eq "badreport" || ($mode eq "lateerror" && $::attach)} {return "invalid"}
  return [format "7ffffe00 %08x" $result]
}
rename after original_after
proc after {ms} {
  global iteration session
  incr iteration
  if {$iteration == 3} {set f [open [file join $session stop] w]; close $f}
}
set argv [list unused.ltx $session]
set argc 2
set status [catch {source $bridge} problem]
if {$status} {
  if {$attach != 0} {puts stderr "attachment leaked"; exit 2}
  puts stderr $problem
  exit 1
}
if {$writes ne {65 0 255 66} || $attach != 0} {error "input corruption or failed detach: $writes / $attach"}
puts MOCK_CONSOLE_PASS
'''
            mock = root / 'mock.tcl'
            mock.write_text(script)
            result = subprocess.run(['tclsh', str(mock), str(root), mode, str(ROOT / 'scripts/jtag-console.tcl')], capture_output=True, text=True)
            output = (root / 'output.bin').read_bytes() if (root / 'output.bin').exists() else b''
            return result, output

    def test_binary_duplex_credit_and_clean_detach(self):
        result, output = self.run_bridge()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(output, b'\0\xffA')
        self.assertIn('MOCK_CONSOLE_PASS', result.stdout)

    def test_old_bitstream_rejected(self):
        result, _ = self.run_bridge('old')
        self.assertEqual(result.returncode, 1)
        self.assertIn('JTC1 not found', result.stderr)

    def test_held_cpu_rejected_without_release(self):
        result, _ = self.run_bridge('held')
        self.assertEqual(result.returncode, 1)
        self.assertIn('CPU is held', result.stderr)

    def test_malformed_read_fails_closed(self):
        result, _ = self.run_bridge('badreport')
        self.assertEqual(result.returncode, 1)
        self.assertIn('invalid console read report', result.stderr)

    def test_error_after_attach_releases_backpressure(self):
        result, _ = self.run_bridge('lateerror')
        self.assertEqual(result.returncode, 1)
        self.assertIn('invalid console read report', result.stderr)
        self.assertNotIn('attachment leaked', result.stderr)


class TerminalInputTests(unittest.TestCase):
    def test_local_escape_and_binary_input(self):
        spec = importlib.util.spec_from_file_location('jtag_terminal', ROOT / 'tools/jtag_terminal.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.input_bytes(b'\0\xff\x03'), (b'\0\xff\x03', False))
        self.assertEqual(module.input_bytes(b'echo\x1dignored'), (b'echo', True))

    def test_smoke_does_not_accept_echo_or_partial_line(self):
        spec = importlib.util.spec_from_file_location('jtag_terminal', ROOT / 'tools/jtag_terminal.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        marker = b'JTAG_CONSOLE_123'
        self.assertFalse(module.has_marker(b'# echo ' + marker + b'\r\n', marker))
        self.assertFalse(module.has_marker(marker, marker))
        self.assertFalse(module.has_marker(marker + b'extra\n', marker))
        self.assertTrue(module.has_marker(b'# echo ' + marker + b'\r\n' + marker + b'\r\n# ', marker))
