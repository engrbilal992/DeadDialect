#ifndef REGISTER_MAPPING_H
#define REGISTER_MAPPING_H
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <signal.h>

#ifndef REGISTER_KEYRING_PATH
#define REGISTER_KEYRING_PATH "/etc/isa/register_keyring"
#endif

#define REG_COUNT 32

/*
 * Register remapping — Phase 3 Milestone 2
 *
 * Security model:
 *   1. Rewriter permutes register fields in binary AND embeds a 24-bit
 *      fingerprint (2 addi x0,x0,N NOPs) at the start of .text.
 *   2. Keyring first line: "FP XXXXXX" (24-bit hex fingerprint).
 *   3. QEMU hook: on first instruction decoded, reads fingerprint NOPs
 *      from binary, compares to keyring. Mismatch -> SIGILL -> blocked.
 *   4. Standard binary has no fingerprint -> fails verification.
 *   5. Wrong-seed binary has wrong fingerprint -> fails verification.
 *
 * No initialized flag — mtime=0 guarantees first load.
 */

static uint8_t  reg_reverse_map[REG_COUNT];
static time_t   reg_map_mtime  = 0;
static uint32_t reg_keyring_fp  = 0xFFFFFFFF; /* invalid until loaded */
static int      reg_fp_checked  = 0;          /* fingerprint decision made */
static uint32_t reg_fp_word0    = 0;          /* candidate first fp-nop */
static int      reg_got_word0   = 0;          /* waiting for second fp-nop */
static int      reg_insn_seen   = 0;          /* instructions seen while checking */

static void register_mapping_reload(void)
{
    struct stat st;
    if (stat(REGISTER_KEYRING_PATH, &st) != 0) return;
    if (st.st_mtime == reg_map_mtime) return;

    /* Reset */
    for (int i = 0; i < REG_COUNT; i++)
        reg_reverse_map[i] = (uint8_t)i;
    reg_keyring_fp = 0xFFFFFFFF;
    reg_fp_checked = 0;

    FILE *f = fopen(REGISTER_KEYRING_PATH, "r");
    if (!f) { reg_map_mtime = st.st_mtime; return; }

    char line[64];
    while (fgets(line, sizeof(line), f)) {
        /* First line: fingerprint "FP XXXXXX" */
        if (strncmp(line, "FP ", 3) == 0) {
            reg_keyring_fp = (uint32_t)strtol(line + 3, NULL, 16);
            continue;
        }
        int permuted, standard;
        if (sscanf(line, "%d %d", &permuted, &standard) == 2) {
            if (permuted >= 0 && permuted < REG_COUNT &&
                standard >= 0 && standard < REG_COUNT)
                reg_reverse_map[permuted] = (uint8_t)standard;
        }
    }
    fclose(f);
    reg_map_mtime = st.st_mtime;
}

/*
 * Check fingerprint NOPs at start of .text.
 * Binary must have: addi x0,x0,hi12 | addi x0,x0,lo12 at .text+0/+4.
 * Fingerprint = (hi12 << 12) | lo12, must match keyring FP line.
 * Returns 1 if OK, 0 if blocked.
 */
static inline int is_fp_nop(uint32_t word, int *val_out)
{
    /* addi x0, x0, N: bits[19:0] == 0x00013 */
    if ((word & 0xFFFFF) != 0x00013) return 0;
    int imm = (int)(word >> 20) & 0xFFF;
    if (imm & 0x800) imm -= 0x1000;
    *val_out = imm;
    return 1;
}

/*
 * OPCODE_FIELDS — only remap fields that are actual registers.
 * Curtis fix: S/B-type rd bits are immediate, U/J-type rs2 bits are immediate.
 */
typedef struct { uint8_t has_rd; uint8_t has_rs1; uint8_t has_rs2; } RegFields;

