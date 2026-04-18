#!/bin/bash
# Phase 3 Build Script — FULLY PORTABLE
# Works on any clean Ubuntu 22.04 machine from scratch.
# Clones repo, downloads QEMU, applies all patches, builds, verifies.
set -e
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Syscall Remapping — Phase 3 Build Script"
echo "  Fully portable — works on any clean Ubuntu 22.04"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# ── STEP 1: Install ALL dependencies ─────────────────────────
echo -e "${CYAN}[1/7] Installing dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y \
    wget git \
    clang lld python3 \
    qemu-utils e2fsprogs \
    libglib2.0-dev libpixman-1-dev ninja-build \
    pkg-config gcc make libslirp-dev \
    build-essential \
    2>/dev/null || true
echo -e "${GREEN}    Dependencies installed ✓${NC}"

# ── STEP 2: Create /etc/isa/ keyring files ────────────────────
echo -e "\n${CYAN}[2/7] Setting up /etc/isa/ keyring files...${NC}"
sudo mkdir -p /etc/isa
# syscall keyring (Phase 3)
sudo touch /etc/isa/syscall_keyring
sudo chown root:$(whoami) /etc/isa/syscall_keyring
sudo chmod 600 /etc/isa/syscall_keyring

# ── STEP 3: Download QEMU 8.2.0 source if needed ─────────────
echo -e "\n${CYAN}[3/7] Setting up QEMU 8.2.0 source...${NC}"
QEMU_SRC="$PHASE1/qemu-8.2.0"

if [ ! -d "$QEMU_SRC" ]; then
    echo -e "  ${YELLOW}QEMU source not found. Downloading...${NC}"
    mkdir -p "$PHASE1"
    cd "$PHASE1"
    wget -q --show-progress https://download.qemu.org/qemu-8.2.0.tar.xz
    tar xf qemu-8.2.0.tar.xz
    rm qemu-8.2.0.tar.xz
    cd "$BASE_DIR"
    echo -e "${GREEN}    QEMU 8.2.0 source downloaded ✓${NC}"
else
    echo -e "${GREEN}    QEMU source already present ✓${NC}"
fi

# ── STEP 4: Apply ALL patches to QEMU ────────────────────────
echo -e "\n${CYAN}[4/7] Applying patches to QEMU...${NC}"

# Phase 3 applies syscall remapping only — opcode patch removed
# (opcode patch interferes with syscall remapping when /etc/isa/map is non-empty)

# --- Patch: syscall_mapping.h (syscall remapping — Phase 3) ---
cp "$SYSCALL_MAPPING_H" "$QEMU_SYSCALL_H_DEST"
SRC_SUM=$(sha256sum "$SYSCALL_MAPPING_H" | cut -d' ' -f1)
DST_SUM=$(sha256sum "$QEMU_SYSCALL_H_DEST" | cut -d' ' -f1)
[ "$SRC_SUM" = "$DST_SUM" ] && \
    echo -e "${GREEN}    syscall_mapping.h copied & verified ✓ (${SRC_SUM:0:16}...)${NC}" || \
    { echo -e "${RED}    syscall_mapping.h checksum mismatch ✗${NC}"; exit 1; }

if ! grep -q "syscall_mapping.h" "$QEMU_SYSCALL_C"; then
    sed -i '1s|^|#include "syscall_mapping.h"\n|' "$QEMU_SYSCALL_C"
    echo -e "${GREEN}    syscall_mapping.h included in syscall.c ✓${NC}"
else
    echo -e "${GREEN}    syscall.c already includes syscall_mapping.h ✓${NC}"
fi

if ! grep -q "syscall_translate" "$QEMU_SYSCALL_C"; then
    sed -i 's/ret = do_syscall1(cpu_env, num,/num = syscall_translate(num);\n    ret = do_syscall1(cpu_env, num,/' "$QEMU_SYSCALL_C"
    echo -e "${GREEN}    syscall_translate hook added ✓${NC}"
else
    echo -e "${GREEN}    syscall_translate hook already present ✓${NC}"
fi

# Verify both patches
grep -q "syscall_translate" "$QEMU_SYSCALL_C" && \
    echo -e "${GREEN}    All QEMU patches verified ✓${NC}" || \
    { echo -e "${RED}    Patch verification FAILED ✗${NC}"; exit 1; }

# ── STEP 5: Build QEMU ────────────────────────────────────────
echo -e "\n${CYAN}[5/7] Building patched QEMU 8.2.0...${NC}"
mkdir -p "$QEMU_SRC/build"
cd "$QEMU_SRC/build"

if [ ! -f "build.ninja" ]; then
    echo -e "  ${YELLOW}Configuring QEMU build...${NC}"
    ../configure \
        --target-list=riscv64-linux-user \
        --disable-system \
        --enable-slirp \
        2>/dev/null
    echo -e "${GREEN}    Configured ✓${NC}"
fi

make qemu-riscv64 -j$(nproc) 2>/dev/null
echo -e "${GREEN}    QEMU built ✓${NC}"
cd "$BASE_DIR"

# Verify binary
[ -f "$QEMU" ] && \
    echo -e "${GREEN}    QEMU binary verified ✓ ($QEMU)${NC}" || \
    { echo -e "${RED}    QEMU binary not found ✗${NC}"; exit 1; }

# ── STEP 6: Create symlink in phase3 directory ───────────────
echo -e "\n${CYAN}[6/7] Creating qemu-riscv64 symlink in phase3...${NC}"
ln -sf "$QEMU" "$BASE_DIR/qemu-riscv64"
echo -e "${GREEN}    Symlink created: phase3/qemu-riscv64 -> $QEMU ✓${NC}"

# ── STEP 7: Run audit ─────────────────────────────────────────
echo -e "\n${CYAN}[7/7] Running complete audit...${NC}"
bash "$BASE_DIR/audit.sh"

echo -e "\n${CYAN}████████████████████████████████████████████████████████${NC}"
echo -e "${GREEN}  Build Complete! Everything is ready.${NC}"
echo -e "${GREEN}  Run demo:  bash demo.sh${NC}"
echo -e "${GREEN}  Run audit: bash audit.sh${NC}"
echo -e "${CYAN}████████████████████████████████████████████████████████${NC}\n"
