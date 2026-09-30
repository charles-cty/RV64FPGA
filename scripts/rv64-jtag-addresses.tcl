# Numeric helpers shared by the Linux DDR diagnostic readers. Windows Tcl's
# scan %x uses a signed 32-bit long; format %x also truncates to 32 bits.
namespace eval rv64_diag {
  proc words_value {words} {
    set value 0
    foreach word [lreverse $words] {
      if {![regexp {^[0-9a-fA-F]{8}$} $word]} {
        error "expected an eight-digit AXI word, got: $word"
      }
      set value [expr {($value << 32) | (0 + "0x$word")}]
    }
    return $value
  }

  proc hex64 {value} {
    return [format %016llx [expr {$value & 0xffffffffffffffff}]]
  }

  # These mappings belong to the archived Linux 6.12 diagnostic payload.
  proc kernel_pa {va} {
    if {$va < 0xffffffff80000000 || $va >= 0xffffffffa0000000} {
      error "address is outside the diagnostic kernel image mapping"
    }
    return [expr {$va - 0xffffffff80000000 + 0x80200000}]
  }

  proc linear_pa {va} {
    if {$va < 0xffffffd600000000 || $va >= 0xffffffd620000000} {
      error "address is outside the diagnostic 512 MiB linear mapping"
    }
    return [expr {$va - 0xffffffd600000000 + 0x80000000}]
  }
}