static inline RegFields reg_get_fields(uint8_t opcode)
{
    switch (opcode) {
        case 0x33: case 0x3B: case 0x2F:
        case 0x53: case 0x43: case 0x47: case 0x4B: case 0x4F:
            return (RegFields){1, 1, 1};
        case 0x13: case 0x1B: case 0x03: case 0x67: case 0x07:
            return (RegFields){1, 1, 0};
        case 0x0F:
            return (RegFields){0, 1, 0};
        case 0x23: case 0x27:
            return (RegFields){0, 1, 1};
        case 0x63:
            return (RegFields){0, 1, 1};
        case 0x37: case 0x17:
            return (RegFields){1, 0, 0};
        case 0x6F:
            return (RegFields){1, 0, 0};
        case 0x73:
            return (RegFields){0, 0, 0};
        default:
            return (RegFields){0, 0, 0};
    }
}


static inline uint32_t register_decode_instruction(uint32_t insn)
{
    if ((insn & 0x3) != 0x3) return insn;
    register_mapping_reload();

    /* Fingerprint verification:
     * - Binary compiled under a permutation has 2 fp-nop instructions
     *   at .text+0 encoding the 24-bit fingerprint.
     * - We detect the first consecutive pair of fp-nops seen.
     * - If keyring has FP line AND binary has fp-nops: FP must match.
     * - If keyring has FP line AND binary has NO fp-nops: BLOCK (standard binary).
     * - If keyring is empty (no FP line): pass everything through.
     *
     * reg_got_word0: waiting for second fp-nop after first
     * reg_fp_checked: fingerprint decision made — no more checks
     */
    if (!reg_fp_checked) { /* always scan — block fp-nop binaries without keyring too */
        reg_insn_seen++;
        int v0;
        if (!reg_got_word0) {
            if (is_fp_nop(insn, &v0)) {
                reg_fp_word0  = insn;
                reg_got_word0 = 1;
            } else if (reg_insn_seen >= 8) {
                /* No fp-nop pair in first 8 instructions */
                reg_fp_checked = 1;
                /* Only block if keyring is active */
                if (reg_keyring_fp != 0xFFFFFFFF) {
                    raise(SIGILL);
                }
            }
        } else {
            int v1;
            if (is_fp_nop(insn, &v1)) {
                /* Consecutive pair found — verify fingerprint */
                reg_fp_checked = 1;
                int vv0 = 0;
                is_fp_nop(reg_fp_word0, &vv0);
                uint32_t binary_fp = ((uint32_t)(vv0 & 0xFFF) << 12) |
                                      (uint32_t)(v1  & 0xFFF);
                if (reg_keyring_fp == 0xFFFFFFFF || binary_fp != reg_keyring_fp) {
                    raise(SIGILL);
                }
            } else {
                /* Not consecutive — reset */
                reg_got_word0 = 0;
                if (is_fp_nop(insn, &v1)) {
                    reg_fp_word0  = insn;
                    reg_got_word0 = 1;
                }
                if (reg_insn_seen >= 8) {
                    reg_fp_checked = 1;
                    if (reg_keyring_fp != 0xFFFFFFFF) {
                        raise(SIGILL);
                    }
                }
            }
        }
    }

    /* Apply reverse register map */
    uint8_t opcode = insn & 0x7F;
    RegFields f = reg_get_fields(opcode);
    if (!f.has_rd && !f.has_rs1 && !f.has_rs2) return insn;

    if (f.has_rd) {
        uint8_t rd = (insn >> 7) & 0x1F;
        insn = (insn & ~(0x1FU << 7)) | ((uint32_t)reg_reverse_map[rd] << 7);
    }
    if (f.has_rs1) {
        uint8_t rs1 = (insn >> 15) & 0x1F;
        insn = (insn & ~(0x1FU << 15)) | ((uint32_t)reg_reverse_map[rs1] << 15);
    }
    if (f.has_rs2) {
        uint8_t rs2 = (insn >> 20) & 0x1F;
        insn = (insn & ~(0x1FU << 20)) | ((uint32_t)reg_reverse_map[rs2] << 20);
    }
    return insn;
}

#endif /* REGISTER_MAPPING_H */
