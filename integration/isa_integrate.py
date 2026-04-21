#!/usr/bin/env python3
"""
ISA Integration Rewriter — Phase 3 Milestone 3
Applies two remapping layers simultaneously:
  1. Register remapping + fingerprint (register_mapping.h)
  2. Syscall remapping                (syscall_mapping.h)

Rewrite order: registers first, syscalls second.
Both keyrings written atomically from same seed.

Author: Muhammad Bilal
Usage: python3 isa_integrate.py <input> <output> [--seed N] [--quiet]
"""

import sys, os, struct, random, secrets, hashlib, argparse, shutil, subprocess

_BASE = os.path.dirname(os.path.abspath(__file__))
_ENV  = os.path.join(_BASE, "isa.env")

def _load_env():
    cfg = {}
    with open(_ENV) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"): continue
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip()
    return cfg

_cfg = _load_env()
REGISTER_KEYRING = _cfg.get("REGISTER_KEYRING", "/etc/isa/register_keyring")
SYSCALL_KEYRING  = _cfg.get("SYSCALL_KEYRING",  "/etc/isa/syscall_keyring")

# ── Constants ────────────────────────────────────────────────────
REG_COUNT     = 32
SYSCALL_COUNT = 436
FROZEN        = {0, 1, 2, 10, 11, 12, 13, 14, 15, 16, 17}
SHUFFLEABLE   = [r for r in range(REG_COUNT) if r not in FROZEN]

# OPCODE_FIELDS: Curtis fix — only remap actual register fields
OPCODE_FIELDS = {
    0x33:(True,True,True),  0x3B:(True,True,True),
    0x2F:(True,True,True),  0x53:(True,True,True),
    0x43:(True,True,True),  0x47:(True,True,True),
    0x4B:(True,True,True),  0x4F:(True,True,True),
    0x13:(True,True,False), 0x1B:(True,True,False),
    0x03:(True,True,False), 0x67:(True,True,False),
    0x07:(True,True,False), 0x0F:(False,True,False),
    0x23:(False,True,True), 0x27:(False,True,True),
    0x63:(False,True,True),
    0x37:(True,False,False),0x17:(True,False,False),
    0x6F:(True,False,False),
    0x73:(False,False,False),
}

A7=17; X0=0; OP_IMM=0x13; OP_LUI=0x37; FUNCT3_ADDI=0
FP_MAGIC = 0x00013  # addi x0,x0,N fingerprint NOP

# ── ELF helper ───────────────────────────────────────────────────
def get_text_section(data):
    if len(data) < 64 or data[:4] != b'\x7fELF': return 0, len(data)
    e_shoff     = struct.unpack_from('<Q', data, 40)[0]
    e_shentsize = struct.unpack_from('<H', data, 58)[0]
    e_shnum     = struct.unpack_from('<H', data, 60)[0]
    e_shstrndx  = struct.unpack_from('<H', data, 62)[0]
    shstr_off      = e_shoff + e_shstrndx * e_shentsize
    shstr_file_off = struct.unpack_from('<Q', data, shstr_off + 24)[0]
    for i in range(e_shnum):
        sh_off      = e_shoff + i * e_shentsize
        sh_name     = struct.unpack_from('<I', data, sh_off)[0]
        sh_file_off = struct.unpack_from('<Q', data, sh_off + 24)[0]
        sh_size     = struct.unpack_from('<Q', data, sh_off + 32)[0]
        name = b''
        j = shstr_file_off + sh_name
        while j < len(data) and data[j] != 0:
            name += bytes([data[j]]); j += 1
        if name == b'.text':
            return sh_file_off, sh_file_off + sh_size
    return 0, len(data)

def _write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, 'w') as f: f.write(content)
    except PermissionError:
        r = subprocess.run(['sudo','tee',path],
                           input=content, text=True, capture_output=True)
        if r.returncode != 0:
            raise PermissionError(f"Cannot write {path}: {r.stderr}")

# ── Layer 1: Register permutation + fingerprint ──────────────────
def make_reg_perm(seed):
    r = random.Random(seed)
    shuffled = SHUFFLEABLE[:]
    r.shuffle(shuffled)
    perm = list(range(REG_COUNT))
    for std, p in zip(SHUFFLEABLE, shuffled):
        perm[std] = p
    return perm

