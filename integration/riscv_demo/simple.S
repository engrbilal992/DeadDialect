# REG REMAP simple test
# First 2 instructions are placeholder NOPs replaced by fingerprint at rewrite time.
# s0(x8) carries pointer, lb dereferences it — wrong mapping = crash.

.section .rodata
.align 3
msg:
    .ascii "REG REMAP: simple test OK\n"

.section .text
.global _start
_start:
    # Placeholder NOPs — replaced by fingerprint NOPs by rewriter
    addi    ra, ra, 0
    addi    ra, ra, 0
    # Real code starts here
    lui     s0, %hi(msg)
    addi    s0, s0, %lo(msg)
    addi    s1, zero, 26
    lb      t0, 0(s0)
    addi    a0, zero, 1
    addi    a1, s0, 0
    addi    a2, s1, 0
    addi    a7, zero, 64
    ecall
    addi    a0, zero, 0
    addi    a7, zero, 93
    ecall
