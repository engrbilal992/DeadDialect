/*
 * isa_remap_ldso.h — musl ld.so ISA Remapping Patch
 * Hooks into musl dynlink.c to remap .text of every
 * dynamically loaded ELF AFTER mmap, BEFORE execution.
 * Author: Curtis Cole (architecture), Muhammad Bilal (integration)
 */
#ifndef ISA_REMAP_LDSO_H
#define ISA_REMAP_LDSO_H

#include <stdint.h>
#include <sys/mman.h>

#define ISA_LDSO_DEBUG    0
#define ISA_OPCODE_SYSTEM 0x73

static uint8_t isa_ldso_rmap[128];
static int     isa_ldso_initialized = 0;

static void isa_ldso_init(void)
{
    if (isa_ldso_initialized) return;
    for (int i = 0; i < 128; i++) isa_ldso_rmap[i] = (uint8_t)i;

    int fd = open("/etc/isa/map", O_RDONLY);
    if (fd < 0) { isa_ldso_initialized = 1; return; }

    char buf[4096];
    int n = read(fd, buf, sizeof(buf)-1);
    close(fd);
    if (n <= 0) { isa_ldso_initialized = 1; return; }
    buf[n] = '\0';

    char *p = buf;
    while (*p) {
        while (*p==' '||*p=='\t'||*p=='\n'||*p=='\r') p++;
        if (!*p) break;
        int remapped=0;
        while (*p>='0'&&*p<='9') { remapped=remapped*10+(*p-'0'); p++; }
        while (*p==' '||*p=='\t') p++;
        int standard=0;
        while (*p>='0'&&*p<='9') { standard=standard*10+(*p-'0'); p++; }
        if (remapped>=0&&remapped<128&&standard>=0&&standard<128)
            isa_ldso_rmap[remapped&0x7F]=(uint8_t)standard;
        while (*p&&*p!='\n') p++;
    }
    isa_ldso_initialized = 1;
}

static inline uint32_t isa_ldso_remap_insn(uint32_t insn)
{
    if ((insn&0x3)!=0x3) return insn;
    uint8_t opcode=insn&0x7F;
    uint8_t std=isa_ldso_rmap[opcode];
    if (std!=opcode) insn=(insn&~(uint32_t)0x7F)|std;
    return insn;
}

static int isa_ldso_remap_region(unsigned char *base, size_t len, int cur_prot)
{
    if (len<4) return 0;
    size_t page_size=PAGE_SIZE;
    uintptr_t page_start=(uintptr_t)base&~(page_size-1);
    uintptr_t page_end=((uintptr_t)base+len+page_size-1)&~(page_size-1);
    if (mprotect((void*)page_start,page_end-page_start,PROT_READ|PROT_WRITE)!=0)
        return -1;
    int count=0; size_t i=0;
    while (i+3<len) {
        uint32_t *ip=(uint32_t*)(base+i);
        uint32_t insn=*ip;
        if ((insn&0x3)!=0x3) { i+=2; continue; }
        uint32_t r=isa_ldso_remap_insn(insn);
        if (r!=insn) { *ip=r; count++; }
        i+=4;
    }
    mprotect((void*)page_start,page_end-page_start,cur_prot);
    __builtin___clear_cache((char*)base,(char*)(base+len));
    return count;
}

static void isa_ldso_remap_dso(unsigned char *base,
                                const Ehdr *eh,
                                const Phdr *phdr,
                                size_t phnum)
{
    isa_ldso_init();
    int has=0;
    for (int i=0;i<128;i++) if (isa_ldso_rmap[i]!=(uint8_t)i){has=1;break;}
    if (!has) return;
    for (size_t i=0;i<phnum;i++) {
        if (phdr[i].p_type!=PT_LOAD) continue;
        if (!(phdr[i].p_flags&PF_X)) continue;
        int prot=0;
        if (phdr[i].p_flags&PF_R) prot|=PROT_READ;
        if (phdr[i].p_flags&PF_W) prot|=PROT_WRITE;
        if (phdr[i].p_flags&PF_X) prot|=PROT_EXEC;
        isa_ldso_remap_region(base+phdr[i].p_vaddr,phdr[i].p_filesz,prot);
    }
}
#endif /* ISA_REMAP_LDSO_H */
