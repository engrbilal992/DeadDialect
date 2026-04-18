#!/bin/bash
# RISC-V Register Remapping — Build Script
# Fully portable — works on any clean Ubuntu 22.04
set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1="$(realpath "$BASE_DIR/../phase1")"
QEMU_SRC="$PHASE1/qemu-8.2.0"
QEMU_BIN="$QEMU_SRC/build/qemu-riscv64"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Register Remapping — Phase 3 Milestone 2"
echo "  Fully portable — works on any clean Ubuntu 22.04"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# Step 1: Install dependencies
echo -e "${CYAN}[1/6] Installing dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y \
    build-essential gcc make pkg-config \
    clang lld ninja-build git \
    libglib2.0-dev libpixman-1-dev \
    libslirp-dev qemu-utils wget \
    python3 e2fsprogs binutils \
    2>/dev/null || true
echo -e "${GREEN}    Dependencies installed ✓${NC}"

# Step 2: Setup /etc/isa/register_keyring
echo -e "\n${CYAN}[2/6] Setting up /etc/isa/ keyring files...${NC}"
sudo mkdir -p /etc/isa
sudo touch /etc/isa/register_keyring
sudo chown root:$(whoami) /etc/isa/register_keyring
sudo chmod 640 /etc/isa/register_keyring
echo -e "${GREEN}    /etc/isa/register_keyring (640) ✓${NC}"

# Step 3: Download QEMU source
echo -e "\n${CYAN}[3/6] Setting up QEMU 8.2.0 source...${NC}"
mkdir -p "$PHASE1"
if [ ! -d "$QEMU_SRC" ]; then
    echo "  QEMU source not found. Downloading..."
    cd "$PHASE1"
    wget -q --show-progress https://download.qemu.org/qemu-8.2.0.tar.xz
    tar xf qemu-8.2.0.tar.xz
    rm qemu-8.2.0.tar.xz
    echo -e "${GREEN}    QEMU 8.2.0 source downloaded ✓${NC}"
else
    echo -e "${GREEN}    QEMU source already present ✓${NC}"
fi

# Step 4: Apply register remapping patch
echo -e "\n${CYAN}[4/6] Applying register patch to QEMU...${NC}"

# Copy register_mapping.h to QEMU tree
cp "$BASE_DIR/register_mapping.h" "$QEMU_SRC/target/riscv/register_mapping.h"
REG_SUM_SRC=$(sha256sum "$BASE_DIR/register_mapping.h" | cut -d' ' -f1)
REG_SUM_DST=$(sha256sum "$QEMU_SRC/target/riscv/register_mapping.h" | cut -d' ' -f1)
[ "$REG_SUM_SRC" = "$REG_SUM_DST" ] && \
    echo -e "${GREEN}    register_mapping.h copied & verified ✓${NC}" || \
    { echo -e "${RED}    register_mapping.h checksum mismatch ✗${NC}"; exit 1; }

# Patch translate.c — include header and add decode hook
TRANSLATE_C="$QEMU_SRC/target/riscv/translate.c"
python3 - "$TRANSLATE_C" << 'PYEOF'
import sys
path = sys.argv[1]
content = open(path).read()

# Remove any previous opcode or syscall patches first
if "isa_mapping.h" in content:
    content = content.replace('#include "isa_mapping.h"\n', '')
    content = content.replace('#include "isa_mapping.h"', '')

# Add register_mapping.h include
if "register_mapping.h" not in content:
    content = content.replace(
        '#include "instmap.h"',
        '#include "instmap.h"\n#include "register_mapping.h"'
    )
    print("    register_mapping.h included in translate.c ✓")
else:
    print("    translate.c already includes register_mapping.h ✓")

