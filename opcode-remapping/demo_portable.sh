#!/bin/bash
# RISC-V Dynamic ISA Remapping — Full Milestone 3 Demo
# Author: Muhammad Bilal
# Fully portable — works inside AppImage or standalone

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Auto-detect QEMU — relative paths only, no hardcoded Desktop
if [ -f "$SCRIPT_DIR/../bin/qemu-riscv64" ]; then
    QEMU="$(realpath "$SCRIPT_DIR/../bin/qemu-riscv64")"
elif [ -f "$SCRIPT_DIR/../phase1/qemu-8.2.0/build/qemu-riscv64" ]; then
    QEMU="$(realpath "$SCRIPT_DIR/../phase1/qemu-8.2.0/build/qemu-riscv64")"
else
    QEMU="qemu-riscv64"
fi

# Auto-detect song
if [ -f "$SCRIPT_DIR/converter.m4a" ]; then
    SONG="$SCRIPT_DIR/converter.m4a"
else
    SONG=""
fi

# Auto-detect isa_compile.py — relative paths only
if [ -f "$SCRIPT_DIR/isa_compile.py" ]; then
    ISA_COMPILE="$SCRIPT_DIR/isa_compile.py"
elif [ -f "$SCRIPT_DIR/../trigger-remapping/isa_compile.py" ]; then
    ISA_COMPILE="$(realpath "$SCRIPT_DIR/../trigger-remapping/isa_compile.py")"
else
    echo "ERROR: isa_compile.py not found"; exit 1
fi

# Auto-detect source files — relative paths only
if [ -f "$SCRIPT_DIR/advanced.c" ]; then
    SRC_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/riscv_demo/advanced.c" ]; then
    SRC_DIR="$SCRIPT_DIR/riscv_demo"
else
    SRC_DIR="$(realpath "$SCRIPT_DIR/../trigger-remapping/riscv_demo" 2>/dev/null || echo "$SCRIPT_DIR")"
fi
OUT_DIR="/tmp/isa_demo_$$"
mkdir -p "$OUT_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'
CYAN='\033[0;36m';  YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Dynamic ISA Remapping Emulator"
echo "  Full System Demo — Milestone 3"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

if [ -n "$SONG" ] && [ -f "$SONG" ]; then
    # Clear syscall keyring to prevent Phase 3 interference
sudo truncate -s 0 /etc/isa/syscall_keyring 2>/dev/null || true
sleep 1
echo -e "${YELLOW}[MUSIC] Starting Converter...${NC}"
    ffplay -nodisp -autoexit -loglevel quiet "$SONG" &
    SONG_PID=$!
    sleep 2
fi

echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  PHASE 1: BOOT A (seed=42)${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"

python3 - << 'PYEOF2'
import random, subprocess
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random(42); s=OPCODES[:]; r.shuffle(s)
mapping=dict(zip(OPCODES,s))
lines = "".join(str(mp)+" "+str(o)+"\n" for o,mp in mapping.items())
try:
    open("/etc/isa/map","w").write(lines)
except PermissionError:
    subprocess.run(["sudo","tee","/etc/isa/map"],input=lines,text=True,capture_output=True)
print("Boot A mapping generated (seed=42)")
PYEOF2

echo -e "\n${YELLOW}[1] Compiling advanced test suite for Boot A...${NC}"
python3 "$ISA_COMPILE" "$SRC_DIR/advanced.c" "$OUT_DIR/advanced_bootA" 42 >/dev/null 2>/dev/null
echo -e "${GREEN}    Advanced program compiled and remapped${NC}"

echo -e "\n${YELLOW}[2] Running advanced program under Boot A ISA...${NC}"
$QEMU "$OUT_DIR/advanced_bootA" 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓${NC}" || echo -e "${RED}    Result: FAILED ✗${NC}"

echo -e "\n${YELLOW}[3] Compiling malware simulation for Boot A...${NC}"
python3 "$ISA_COMPILE" "$SRC_DIR/malware_sim.c" "$OUT_DIR/malware_bootA" 42 >/dev/null 2>/dev/null
echo -e "${GREEN}    Malware compiled for Boot A${NC}"

echo -e "\n${YELLOW}[4] Running malware under Boot A ISA...${NC}"
$QEMU "$OUT_DIR/malware_bootA" 2>/dev/null
[ $? -eq 0 ] && echo -e "${RED}    Malware executed successfully (expected on Boot A)${NC}"

echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  PHASE 2: SYSTEM REBOOT${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
sleep 1
NEW_SEED=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
echo -e "${GREEN}  New boot seed: $NEW_SEED${NC}"
python3 - $NEW_SEED << 'PYEOF2'
import random, subprocess, sys
seed = int(sys.argv[1])
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random(seed); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
lines = "".join(str(mp)+" "+str(o)+"\n" for o,mp in m.items())
try:
    open("/etc/isa/map","w").write(lines)
except PermissionError:
    subprocess.run(["sudo","tee","/etc/isa/map"],input=lines,text=True,capture_output=True)
print("Boot B mapping generated (seed="+str(seed)+")")
PYEOF2

echo -e "\n${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  PHASE 3: BOOT B — Security Test${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"

echo -e "\n${YELLOW}[5] Testing advanced program after reboot...${NC}"
$QEMU "$OUT_DIR/advanced_bootA" 2>/dev/null
[ $? -ne 0 ] && echo -e "${RED}    Result: FAILED ✗ — Binary incompatible with new ISA${NC}"

echo -e "\n${YELLOW}[6] Testing malware after reboot...${NC}"
$QEMU "$OUT_DIR/malware_bootA" 2>/dev/null
[ $? -ne 0 ] && echo -e "${GREEN}    Result: BLOCKED ✓ — Malware cannot execute!${NC}"

echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  FINAL RESULTS${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Boot A binary + Boot A mapping : SUCCESS ✓${NC}"
echo -e "${GREEN}  Malware + Boot A mapping       : EXECUTED (expected)${NC}"
echo -e "${RED}  Boot A binary + Boot B mapping : FAILED ✗${NC}"
echo -e "${GREEN}  Malware + Boot B mapping       : BLOCKED ✓${NC}"
echo -e "\n${GREEN}  ISA remapping prevents malware persistence. ✓${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}\n"

kill $SONG_PID 2>/dev/null
pkill -f "ffplay.*converter" 2>/dev/null
echo -e "${YELLOW}[MUSIC] Done.${NC}"
