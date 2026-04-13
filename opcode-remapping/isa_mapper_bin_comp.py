#!/usr/bin/env python3
"""
ISA Remapping Layer — Milestone 1
Dynamic RISC-V opcode remapper for boot-time ISA mutation.

Author: Muhammad Bilal
Project: RISC-V ISA Modification Emulator
"""

import random
import struct
import shutil
import os
import sys

# ─────────────────────────────────────────────
# Official RISC-V Base ISA 7-bit OpcodesS
# ─────────────────────────────────────────────
RISCV_OPCODES = {
    0x33: "OP        (ADD/SUB/AND/OR/XOR)",
    0x13: "OP-IMM    (ADDI/SLTI/XORI etc)",
    0x03: "LOAD      (LB/LH/LW/LD)",
    0x23: "STORE     (SB/SH/SW/SD)",
    0x63: "BRANCH    (BEQ/BNE/BLT/BGE)",
    0x6F: "JAL",
    0x67: "JALR",
    0x37: "LUI",
    0x17: "AUIPC",
    0x0F: "FENCE",
    0x3B: "OP-32     (ADDW/SUBW/SLLW)",
    0x1B: "OP-IMM-32 (ADDIW/SLLIW)",
}

# Never remap — required for OS syscalls and program exit
PROTECTED = {0x73}  # SYSTEM (ecall/ebreak/csrr)

QEMU_BINARY = os.path.expanduser(
    "~/Desktop/risc_v_isa_modification/qemu-8.2.0/build/qemu-riscv64"
)
REVERSE_MAP_FILE = "/tmp/isa_reverse_map"


def generate_mapping(seed: int) -> dict:
    """Generate deterministic opcode shuffle from seed."""
    opcodes = list(RISCV_OPCODES.keys())
    r = random.Random(seed)
    shuffled = opcodes[:]
    r.shuffle(shuffled)
    return dict(zip(opcodes, shuffled))


def write_reverse_map(mapping: dict, path: str = REVERSE_MAP_FILE):
    """
    Write reverse mapping file for QEMU to read.
    Format: remapped_opcode standard_opcode
    """
    with open(path, "w") as f:
        for orig, mapped in mapping.items():
            f.write(f"{mapped} {orig}\n")


def is_32bit(word: int) -> bool:
    """Per RISC-V spec: 32-bit instructions have bits[1:0] == 0b11."""
    return (word & 0x3) == 0x3


def remap_binary(input_file: str, output_file: str, seed: int) -> dict:
    """
    Read ELF binary, apply seed-based opcode remapping, write new binary.
    Returns the mapping used.
    """
    mapping = generate_mapping(seed)
    shutil.copy(input_file, output_file)
    os.chmod(output_file, 0o755)

    with open(output_file, "rb") as f:
        data = bytearray(f.read())

    remapped = 0
    skipped = 0
    i = 0

    while i < len(data) - 3:
        word = struct.unpack_from("<I", data, i)[0]

        if not is_32bit(word):
            i += 2
            skipped += 1
            continue

        opcode = word & 0x7F

        if opcode in PROTECTED:
            i += 4
            continue

        if opcode in mapping and mapping[opcode] != opcode:
            new_word = (word & ~0x7F) | mapping[opcode]
            struct.pack_into("<I", data, i, new_word)
            remapped += 1

        i += 4

    with open(output_file, "wb") as f:
        f.write(data)

    return mapping, remapped, skipped


def print_mapping(mapping: dict, seed: int, label: str):
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"  Seed: {seed}")
    print(f"{'='*60}")
    print(f"  {'Standard Opcode':<20} {'Remapped To':<20} Instruction Type")
    print(f"  {'-'*56}")
    for orig, mapped in mapping.items():
        changed = " *" if orig != mapped else ""
        print(f"  {hex(orig):<20} {hex(mapped):<20} "
              f"{RISCV_OPCODES[orig]}{changed}")
    print(f"\n  Protected (never remapped): "
          f"SYSTEM 0x73 (ecall/ebreak)")


def run_binary(binary: str, label: str) -> int:
    """Run binary with patched QEMU, return exit code."""
    ret = os.system(f"{QEMU_BINARY} {binary} 2>/dev/null")
    status = "SUCCESS ✓" if ret == 0 else "FAILED ✗"
    print(f"  {label}: {status} (exit {ret})")
    return ret


