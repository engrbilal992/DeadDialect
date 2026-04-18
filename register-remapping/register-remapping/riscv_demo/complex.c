/* Complex RISC-V test — arithmetic, loops, multiple registers */
static void write_str(const char *s) {
    int len = 0;
    while (s[len]) len++;
    register long a0 asm("a0") = 1;
    register long a1 asm("a1") = (long)s;
    register long a2 asm("a2") = len;
    register long a7 asm("a7") = 64;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
}

static int multiply(int a, int b) {
    int result = 0;
    for (int i = 0; i < b; i++)
        result += a;
    return result;
}

static int fibonacci(int n) {
    if (n <= 1) return n;
    int a = 0, b = 1, c;
    for (int i = 2; i <= n; i++) {
        c = a + b; a = b; b = c;
    }
    return b;
}

static void write_num(long n) {
    char buf[32];
    int i = 30;
    buf[31] = '\n';
    if (n == 0) { buf[i--] = '0'; }
    else { while (n > 0) { buf[i--] = '0' + (n % 10); n /= 10; } }
    register long a0 asm("a0") = 1;
    register long a1 asm("a1") = (long)(buf + i + 1);
    register long a2 asm("a2") = 30 - i + 1;
    register long a7 asm("a7") = 64;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
}

void _start(void) {
    write_str("REG REMAP: complex test start\n");
    write_str("multiply(6,7)="); write_num(multiply(6, 7));
    write_str("fibonacci(10)="); write_num(fibonacci(10));
    write_str("REG REMAP: complex test OK\n");
    register long a0 asm("a0") = 0;
    register long a7 asm("a7") = 93;
    asm volatile("ecall" :: "r"(a0), "r"(a7) : "memory");
}
