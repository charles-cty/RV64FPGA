import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


class JtagLoaderScriptTest(unittest.TestCase):
    def test_loader_writes_verifies_captures_then_releases_cpu(self) -> None:
        tclsh = shutil.which("tclsh")
        if tclsh is None:
            self.skipTest("tclsh is unavailable")

        repository_root = Path(__file__).resolve().parents[1]
        loader_script = repository_root / "scripts" / "load-rv64-linux-jtag.tcl"
        mock_script = textwrap.dedent(
            r'''
            array set transactions {}
            array set memory {}
            array set read_result {}
            set workspace_reads 0
            set cpu_hold 1
            set loader_released 0
            set last_bresp OKAY
            set last_rresp OKAY
            set ila_armed 0
            set capture_uploaded 0
            set probes_configured 0
            set maximum_queue_depth 0
            set empty_capture [expr {[info exists ::env(MOCK_EMPTY_CAPTURE)] &&
                                     $::env(MOCK_EMPTY_CAPTURE) eq "1"}]

            proc open_hw_manager {} {}
            proc close_hw_manager {} {}
            proc connect_hw_server {args} {}
            proc disconnect_hw_server {} {}
            proc open_hw_target {} {}
            proc close_hw_target {} {}
            proc current_hw_device {args} {}
            proc refresh_hw_device {args} {}
            proc reset_hw_axi {args} {}
            proc reset_hw_ila {args} {}
            proc set_property {property value object} {
              global probes_configured
              if {$property eq "CONTROL.TRIGGER_MODE"} {
                error "CONTROL.TRIGGER_MODE is read-only"
              }
              if {$property eq "PROBES.FILE"} {
                set probes_configured 1
              }
            }
            proc get_hw_devices {args} { return {xc7k480t_0} }
            proc get_hw_axis {args} { return {hw_axi_0} }
            proc get_hw_ilas {args} { return {hw_ila_0} }
            proc get_hw_probes {args} {
              set filter_index [lsearch -exact $args -filter]
              if {$filter_index < 0 || [lindex $args [expr {$filter_index + 1}]] ne {NAME == "cpu_reset"}} {
                error "unexpected CPU reset ILA probe filter: $args"
              }
              return {cpu_reset}
            }
            proc after {milliseconds} {}
            proc wait_on_hw_ila {args} {}

            proc get_hw_axi_txns {args} { return $args }
            proc delete_hw_axi_txn {args} {}

            proc create_hw_axi_txn {name axi args} {
              global transactions
              array set options $args
              set transactions($name,address) [lindex [scan $options(-address) %x] 0]
              if {[info exists options(-data)]} {
                set transactions($name,data) $options(-data)
              } else {
                set transactions($name,data) {}
              }
              set transactions($name,length) $options(-len)
              set transactions($name,type) $options(-type)
            }

            proc run_hw_axi {args} {
              global transactions memory read_result cpu_hold loader_released last_bresp last_rresp maximum_queue_depth workspace_reads
              if {[lindex $args 0] eq "-queue"} {
                set args [lrange $args 1 end]
              }
              set queue_depth [llength $args]
              if {$queue_depth > 16} {
                error "mock write queue exceeds configured IP depth: $queue_depth"
              }
              if {$queue_depth > $maximum_queue_depth} {
                set maximum_queue_depth $queue_depth
              }
              foreach transaction $args {
                set address $transactions($transaction,address)
                set length $transactions($transaction,length)
                set type $transactions($transaction,type)
                if {$type eq "WRITE"} {
                  set word_index 0
                  foreach word $transactions($transaction,data) {
                    set word [string tolower $word]
                    set current_address [expr {$address + 4 * $word_index}]
                    if {$current_address == 0x7fffff00} {
                      if {$word eq "00000000"} {
                        if {$workspace_reads != 16384} {
                          error "DTB workspace was not fully verified before release"
                        }
                        set cpu_hold 0
                        set loader_released 1
                      }
                    } else {
                      set memory($current_address) $word
                    }
                    incr word_index
                  }
                  if {$word_index != $length} {
                    error "write transaction length mismatch"
                  }
                  set last_bresp OKAY
                } elseif {$type eq "READ"} {
                  set values {}
                  for {set word_index 0} {$word_index < $length} {incr word_index} {
                    set current_address [expr {$address + 4 * $word_index}]
                    if {$current_address == 0x7fffff00} {
                      set value [format %08x [expr {($loader_released << 2) | (1 << 1) | $cpu_hold}]]
                    } elseif {[info exists memory($current_address)]} {
                      set value $memory($current_address)
                      if {$current_address >= 0x90000000 && $current_address < 0x90010000} {
                        if {!$cpu_hold || $value ne "00000000"} {
                          error "invalid DTB workspace initialization"
                        }
                        if {$workspace_reads == 0} {
                          for {set boundary [expr {0x90000000}]} {$boundary < 0x90010000} {incr boundary 4} {
                            if {![info exists memory($boundary)]} {
                              error "DTB workspace read before complete initialization"
                            }
                          }
                        }
                        incr workspace_reads
                        if {[info exists ::env(MOCK_WORKSPACE_CORRUPTION)] &&
                            $current_address == 0x9000fffc} {
                          set value 00000001
                        }
                      }
                    } else {
                      set value 00000000
                    }
                    lappend values $value
                  }
                  set read_result($transaction) $values
                  set last_rresp OKAY
                } else {
                  error "unknown transaction type: $type"
                }
              }
            }

            proc get_property {property object} {
              global last_bresp last_rresp
              if {$property eq "STATUS.BRESP"} {
                return $last_bresp
              }
              if {$property eq "STATUS.RRESP"} {
                return $last_rresp
              }
              error "unexpected property: $property"
            }

            proc report_hw_axi_txn {transaction args} {
              global read_result transactions
              set address $transactions($transaction,address)
              set report "READ DATA is: [join $read_result($transaction) {}]"
              set index 0
              foreach value $read_result($transaction) {
                append report [format "\n%08x  %s " [expr {$address + 4 * $index}] $value]
                incr index
              }
              return $report
            }

            proc run_hw_ila {args} {
              global ila_armed
              set ila_armed 1
            }

            proc upload_hw_ila_data {args} {
              global cpu_hold ila_armed capture_uploaded probes_configured empty_capture
              if {!$probes_configured || !$ila_armed || $cpu_hold} {
                error "ILA capture was not armed before CPU release"
              }
              if {$empty_capture} {
                return {}
              }
              set capture_uploaded 1
              return capture_data
            }

            proc write_hw_ila_data {args} {
              global capture_uploaded
              if {!$capture_uploaded} {
                error "ILA data was not uploaded"
              }
              set csv_path [lindex $args end-1]
              set handle [open $csv_path wb]
              puts $handle "Sample in Buffer,cpu_reset"
              puts $handle "Radix - UNSIGNED,HEX"
              puts $handle "0,0"
              close $handle
            }

            set loader_script [lindex $argv 0]
            set payload_file [lindex $argv 1]
            set debug_probes_file [lindex $argv 2]
            set argc 3
            set argv [list $payload_file $debug_probes_file 3]
            source $loader_script
            if {!$probes_configured || $cpu_hold != 0 || !$loader_released || !$capture_uploaded ||
                $maximum_queue_depth != 1} {
              error "loader completion state is invalid"
            }
            puts "MOCK_JTAG_LOADER_PASS"
            '''
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            payload_file = temporary_path / "fw_payload.bin"
            payload_file.write_bytes(bytes(range(256)) * 65 + b"\x99")
            debug_probes_file = temporary_path / "rv64_mig_soc_top.ltx"
            debug_probes_file.write_text("debug probes", encoding="utf-8")
            mock_file = temporary_path / "mock_hardware.tcl"
            mock_file.write_text(mock_script, encoding="utf-8")

            result = subprocess.run(
                [
                    tclsh,
                    str(mock_file),
                    str(loader_script),
                    str(payload_file),
                    str(debug_probes_file),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("JTAG_DDR3_DIAGNOSTIC_PASS", result.stdout)
            self.assertIn("JTAG_DTB_WORKSPACE_INIT_PASS", result.stdout)
            self.assertIn("JTAG_PAYLOAD_WRITE_RATE", result.stdout)
            self.assertIn("JTAG_PAYLOAD_VERIFY_PASS", result.stdout)
            self.assertIn("JTAG_LINUX_LOAD_PASS", result.stdout)
            self.assertIn("MOCK_JTAG_LOADER_PASS", result.stdout)
            self.assertTrue((temporary_path / "rv64-linux-cpu-startup.csv").is_file())

            corrupt_environment = os.environ.copy()
            corrupt_environment["MOCK_WORKSPACE_CORRUPTION"] = "1"
            corrupt_result = subprocess.run(
                [tclsh, str(mock_file), str(loader_script), str(payload_file),
                 str(debug_probes_file)],
                check=False, capture_output=True, text=True, env=corrupt_environment,
            )
            self.assertNotEqual(corrupt_result.returncode, 0)
            self.assertIn("DTB workspace mismatch at 0x9000fc00",
                          corrupt_result.stdout + corrupt_result.stderr)
            self.assertNotIn("JTAG_DTB_WORKSPACE_INIT_PASS", corrupt_result.stdout)
            self.assertNotIn("JTAG_LINUX_LOAD_PASS", corrupt_result.stdout)

            empty_capture_environment = os.environ.copy()
            empty_capture_environment["MOCK_EMPTY_CAPTURE"] = "1"
            empty_result = subprocess.run(
                [
                    tclsh,
                    str(mock_file),
                    str(loader_script),
                    str(payload_file),
                    str(debug_probes_file),
                ],
                check=False,
                capture_output=True,
                text=True,
                env=empty_capture_environment,
            )

            self.assertNotEqual(empty_result.returncode, 0)
            self.assertIn(
                "CPU startup ILA did not produce a triggered capture",
                empty_result.stdout + empty_result.stderr,
            )
            self.assertNotIn("JTAG_LINUX_LOAD_PASS", empty_result.stdout)


if __name__ == "__main__":
    unittest.main()