def main():
    src = "hello"
    bin_dir = "."

    if not os.path.exists(src):
        print(f"Error: '{src}' binary not found. Compile it first.")
        sys.exit(1)

    print("\n" + "█"*60)
    print("  RISC-V Dynamic ISA Remapping — Milestone 1 Demo")
    print("█"*60)

    # ── BOOT A ──────────────────────────────────────────────
    seed_A = 42
    mapping_A, remapped_A, skipped_A = remap_binary(
        src, f"{bin_dir}/hello_bootA", seed_A
    )
    print_mapping(mapping_A, seed_A, "BOOT A")
    print(f"\n  Stats: {remapped_A} instructions remapped, "
          f"{skipped_A} compressed skipped")

    write_reverse_map(mapping_A)
    print(f"\n  Reverse map written → {REVERSE_MAP_FILE}")

    print(f"\n  Running binaries under Boot A ISA mapping:")
    run_binary(f"{bin_dir}/hello_bootA", "Boot A binary  (remapped)")
    run_binary(f"{bin_dir}/hello",       "Original binary (standard)")

    # ── REBOOT → BOOT B ─────────────────────────────────────
    seed_B = 99
    mapping_B, remapped_B, skipped_B = remap_binary(
        src, f"{bin_dir}/hello_bootB", seed_B
    )
    print_mapping(mapping_B, seed_B, "REBOOT → BOOT B (new seed)")
    print(f"\n  Stats: {remapped_B} instructions remapped, "
          f"{skipped_B} compressed skipped")

    write_reverse_map(mapping_B)
    print(f"\n  Reverse map written → {REVERSE_MAP_FILE}")

    print(f"\n  Running Boot A binary under Boot B ISA mapping:")
    print(f"  (Simulating malware/old binary after reboot)")
    ret = os.system(
        f"{QEMU_BINARY} {bin_dir}/hello_bootA 2>/dev/null"
    )

    print(f"\n{'='*60}")
    if ret != 0:
        print("  RESULT: FAILED — Boot A binary cannot execute under")
        print("          Boot B mapping. ISA remapping works. ✓")
    else:
        print("  RESULT: Ran (seed collision — use different seeds)")
    print(f"{'='*60}\n")


def binary_comparison(orig_file: str, remapped_file: str, mapping: dict):
    """Show side-by-side binary comparison of original vs remapped."""
    with open(orig_file, 'rb') as f:
        orig = f.read()
    with open(remapped_file, 'rb') as f:
        remap = f.read()

    offset = 0x144  # .text section start
    names = {
        0x33:"OP (ADD/SUB)",   0x13:"OP-IMM (ADDI)",
        0x03:"LOAD",           0x23:"STORE",
        0x63:"BRANCH",         0x6F:"JAL",
        0x67:"JALR",           0x37:"LUI",
        0x17:"AUIPC",          0x0F:"FENCE",
        0x3B:"OP-32",          0x1B:"OP-IMM-32",
    }

    print("\n" + "█"*70)
    print("  BINARY COMPARISON: Original vs Remapped")
    print("  (showing first 20 x 32-bit words from .text section)")
    print("█"*70)
    print(f"  {'Original (standard RISC-V)':^34} {'Remapped (Boot A)':^34}")
    print(f"  {'-'*34} {'-'*34}")

    for i in range(20):
        o  = struct.unpack_from('<I', orig,  offset + i*4)[0]
        rm = struct.unpack_from('<I', remap, offset + i*4)[0]
        diff = "  <- opcode changed" if o != rm else ""
        print(f"  {o:032b}  {rm:032b}{diff}")

    print("\n" + "█"*70)
    print("  OPCODE MAPPING TABLE (seed=42)")
    print("█"*70)
    print(f"  {'Original':^24} {'Remapped To':^24} Type")
    print(f"  {'-'*65}")
    for orig_op, mapped_op in mapping.items():
        changed = " *" if orig_op != mapped_op else ""
        print(f"  {orig_op:08b} (0x{orig_op:02X})     "
              f"{mapped_op:08b} (0x{mapped_op:02X})     "
              f"{names.get(orig_op,'')}{changed}")
    print("\n  * = changed")
    print("  SYSTEM 0x73 protected — never remapped.")
    print("█"*70)


if __name__ == "__main__":
    main()
    # Binary comparison using Boot A mapping
    OPCODES = list(RISCV_OPCODES.keys())
    r = random.Random(42)
    s = OPCODES[:]
    r.shuffle(s)
    mapping_for_compare = dict(zip(OPCODES, s))
    binary_comparison("hello", "hello_bootA", mapping_for_compare)
