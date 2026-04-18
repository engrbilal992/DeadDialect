#ifndef REGISTER_MAPPING_H
#define REGISTER_MAPPING_H
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>

#ifndef REGISTER_KEYRING_PATH
#define REGISTER_KEYRING_PATH "/etc/isa/register_keyring"
#endif

#define REG_COUNT 32

/* Frozen registers — never remapped */
/* x0(zero), x1(ra), x2(sp), x10-x17(a0-a7) = 11 frozen */
static const int reg_frozen[REG_COUNT] = {
    1,1,1,0,0,0,0,0,  /* x0-x7:  x0,x1,x2 frozen */
    0,0,1,1,1,1,1,1,  /* x8-x15: x10-x15 frozen  */
    1,1,0,0,0,0,0,0,  /* x16-x23: x16,x17 frozen */
    0,0,0,0,0,0,0,0   /* x24-x31: none frozen    */
};

static uint8_t reg_reverse_map[REG_COUNT];
static time_t  reg_map_mtime = 0;
/* No initialized flag — mtime starts at 0, no real file has mtime 0 */

static void register_mapping_reload(void)
{
    struct stat st;
    if (stat(REGISTER_KEYRING_PATH, &st) != 0) return;
    if (st.st_mtime == reg_map_mtime) return;

    /* Identity map by default */
    for (int i = 0; i < REG_COUNT; i++)
        reg_reverse_map[i] = (uint8_t)i;

    FILE *f = fopen(REGISTER_KEYRING_PATH, "r");
    if (!f) return;

    int remapped, standard;
    while (fscanf(f, "%d %d", &remapped, &standard) == 2) {
        if (remapped  >= 0 && remapped  < REG_COUNT &&
            standard  >= 0 && standard  < REG_COUNT) {
            reg_reverse_map[remapped] = (uint8_t)standard;
        }
    }
    fclose(f);
    /* Update mtime only after successful read */
    reg_map_mtime = st.st_mtime;
}

static inline uint8_t reg_decode(uint8_t r)
{
    if (r >= REG_COUNT) return r;
    register_mapping_reload();
    return reg_reverse_map[r];
}

/* Decode a full 32-bit instruction — remap rd, rs1, rs2 fields */
static inline uint32_t register_decode_instruction(uint32_t insn)
{
    if ((insn & 0x3) != 0x3) return insn; /* skip compressed */
    register_mapping_reload();

    uint8_t opcode = insn & 0x7F;
    uint8_t rd  = (insn >> 7)  & 0x1F;
    uint8_t rs1 = (insn >> 15) & 0x1F;
    uint8_t rs2 = (insn >> 20) & 0x1F;

    /* SYSTEM (ecall/ebreak) — never touch */
    if (opcode == 0x73) return insn;

    uint8_t rd2  = reg_reverse_map[rd];
    uint8_t rs12 = reg_reverse_map[rs1];
    uint8_t rs22 = reg_reverse_map[rs2];

    insn = (insn & ~(0x1F <<  7)) | ((uint32_t)rd2  <<  7);
    insn = (insn & ~(0x1F << 15)) | ((uint32_t)rs12 << 15);
    insn = (insn & ~(0x1F << 20)) | ((uint32_t)rs22 << 20);

    return insn;
}

#endif /* REGISTER_MAPPING_H */
