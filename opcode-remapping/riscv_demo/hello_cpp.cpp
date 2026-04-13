// C++ program — tests that our remapper works on C++ binaries too
extern "C" void _start() {
    // C++ volatile variables
    volatile int x = 100;
    volatile int y = 200;
    volatile int z = x + y;  // 300

    // Exit via ecall
    register long a0 asm("a0") = 0;
    register long a7 asm("a7") = 93;
    asm volatile("ecall" : : "r"(a0), "r"(a7));
}
