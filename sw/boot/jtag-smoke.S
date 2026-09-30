.section .text
.globl _start
.type _start, @function
_start:
  lui x5, 0x10000
  addi x6, x0, 74
  sb x6, 0(x5)
  lui x5, 0x10001
  addi x6, x0, 5
  sd x6, 0(x5)
1:
  jal x0, 1b
