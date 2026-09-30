#include <stdint.h>

static long sys_write(int fd, const void *buffer, unsigned long length) {
    register long a0 __asm__("a0") = fd;
    register const void *a1 __asm__("a1") = buffer;
    register unsigned long a2 __asm__("a2") = length;
    register long a7 __asm__("a7") = 64; /* __NR_write */
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7)
                      : "memory");
    return a0;
}

void main(void) {
    static const char banner[] = "RV64FPGA userspace direct init\r\n";
    (void)sys_write(1, banner, sizeof(banner) - 1);
    for (;;) {
        static const char alive[] = "RV64FPGA userspace alive\r\n";
        (void)sys_write(1, alive, sizeof(alive) - 1);
        for (volatile uint64_t delay = 0; delay < 5000000ULL; ++delay) {
        }
    }
}
