# REG REMAP complex test
# First 2 instructions are placeholder NOPs for fingerprint.

.section .rodata
.align 3
msg1:
    .ascii "REG REMAP: complex test start\n"
msg2:
    .ascii "REG REMAP: complex test OK\n"

.section .text
.global _start
_start:
    # Placeholder NOPs — replaced by fingerprint
    addi    ra, ra, 0
    addi    ra, ra, 0
    # Real code
    lui     s0, %hi(msg1)
    addi    s0, s0, %lo(msg1)
    addi    s1, zero, 30
    lb      t0, 0(s0)
    addi    a0, zero, 1
    addi    a1, s0, 0
    addi    a2, s1, 0
    addi    a7, zero, 64
    ecall
    addi    s2, zero, 6
    addi    s3, zero, 7
    mul     s4, s2, s3
    lui     s0, %hi(msg2)
    addi    s0, s0, %lo(msg2)
    addi    s1, zero, 27
    lb      t0, 0(s0)
    addi    a0, zero, 1
    addi    a1, s0, 0
    addi    a2, s1, 0
    addi    a7, zero, 64
    ecall
    addi    a0, zero, 0
    addi    a7, zero, 93
    ecall
