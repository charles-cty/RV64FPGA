    .section .text.start
    .globl _start
    .type _start, @function
_start:
    /* write(1, message, message_end-message), then remain PID 1 forever. */
    li      a0, 1
    la      a1, message
    li      a2, 34
    li      a7, 64
    ecall
1:
    j       1b
    .align  2
message:
    .ascii  "RV64FPGA minimal userspace alive\r\n"
message_end:
