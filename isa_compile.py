#!/usr/bin/env python3
"""
ISA-Aware Compiler Wrapper — Milestone 2 & 3
Supports: C, C++, pre-compiled RISC-V binaries
Author: Muhammad Bilal
Usage: python3 isa_compile.py <source> <output> [seed]
"""

import sys
import os
import random
import struct
import subprocess
import shutil

# Auto-detect QEMU — works inside AppImage or standalone
_script_dir = os.path.dirname(os.path.abspath(__file__))
_candidates = [
    os.path.join(_script_dir, "../bin/qemu-riscv64"),
    os.path.join(_script_dir, "../phase1/qemu-8.2.0/build/qemu-riscv64"),
    os.environ.get("QEMU", ""),
]
QEMU = next((os.path.realpath(p) for p in _candidates if p and os.path.exists(p)), "qemu-riscv64")

REVERSE_MAP = os.environ.get("ISA_MAP", "/etc/isa/map")
OPCODES     = [0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
PROTECTED   = {0x73}
NAMES       = {
    0x33:"OP",    0x13:"OP-IMM", 0x03:"LOAD",
    0x23:"STORE", 0x63:"BRANCH", 0x6F:"JAL",
    0x67:"JALR",  0x37:"LUI",    0x17:"AUIPC",
    0x0F:"FENCE", 0x3B:"OP-32",  0x1B:"OP-IMM-32",
}

def generate_mapping(seed):
    r = random.Random(seed)
    s = OPCODES[:]
    r.shuffle(s)
    return dict(zip(OPCODES, s))

def write_reverse_map(mapping):
    os.makedirs(os.path.dirname(REVERSE_MAP), exist_ok=True)
    with open(REVERSE_MAP, "w") as f:
        for orig, mapped in mapping.items():
            f.write(f"{mapped} {orig}\n")

def compile_source(source, output_std):
    ext = os.path.splitext(source)[1].lower()
    if ext == '.c':
        compiler, lang = "clang", "C"
    elif ext in ['.cpp', '.cc', '.cxx']:
        compiler, lang = "clang++", "C++"
    else:
        with open(source, 'rb') as f:
            magic = f.read(4)
        if magic == b'\x7fELF':
            print(f"[BIN]  Pre-compiled RISC-V binary detected")
            print(f"[BIN]  Skipping compilation — using binary directly")
            shutil.copy(source, output_std)
            os.chmod(output_std, 0o755)
            print(f"[BIN]  Binary ready: {output_std}")
            return
        else:
            print(f"[ERROR] Unsupported file type: {ext}")
            sys.exit(1)

    print(f"[LLVM] Compiling {source} as {lang} with Clang (RISC-V target)...")
    cmd = [compiler, "--target=riscv64-linux-gnu",
           "-nostdlib", "-static", "-fuse-ld=lld", "-O1",
           "-o", output_std, source]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[ERROR] Compilation failed:\n{result.stderr}")
        sys.exit(1)
    print(f"[LLVM] Standard binary: {output_std}")

def get_text_section_bounds(data):
    if len(data) < 64 or data[:4] != b'\x7fELF':
        return 0, len(data)
    e_shoff        = struct.unpack_from('<Q', data, 40)[0]
    e_shentsize    = struct.unpack_from('<H', data, 58)[0]
    e_shnum        = struct.unpack_from('<H', data, 60)[0]
    e_shstrndx     = struct.unpack_from('<H', data, 62)[0]
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

def remap_binary(input_file, output_file, mapping):
    with open(input_file, "rb") as f:
        data = bytearray(f.read())
    text_start, text_end = get_text_section_bounds(data)
    print(f"[ISA]  .text section: 0x{text_start:X} - 0x{text_end:X}")
    count = 0
    i = text_start
    while i < text_end - 3:
        w = struct.unpack_from("<I", data, i)[0]
        if (w & 0x3) != 0x3:
            i += 2; continue
        op = w & 0x7F
        if op not in PROTECTED and op in mapping and mapping[op] != op:
            data[i:i+4] = struct.pack("<I", (w & ~0x7F) | mapping[op])
            count += 1
        i += 4
    with open(output_file, "wb") as f:
        f.write(data)
    os.chmod(output_file, 0o755)
    print(f"[ISA]  Remapped {count} instructions -> {output_file}")
    return count

def print_mapping(mapping, seed):
    print(f"\n  Active ISA Mapping (seed={seed}):")
    print(f"  {'Original':^16} {'Remapped':^16} Type")
    print(f"  {'-'*50}")
    for o, m in mapping.items():
        changed = " *" if o != m else ""
        print(f"  0x{o:02X} ({NAMES[o]:<10}) -> 0x{m:02X}{changed}")
    print(f"  SYSTEM 0x73 protected.")

def binary_comparison(std_binary, remapped_binary, mapping):
    try:
        with open(std_binary, 'rb') as f: orig = f.read()
        with open(remapped_binary, 'rb') as f: remap = f.read()
    except FileNotFoundError:
        print("  [WARN] Binaries not found for comparison."); return
    text_start, _ = get_text_section_bounds(bytearray(orig))
    print(f"\n  [INFO] Binary comparison from .text offset: 0x{text_start:X}")
    print("\n" + "="*72)
    print("  BINARY COMPARISON: Original vs Remapped (1s and 0s)")
    print("="*72)
    print(f"  {'Original (standard RISC-V)':^34} {'Remapped (this session)':^34}")
    print(f"  {'-'*34} {'-'*34}")
    shown = 0; i = 0
    while shown < 20 and text_start + i*4 + 4 <= len(orig):
        o  = struct.unpack_from('<I', orig,  text_start + i*4)[0]
        rm = struct.unpack_from('<I', remap, text_start + i*4)[0]
        if o == 0 and rm == 0: i += 1; continue
        diff = "  <- opcode changed" if o != rm else ""
        print(f"  {o:032b}  {rm:032b}{diff}")
        shown += 1; i += 1
    print("\n" + "="*72)
    print("  OPCODE MAPPING TABLE:")
    print(f"  {'Original':^20} {'Remapped':^20} Type")
    print(f"  {'-'*60}")
    for orig_op, mapped_op in mapping.items():
        changed = " *" if orig_op != mapped_op else ""
        print(f"  {orig_op:08b} (0x{orig_op:02X})     "
              f"{mapped_op:08b} (0x{mapped_op:02X})     "
              f"{NAMES.get(orig_op,'')}{changed}")
    print("\n  * = opcode changed | SYSTEM 0x73 always protected")
    print("="*72)

def main():
    if len(sys.argv) < 3:
        print("\nUsage: python3 isa_compile.py <source> <output> [seed]")
        print("  source: .c  .cpp  .cc  .cxx  or RISC-V ELF binary\n")
        sys.exit(1)
    source = sys.argv[1]
    output = sys.argv[2]
    seed   = int(sys.argv[3]) if len(sys.argv) > 3 else int.from_bytes(os.urandom(4), "big")
    print("\n" + "="*60)
    print("  RISC-V ISA-Aware Compiler (LLVM/Clang + ISA Mapper)")
    print("="*60)
    print(f"  Source : {source}\n  Output : {output}\n  Seed   : {seed}")
    std_binary = output + "_standard"
    compile_source(source, std_binary)
    mapping = generate_mapping(seed)
    print_mapping(mapping, seed)
    write_reverse_map(mapping)
    print(f"\n  Reverse map written -> {REVERSE_MAP}")
    remap_binary(std_binary, output, mapping)
    print(f"\n  Testing {output} with patched QEMU...")
    ret = os.system(f"{QEMU} {output} 2>/dev/null")
    status = "SUCCESS ✓" if ret == 0 else "FAILED ✗"
    print(f"  Result: {status} (exit {ret})")
    binary_comparison(std_binary, output, mapping)
    print("="*60 + "\n")

if __name__ == "__main__":
    main()
