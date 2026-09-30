    .section .text.start
    .globl _start
    .type _start, @function
_start:
    call main
1:  j 1b