def make_fingerprint(seed):
    h = hashlib.sha256(str(seed).encode()).digest()
    fp = int.from_bytes(h[:3], 'big') & 0xFFFFFF
    return fp, (fp >> 12) & 0xFFF, fp & 0xFFF

def encode_fp_nop(val):
    return ((val & 0xFFF) << 20) | FP_MAGIC

def write_register_keyring(reg_perm, seed, path=REGISTER_KEYRING):
    fp, hi12, lo12 = make_fingerprint(seed)
    reverse = list(range(REG_COUNT))
    for std in range(REG_COUNT):
        reverse[reg_perm[std]] = std
    lines = [f"FP {fp:06X}\n"]
    lines += [f"{p} {s}\n" for p,s in enumerate(reverse) if p != s]
    _write_file(path, "".join(lines))
    return fp

def rewrite_registers(data, text_start, text_end, reg_perm, seed):
    fp, hi12, lo12 = make_fingerprint(seed)
    # Embed fingerprint NOPs at .text+0
    struct.pack_into("<I", data, text_start,     encode_fp_nop(hi12))
    struct.pack_into("<I", data, text_start + 4, encode_fp_nop(lo12))
    count = 0
    i = text_start + 8  # skip fingerprint NOPs
    while i <= text_end - 4:
        word = struct.unpack_from("<I", data, i)[0]
        if (word & 0x3) != 0x3: i += 2; continue
        op = word & 0x7F
        if op not in OPCODE_FIELDS: i += 4; continue
        has_rd, has_rs1, has_rs2 = OPCODE_FIELDS[op]
        new_word = word; changed = False
        if has_rd:
            rd = (word >> 7) & 0x1F
            nr = reg_perm[rd]
            if nr != rd:
                new_word = (new_word & ~(0x1F<<7)) | (nr<<7); changed=True
        if has_rs1:
            rs1 = (word >> 15) & 0x1F
            nr  = reg_perm[rs1]
            if nr != rs1:
                new_word = (new_word & ~(0x1F<<15)) | (nr<<15); changed=True
        if has_rs2:
            rs2 = (word >> 20) & 0x1F
            nr  = reg_perm[rs2]
            if nr != rs2:
                new_word = (new_word & ~(0x1F<<20)) | (nr<<20); changed=True
        if changed:
            struct.pack_into("<I", data, i, new_word); count += 1
        i += 4
    return count, fp

# ── Layer 2: Syscall permutation ─────────────────────────────────
def make_syscall_perm(seed):
    r = random.Random(seed)
    perm = list(range(SYSCALL_COUNT))
    r.shuffle(perm)
    return perm

def write_syscall_keyring(syscall_perm, path=SYSCALL_KEYRING):
    lines = [f"{p} {s}\n" for s,p in enumerate(syscall_perm)]
    _write_file(path, "".join(lines))

def decode_i(word):
    imm = (word >> 20) & 0xFFF
    if imm & 0x800: imm -= 0x1000
    return word&0x7F,(word>>7)&0x1F,(word>>12)&0x7,(word>>15)&0x1F,imm

def decode_u(word):
    return word&0x7F,(word>>7)&0x1F,(word>>12)&0xFFFFF

