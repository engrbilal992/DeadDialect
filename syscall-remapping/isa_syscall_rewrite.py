#!/usr/bin/env python3
"""
ISA Syscall Rewriter — Phase 3 Milestone 1
Author: Muhammad Bilal
Usage: python3 isa_syscall_rewrite.py <input_elf> <output_elf> [--seed N] [--keyring PATH] [--quiet]
POC Limitation: static bare-metal binaries only.
"""

import sys
import os
import struct
import random
import secrets
import argparse
import shutil

SYSCALL_COUNT = 436
KEYRING_PATH  = os.environ.get("ISA_SYSCALL_KEYRING", "/etc/isa/syscall_keyring")
A7 = 17
X0 = 0
OP_IMM  = 0x13
OP_LUI  = 0x37
FUNCT3_ADDI = 0x0

def generate_permutation(seed):
    """
    Generate deterministic syscall number permutation from seed.
    random.Random() accepts arbitrarily large ints in Python —
    no need for a separate large-seed path.
    perm[standard] = permuted
    """
    r = random.Random(seed)
    perm = list(range(SYSCALL_COUNT))
    r.shuffle(perm)
    return perm

def write_keyring(perm, path=KEYRING_PATH):
    import subprocess
    os.makedirs(os.path.dirname(path), exist_ok=True)
    content = "".join(f"{permuted} {standard}\n" for standard, permuted in enumerate(perm))
    try:
        with open(path, "w") as f:
            f.write(content)
    except PermissionError:
        r = subprocess.run(["sudo", "tee", path],
                           input=content, text=True, capture_output=True)
        if r.returncode != 0:
            raise PermissionError(f"Cannot write keyring: {r.stderr}")

def get_text_section_bounds(data):
    if len(data) < 64 or data[:4] != b'\x7fELF':
        return 0, len(data)
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

def decode_i(word):
    opcode = word & 0x7F
    rd     = (word >> 7)  & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1    = (word >> 15) & 0x1F
    imm    = (word >> 20) & 0xFFF
    if imm & 0x800:
        imm -= 0x1000
    return opcode, rd, funct3, rs1, imm

def decode_u(word):
    opcode = word & 0x7F
    rd     = (word >> 7) & 0x1F
    imm    = (word >> 12) & 0xFFFFF
    return opcode, rd, imm

def encode_i(opcode, rd, funct3, rs1, imm):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_u(opcode, rd, imm):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode

def is_32bit(word):
    return (word & 0x3) == 0x3

def is_li_a7(word):
    if not is_32bit(word): return False, 0
    opcode, rd, funct3, rs1, imm = decode_i(word)
    if opcode == OP_IMM and rd == A7 and funct3 == FUNCT3_ADDI and rs1 == X0:
        return True, imm
    return False, 0

def is_lui_a7(word):
    if not is_32bit(word): return False, 0
    opcode, rd, imm = decode_u(word)
    if opcode == OP_LUI and rd == A7:
        return True, imm
    return False, 0

def is_addi_a7_a7(word):
    if not is_32bit(word): return False, 0
    opcode, rd, funct3, rs1, imm = decode_i(word)
    if opcode == OP_IMM and rd == A7 and funct3 == FUNCT3_ADDI and rs1 == A7:
        return True, imm
    return False, 0

def is_ecall(word):
    return is_32bit(word) and word == 0x00000073

def rewrite_binary(input_file, output_file, perm, quiet=False):
    shutil.copy(input_file, output_file)
    os.chmod(output_file, 0o755)
    with open(output_file, "rb") as f:
        data = bytearray(f.read())
    text_start, text_end = get_text_section_bounds(data)
    if not quiet:
        print(f"[SYSCALL] .text section: 0x{text_start:X} - 0x{text_end:X}")
    count = 0
    i = text_start
    while i < text_end - 3:
        word = struct.unpack_from("<I", data, i)[0]
        if not is_32bit(word):
            i += 2; continue
        matched, syscall_num = is_li_a7(word)
        if matched and 0 <= syscall_num < SYSCALL_COUNT:
            found_ecall = False
            for j in range(1, 9):
                next_off = i + j * 4
                if next_off + 4 > text_end: break
                next_word = struct.unpack_from("<I", data, next_off)[0]
                if is_ecall(next_word):
                    found_ecall = True; break
                m2, _ = is_li_a7(next_word)
                if m2: break
            if found_ecall:
                new_num = perm[syscall_num]
                new_word = encode_i(OP_IMM, A7, FUNCT3_ADDI, X0, new_num)
                struct.pack_into("<I", data, i, new_word)
                if not quiet:
                    print(f"[SYSCALL] Form1 @ 0x{i:X}: syscall {syscall_num} -> {new_num}")
                count += 1
            i += 4; continue
        matched_lui, upper_imm = is_lui_a7(word)
        if matched_lui:
            for j in range(1, 6):
                next_off = i + j * 4
                if next_off + 4 > text_end: break
                next_word = struct.unpack_from("<I", data, next_off)[0]
                matched_addi, lower_imm = is_addi_a7_a7(next_word)
                if matched_addi:
                    syscall_num = (upper_imm << 12) + lower_imm
                    if 0 <= syscall_num < SYSCALL_COUNT:
                        found_ecall = False
                        for k in range(1, 9):
                            ec_off = next_off + k * 4
                            if ec_off + 4 > text_end: break
                            ec_word = struct.unpack_from("<I", data, ec_off)[0]
                            if is_ecall(ec_word):
                                found_ecall = True; break
                        if found_ecall:
                            new_num = perm[syscall_num]
                            new_upper = (new_num >> 12) & 0xFFFFF
                            new_lower = new_num & 0xFFF
                            if new_lower & 0x800:
                                new_upper += 1
                            struct.pack_into("<I", data, i, encode_u(OP_LUI, A7, new_upper))
                            struct.pack_into("<I", data, next_off, encode_i(OP_IMM, A7, FUNCT3_ADDI, A7, new_lower))
                            if not quiet:
                                print(f"[SYSCALL] Form2 @ 0x{i:X}: syscall {syscall_num} -> {new_num}")
                            count += 1
                    break
                m_lui2, _ = is_lui_a7(next_word)
                if m_lui2: break
        i += 4
    with open(output_file, "wb") as f:
        f.write(data)
    if not quiet:
        print(f"[SYSCALL] Rewrote {count} syscall(s) -> {output_file}")
    return count

def main():
    parser = argparse.ArgumentParser(description="RISC-V Syscall Rewriter")
    parser.add_argument("input",   help="Input RISC-V ELF binary")
    parser.add_argument("output",  help="Output rewritten binary")
    parser.add_argument("--seed",  type=int, default=None, help="Fixed seed (random if not provided)")
    parser.add_argument("--keyring", default=KEYRING_PATH, help="Keyring output path")
    parser.add_argument("--quiet", action="store_true", help="Suppress output")
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
        print(f"  RISC-V Syscall Rewriter — Phase 3")
        print(f"{'='*60}")
        print(f"  Input  : {args.input}")
        print(f"  Output : {args.output}")
        print(f"  Seed   : {seed_display}")
        print(f"  Keyring: {args.keyring}")

    perm = generate_permutation(seed)
    write_keyring(perm, args.keyring)

    if not args.quiet:
        print(f"[SYSCALL] Keyring written -> {args.keyring}")

    count = rewrite_binary(args.input, args.output, perm, args.quiet)

    if not args.quiet:
        print(f"\n  Rewrote {count} syscall reference(s)")
        print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
