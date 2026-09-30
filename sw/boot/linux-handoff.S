.section .text
.globl _start
.type _start, @function
_start:
  add x4, x11, x0
  lw x5, 0(x11)
  lui x6, 0xedfe1
  addi x8, x0, 0x230
  sub x6, x6, x8
  bne x5, x6, 20
  lui x2, 0x10001
  addi x3, x10, 1
  sb x3, 0(x2)
loop:
  jal x0, 0
fail:
  lui x2, 0x10001
  addi x3, x0, 2
  sb x3, 0(x2)
  jal x0, -12
