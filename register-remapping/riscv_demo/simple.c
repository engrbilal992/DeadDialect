/* Simple RISC-V test — write + exit syscalls only */
static void write_str(const char *s) {
    int len = 0;
    while (s[len]) len++;
    register long a0 asm("a0") = 1;
    register long a1 asm("a1") = (long)s;
    register long a2 asm("a2") = len;
    register long a7 asm("a7") = 64;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
}
void _start(void) {
    write_str("REG REMAP: simple test OK\n");
    register long a0 asm("a0") = 0;
    register long a7 asm("a7") = 93;
    asm volatile("ecall" :: "r"(a0), "r"(a7) : "memory");
}
