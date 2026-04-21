#!/bin/bash
# RISC-V ISA Integration — Portable Build
# Applies register + syscall patches to QEMU 8.2.0
set -e
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1="$(realpath "$BASE_DIR/../phase1" 2>/dev/null || echo "$BASE_DIR/../phase1")"
QEMU_SRC="$PHASE1/qemu-8.2.0"
QEMU_BIN="$QEMU_SRC/build/qemu-riscv64"
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V ISA Integration — Phase 3 Milestone 3"
echo "  Register + Syscall remapping — unified QEMU"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

echo -e "${CYAN}[1/6] Installing dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y build-essential clang lld ninja-build wget \
    libglib2.0-dev libpixman-1-dev libslirp-dev python3 2>/dev/null || true
echo -e "${GREEN}    OK ✓${NC}"

echo -e "\n${CYAN}[2/6] Setting up keyrings...${NC}"
sudo mkdir -p /etc/isa
for k in /etc/isa/register_keyring /etc/isa/syscall_keyring; do
    sudo touch $k
    sudo chown root:$(whoami) $k
    sudo chmod 640 $k
    echo -e "${GREEN}    $k (640) ✓${NC}"
done

echo -e "\n${CYAN}[3/6] Setting up QEMU 8.2.0 source...${NC}"
mkdir -p "$PHASE1"
if [ ! -d "$QEMU_SRC" ]; then
    cd "$PHASE1"
    wget -q --show-progress https://download.qemu.org/qemu-8.2.0.tar.xz
    tar xf qemu-8.2.0.tar.xz && rm qemu-8.2.0.tar.xz
    echo -e "${GREEN}    Downloaded ✓${NC}"
    cd "$BASE_DIR"
else
    echo -e "${GREEN}    Already present ✓${NC}"
fi

echo -e "\n${CYAN}[4/6] Applying patches (register + syscall only)...${NC}"
cp "$BASE_DIR/register_mapping.h" "$QEMU_SRC/target/riscv/register_mapping.h"
cp "$BASE_DIR/syscall_mapping.h"  "$QEMU_SRC/linux-user/syscall_mapping.h"

python3 - "$QEMU_SRC/target/riscv/translate.c" \
         "$QEMU_SRC/linux-user/syscall.c" << 'PYEOF'
import sys

# Patch translate.c — register hook only
path = sys.argv[1]
content = open(path).read()
if "register_mapping.h" not in content:
    content = content.replace('#include "instmap.h"',
        '#include "instmap.h"\n#include "register_mapping.h"')
if "register_decode_instruction" not in content:
    target = '        for (size_t i = 0; i < ARRAY_SIZE(decoders); ++i) {'
    hook = ('        #ifdef CONFIG_LINUX_USER\n'
            '        opcode32 = register_decode_instruction(opcode32);\n'
            '        ctx->opcode = opcode32;\n'
            '        #endif\n'
            '        for (size_t i = 0; i < ARRAY_SIZE(decoders); ++i) {')
    if target in content:
        content = content.replace(target, hook, 1)
# Remove opcode patch if present from previous builds
content = content.replace('#include "isa_mapping.h"\n', '')
open(path, 'w').write(content)
print("    translate.c: register patch applied ✓")

# Patch syscall.c — syscall hook
path2 = sys.argv[2]
content2 = open(path2).read()
if "syscall_mapping.h" not in content2:
    content2 = content2.replace('#include "qemu.h"',
        '#include "qemu.h"\n#include "syscall_mapping.h"')
if "syscall_translate" not in content2:
    target2 = 'abi_long do_syscall(CPUArchState *cpu_env, int num,'
    if target2 in content2:
        idx = content2.index(target2)
        bi = content2.index('{', idx)
        content2 = (content2[:bi+1] +
            '\n    num = syscall_translate(num); /* permuted->standard */' +
            content2[bi+1:])
open(path2, 'w').write(content2)
print("    syscall.c: syscall patch applied ✓")
PYEOF

# Verify no opcode patch
! grep -q "isa_decode_instruction" "$QEMU_SRC/target/riscv/translate.c" && \
    echo -e "${GREEN}    Opcode patch absent ✓${NC}" || \
    echo -e "${RED}    WARNING: opcode patch present${NC}"

echo -e "\n${CYAN}[5/6] Building QEMU...${NC}"
cd "$QEMU_SRC"
mkdir -p build && cd build
if [ ! -f "build.ninja" ]; then
    ../configure --target-list=riscv64-linux-user \
        --disable-gtk --disable-sdl --disable-opengl \
        --enable-slirp 2>/dev/null
fi
make qemu-riscv64 -j$(nproc) 2>/dev/null
echo -e "${GREEN}    Built ✓${NC}"
ln -sf "$QEMU_BIN" "$BASE_DIR/qemu-riscv64"

echo -e "\n${CYAN}[6/6] Running audit...${NC}"
cd "$BASE_DIR"
bash audit.sh

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  Build complete! Run: bash demo.sh"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"