def encode_i(op,rd,f3,rs1,imm):
    return ((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op

def encode_u(op,rd,imm):
    return ((imm&0xFFFFF)<<12)|(rd<<7)|op

def is_li_a7(word):
    if (word&3)!=3: return False,0
    op,rd,f3,rs1,imm = decode_i(word)
    return (op==OP_IMM and rd==A7 and f3==0 and rs1==X0), imm

def is_lui_a7(word):
    if (word&3)!=3: return False,0
    op,rd,imm = decode_u(word)
    return (op==OP_LUI and rd==A7), imm

def is_addi_a7_a7(word):
    if (word&3)!=3: return False,0
    op,rd,f3,rs1,imm = decode_i(word)
    return (op==OP_IMM and rd==A7 and f3==0 and rs1==A7), imm

def is_ecall(word):
    return (word&3)==3 and word==0x00000073

def rewrite_syscalls(data, text_start, text_end, syscall_perm, quiet=False):
    count = 0
    i = text_start
    while i < text_end - 3:
        word = struct.unpack_from("<I", data, i)[0]
        if (word&3)!=3: i+=2; continue
        matched, snum = is_li_a7(word)
        if matched and 0 <= snum < SYSCALL_COUNT:
            for j in range(1,9):
                noff = i+j*4
                if noff+4 > text_end: break
                nw = struct.unpack_from("<I",data,noff)[0]
                if is_ecall(nw):
                    struct.pack_into("<I",data,i,
                        encode_i(OP_IMM,A7,0,X0,syscall_perm[snum]))
                    count+=1; break
                m2,_ = is_li_a7(nw)
                if m2: break
            i+=4; continue
        ml, upper = is_lui_a7(word)
        if ml:
            for j in range(1,6):
                noff = i+j*4
                if noff+4>text_end: break
                nw = struct.unpack_from("<I",data,noff)[0]
                ma, lower = is_addi_a7_a7(nw)
                if ma:
                    snum=(upper<<12)+lower
                    if 0<=snum<SYSCALL_COUNT:
                        for k in range(1,9):
                            eo=noff+k*4
                            if eo+4>text_end: break
                            if is_ecall(struct.unpack_from("<I",data,eo)[0]):
                                nn=syscall_perm[snum]
                                nu=(nn>>12)&0xFFFFF; nl=nn&0xFFF
                                if nl&0x800: nu+=1
                                struct.pack_into("<I",data,i,encode_u(OP_LUI,A7,nu))
                                struct.pack_into("<I",data,noff,
                                    encode_i(OP_IMM,A7,0,A7,nl))
                                count+=1; break
                    break
                m2,_=is_lui_a7(nw)
                if m2: break
        i+=4
    return count

# ── Main rewriter ─────────────────────────────────────────────────
def rewrite_all(input_file, output_file, seed, quiet=False):
    shutil.copy(input_file, output_file)
    os.chmod(output_file, 0o755)
    with open(output_file, "rb") as f:
        data = bytearray(f.read())

    text_start, text_end = get_text_section(data)
    if not quiet:
        print(f"[INT] .text: 0x{text_start:X} - 0x{text_end:X}")

    reg_perm     = make_reg_perm(seed)
    syscall_perm = make_syscall_perm(seed)

    # Write both keyrings atomically
    fp = write_register_keyring(reg_perm, seed)
    write_syscall_keyring(syscall_perm)
    if not quiet:
        print(f"[INT] Keyrings written (FP=0x{fp:06X})")

    # Apply Layer 1: registers + fingerprint
    n_reg, fp = rewrite_registers(data, text_start, text_end, reg_perm, seed)

    # Apply Layer 2: syscalls
    n_sys = rewrite_syscalls(data, text_start, text_end, syscall_perm, quiet)

    with open(output_file, "wb") as f:
        f.write(data)

    if not quiet:
        print(f"[INT] Registers remapped: {n_reg}")
        print(f"[INT] Syscalls remapped : {n_sys}")
        print(f"[INT] Output: {output_file}")
    return n_reg, n_sys

def main():
    parser = argparse.ArgumentParser(
        description="RISC-V ISA Integration Rewriter — syscall + register")
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if args.seed is not None:
        seed = args.seed
        seed_display = str(seed)
    else:
        seed_bytes = secrets.token_bytes(32)
        seed = int.from_bytes(seed_bytes, 'big')
        seed_display = seed_bytes.hex()[:16] + "..."

    if not args.quiet:
        print(f"\n{'='*60}")
        print(f"  RISC-V ISA Integration Rewriter — Phase 3 Milestone 3")
        print(f"{'='*60}")
        print(f"  Input  : {args.input}")
        print(f"  Output : {args.output}")
        print(f"  Seed   : {seed_display}")
        print(f"  Layers : Register (21! ≈ 2^65) + Syscall (436! ≈ 2^3000+)")
        print(f"  Entropy: 21! × 436! ≈ 2^3065+")

    n_reg, n_sys = rewrite_all(args.input, args.output, seed, args.quiet)

    if not args.quiet:
        print(f"\n  Rewrote: {n_reg} registers, {n_sys} syscalls")
        print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
