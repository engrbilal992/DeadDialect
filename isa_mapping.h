#ifndef ISA_MAPPING_H
#define ISA_MAPPING_H
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>

#ifndef ISA_MAP_PATH
#define ISA_MAP_PATH "/etc/isa/map"
#endif

static uint8_t isa_reverse_map[128];
static time_t isa_map_mtime = 0;

static void isa_mapping_reload(void)
{
    struct stat st;
    if (stat(ISA_MAP_PATH, &st) != 0) return;
    if (st.st_mtime == isa_map_mtime) return;

    for (int i = 0; i < 128; i++)
        isa_reverse_map[i] = (uint8_t)i;

    FILE *f = fopen(ISA_MAP_PATH, "r");
    if (!f) return;

    int remapped, standard;
    while (fscanf(f, "%d %d", &remapped, &standard) == 2) {
        if (remapped >= 0 && remapped < 128 &&
            standard >= 0 && standard < 128) {
            isa_reverse_map[remapped & 0x7F] = (uint8_t)standard;
        }
    }
    fclose(f);
    isa_map_mtime = st.st_mtime; /* update only after successful read */
}

static inline uint32_t isa_decode_instruction(uint32_t insn)
{
    if ((insn & 0x3) != 0x3) return insn;
    isa_mapping_reload();
    uint8_t opcode = insn & 0x7F;
    uint8_t std_opcode = isa_reverse_map[opcode];
    if (std_opcode != opcode)
        insn = (insn & ~0x7FU) | std_opcode;
    return insn;
}
#endif /* ISA_MAPPING_H */
