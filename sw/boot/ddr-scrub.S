/* Run before loading Linux. The host initializes the first 64 KiB, including
 * this program; the CPU initializes every remaining ECC word in 512 MiB DDR.
 * No stack, interrupts, loads from unwritten DDR, or external dependencies. */
#ifndef SCRUB_END
#define SCRUB_END 0xa0000000
#endif
.option norvc
.option norelax
.section .text
.globl _start, scrub_done, scrub_failed
_start:
  csrw mie, zero
  csrw mstatus, zero
  la t2, scrub_failed
  csrw mtvec, t2
  li t0, 0x80010000
  li t1, SCRUB_END
1:
  sd zero, 0(t0)
  addi t0, t0, 8
  bltu t0, t1, 1b
  fence rw, rw
  j scrub_done
.org 0x80
scrub_done:
  j scrub_done
.org 0x84
scrub_failed:
  j scrub_failed
