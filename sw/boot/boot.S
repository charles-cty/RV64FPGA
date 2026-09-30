.section .text
.globl _start
.type _start, @function
_start:
  lui x5, 0x80000
  slli x5, x5, 32
  srli x5, x5, 32
  addi x10, x0, 0
  lui x11, 0x80010
  slli x11, x11, 32
  srli x11, x11, 32
  jalr x0, 0(x5)

.org 64
trap:
  jal x0, 0