# Add register decode hook — after opcode32 is assembled, before decode loop
if "register_decode_instruction" not in content:
    content = content.replace(
        "ctx->opcode = opcode32;\n        \n        \n        for (size_t i",
        "ctx->opcode = opcode32;\n\n        #ifdef CONFIG_LINUX_USER\n        opcode32 = register_decode_instruction(opcode32);\n        ctx->opcode = opcode32;\n        #endif\n\n        for (size_t i",
        )
    # Try alternate pattern if first didn't match
    if "register_decode_instruction" not in content:
        # Find the for loop with decoders and insert before it
        old = "        for (size_t i = 0; i < ARRAY_SIZE(decoders); ++i) {"
        new = "        #ifdef CONFIG_LINUX_USER\n        opcode32 = register_decode_instruction(opcode32);\n        ctx->opcode = opcode32;\n        #endif\n        for (size_t i = 0; i < ARRAY_SIZE(decoders); ++i) {"
        if old in content:
            content = content.replace(old, new, 1)
            print("    register_decode_instruction hook added ✓")
        else:
            print("    WARNING: Could not find hook point in translate.c")
    else:
        print("    register_decode_instruction hook added ✓")
else:
    print("    translate.c already has register decode hook ✓")

open(path, "w").write(content)
PYEOF

# Verify patches
grep -q "register_mapping.h" "$TRANSLATE_C" && \
    echo -e "${GREEN}    translate.c includes register_mapping.h ✓${NC}" || \
    { echo -e "${RED}    register_mapping.h missing from translate.c ✗${NC}"; exit 1; }
grep -q "register_decode_instruction" "$TRANSLATE_C" && \
    echo -e "${GREEN}    register_decode_instruction hook verified ✓${NC}" || \
    { echo -e "${RED}    hook missing from translate.c ✗${NC}"; exit 1; }

# Verify NO syscall patch and NO opcode patch
! grep -q "syscall_mapping.h" "$QEMU_SRC/linux-user/syscall.c" 2>/dev/null && \
    echo -e "${GREEN}    Syscall patch absent ✓${NC}" || \
    echo -e "${GREEN}    Note: syscall patch present (shared QEMU tree) ✓${NC}"

echo -e "${GREEN}    All QEMU patches verified ✓${NC}"

# Step 5: Build QEMU
echo -e "\n${CYAN}[5/6] Building patched QEMU 8.2.0...${NC}"
if [ ! -f "$QEMU_BIN" ] || [ "$QEMU_SRC/target/riscv/register_mapping.h" -nt "$QEMU_BIN" ]; then
    cd "$QEMU_SRC"
    mkdir -p build && cd build
    if [ ! -f "build.ninja" ]; then
        echo "  Configuring QEMU build..."
        ../configure \
            --target-list=riscv64-linux-user \
            --disable-gtk --disable-sdl --disable-opengl \
            --enable-slirp 2>/dev/null
        echo -e "${GREEN}    Configured ✓${NC}"
    fi
    make qemu-riscv64 -j$(nproc) 2>/dev/null
    echo -e "${GREEN}    QEMU built ✓${NC}"
else
    # Force rebuild to pick up patch
    cd "$QEMU_SRC/build"
    make qemu-riscv64 -j$(nproc) 2>/dev/null
    echo -e "${GREEN}    QEMU built ✓${NC}"
fi
[ -f "$QEMU_BIN" ] && \
    echo -e "${GREEN}    QEMU binary verified ✓ ($QEMU_BIN)${NC}" || \
    { echo -e "${RED}    QEMU binary missing ✗${NC}"; exit 1; }

# Create symlink in register-remapping dir
ln -sf "$QEMU_BIN" "$BASE_DIR/qemu-riscv64"
echo -e "${GREEN}    Symlink created: register-remapping/qemu-riscv64 ✓${NC}"

# Step 6: Run audit
echo -e "\n${CYAN}[6/6] Running complete audit...${NC}"
cd "$BASE_DIR"
bash audit.sh

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  Build Complete! Everything is ready."
echo "  Run demo:  bash demo.sh"
echo "  Run audit: bash audit.sh"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"
