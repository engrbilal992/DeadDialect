#!/usr/bin/env python3
"""
ISA Register Rewriter — Phase 3 Milestone 2
Rewrites 5-bit register fields (rd, rs1, rs2) in RISC-V ELF .text section.

Frozen registers (never remapped):
  x0(zero), x1(ra), x2(sp), x10-x17(a0-a7) = 11 frozen, 21 shuffleable
  Entropy: 21! ≈ 2^65

POC Limitation: -march=rv64g required (no RVC compressed instructions).

Author: Muhammad Bilal
Usage: python3 isa_register_rewrite.py <input_elf> <output_elf> [--seed N] [--keyring PATH] [--quiet]
"""

import sys
import os
import struct
import random
import secrets
import argparse
import shutil
import subprocess

REG_COUNT  = 32
KEYRING_PATH = os.environ.get("REGISTER_KEYRING", "/etc/isa/register_keyring")

# Frozen registers — never remapped
# x0(zero)=0, x1(ra)=1, x2(sp)=2, x10-x17(a0-a7)=10-17
FROZEN = {0, 1, 2, 10, 11, 12, 13, 14, 15, 16, 17}
SHUFFLEABLE = [r for r in range(REG_COUNT) if r not in FROZEN]  # 21 registers

def generate_permutation(seed):
    """
    Generate deterministic register permutation from seed.
    Returns mapping: permuted_reg -> standard_reg (for QEMU reverse map).
    Only shuffleable registers are permuted. Frozen registers map to themselves.
    random.Random() accepts arbitrarily large ints in Python.
    """
    r = random.Random(seed)
    shuffled = SHUFFLEABLE[:]
    r.shuffle(shuffled)
    # perm[i] = where register i goes (standard -> permuted)
    perm = list(range(REG_COUNT))
    for std, perm_r in zip(SHUFFLEABLE, shuffled):
        perm[std] = perm_r
    return perm

def write_keyring(perm, path=KEYRING_PATH):
    """
    Write reverse map: permuted_reg standard_reg
    QEMU reads this to translate permuted -> standard at decode time.
    Uses sudo tee fallback for 640/600 root-owned files.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Reverse map: for each standard reg, find what it was permuted to
    reverse = list(range(REG_COUNT))
    for std in range(REG_COUNT):
        reverse[perm[std]] = std
    content = "".join(f"{permuted} {standard}\n"
                      for permuted, standard in enumerate(reverse)
                      if permuted != standard)
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

def remap_registers(data, text_start, text_end, perm, quiet=False):
    """
    Walk .text and remap rd, rs1, rs2 fields in every 32-bit instruction.
    Skips: compressed (16-bit), SYSTEM opcode (0x73), frozen registers.
    """
    count = 0
    i = text_start
    while i <= text_end - 4:
        word = struct.unpack_from("<I", data, i)[0]
        # Skip compressed instructions
        if (word & 0x3) != 0x3:
            i += 2
            continue
        opcode = word & 0x7F
        # Never touch SYSTEM (ecall/ebreak/csr)
        if opcode == 0x73:
            i += 4
            continue

        rd  = (word >> 7)  & 0x1F
        rs1 = (word >> 15) & 0x1F
        rs2 = (word >> 20) & 0x1F

        new_rd  = perm[rd]
        new_rs1 = perm[rs1]
        new_rs2 = perm[rs2]

        if new_rd == rd and new_rs1 == rs1 and new_rs2 == rs2:
            i += 4
            continue

        new_word = word
        new_word = (new_word & ~(0x1F <<  7)) | ((new_rd  & 0x1F) <<  7)
        new_word = (new_word & ~(0x1F << 15)) | ((new_rs1 & 0x1F) << 15)
        new_word = (new_word & ~(0x1F << 20)) | ((new_rs2 & 0x1F) << 20)

        struct.pack_into("<I", data, i, new_word)
        count += 1
        i += 4

    return count

def rewrite_binary(input_file, output_file, perm, quiet=False):
    shutil.copy(input_file, output_file)
    os.chmod(output_file, 0o755)
    with open(output_file, "rb") as f:
        data = bytearray(f.read())
    text_start, text_end = get_text_section_bounds(data)
    if not quiet:
        print(f"[REG] .text section: 0x{text_start:X} - 0x{text_end:X}")
    count = remap_registers(data, text_start, text_end, perm, quiet)
    with open(output_file, "wb") as f:
        f.write(data)
    if not quiet:
        print(f"[REG] Remapped {count} instructions -> {output_file}")
    return count

def print_mapping(perm, seed):
    print(f"\n  Register Mapping (seed={seed}):")
    print(f"  {'Standard':^12} {'Permuted':^12}")
    print(f"  {'-'*26}")
    for std in SHUFFLEABLE:
        p = perm[std]
        if p != std:
            print(f"  x{std:<10} -> x{p}")
    print(f"  Frozen: x0,x1,x2,x10-x17 (ABI registers)")
    print(f"  Shuffleable: {len(SHUFFLEABLE)} registers, entropy: 21! ≈ 2^65")

def main():
    parser = argparse.ArgumentParser(description="RISC-V Register Rewriter")
    parser.add_argument("input",  help="Input RISC-V ELF binary")
    parser.add_argument("output", help="Output rewritten binary")
    parser.add_argument("--seed",    type=int, default=None)
    parser.add_argument("--keyring", default=KEYRING_PATH)
    parser.add_argument("--quiet",   action="store_true")
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
        print(f"  RISC-V Register Rewriter — Phase 3 Milestone 2")
        print(f"{'='*60}")
        print(f"  Input  : {args.input}")
        print(f"  Output : {args.output}")
        print(f"  Seed   : {seed_display}")
        print(f"  Keyring: {args.keyring}")

    perm = generate_permutation(seed)

    if not args.quiet:
        print_mapping(perm, seed_display)

    write_keyring(perm, args.keyring)

    if not args.quiet:
        print(f"\n[REG] Keyring written -> {args.keyring}")

    count = rewrite_binary(args.input, args.output, perm, args.quiet)

    if not args.quiet:
        print(f"\n  Remapped {count} instruction(s)")
        print(f"{'='*60}\n")

if __name__ == "__main__":
    main()
