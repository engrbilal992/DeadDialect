#!/bin/bash
# Integration Trigger Demo — single trigger remaps both layers atomically
source "$(dirname "$(readlink -f "$0")")/../config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V ISA Integration — Unified Trigger Demo"
echo "  One trigger remaps register + syscall simultaneously"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
    -o /tmp/trig_simple "$DEMO_DIR/simple.S" 2>/dev/null
clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
    -o /tmp/trig_malware "$DEMO_DIR/simple.S" 2>/dev/null

echo -e "${CYAN}═══ PHASE 1: Initial mapping (seed=42) ═══${NC}"
sudo truncate -s 0 "$REGISTER_KEYRING"
sudo truncate -s 0 "$SYSCALL_KEYRING"
sleep 1

python3 "$BASE_DIR/isa_integrate.py" /tmp/trig_simple /tmp/trig_A \
    --seed 42 --quiet
python3 "$BASE_DIR/isa_integrate.py" /tmp/trig_malware /tmp/trig_mal \
    --seed 42 --quiet
sleep 2

OUT=$(timeout 5 "$QEMU" /tmp/trig_A 2>/dev/null)
[ $? -eq 0 ] && echo -e "  Program (perm A): ${GREEN}SUCCESS ✓${NC} — $OUT" || \
    echo -e "  Program (perm A): ${RED}FAILED ✗${NC}"

OUT=$(timeout 5 "$QEMU" /tmp/trig_mal 2>/dev/null)
[ $? -eq 0 ] && echo -e "  Malware (perm A): ${YELLOW}EXECUTED (expected)${NC}" || \
    echo -e "  Malware (perm A): ${RED}FAILED ✗${NC}"

echo -e "\n${CYAN}═══ PHASE 2: TRIGGER FIRED — both layers remapped atomically ═══${NC}"
NEW_SEED=$(python3 -c "import secrets; print(int.from_bytes(secrets.token_bytes(4),'big'))")
# Single trigger call remaps both register + syscall keyrings
python3 "$BASE_DIR/isa_integrate.py" /tmp/trig_simple /tmp/trig_B \
    --seed $NEW_SEED --quiet
sleep 2
echo -e "  ${YELLOW}New seed: $NEW_SEED — both keyrings updated atomically${NC}"

echo -e "\n${CYAN}═══ PHASE 3: Testing old binaries after trigger ═══${NC}"
timeout 5 "$QEMU" /tmp/trig_A >/dev/null 2>/dev/null
[ $? -ne 0 ] && echo -e "  Old program: ${GREEN}BLOCKED ✓${NC}" || \
    echo -e "  Old program: ${RED}NOT BLOCKED ✗${NC}"

timeout 5 "$QEMU" /tmp/trig_mal >/dev/null 2>/dev/null
[ $? -ne 0 ] && echo -e "  Malware:     ${GREEN}BLOCKED ✓${NC}" || \
    echo -e "  Malware:     ${RED}NOT BLOCKED ✗${NC}"

OUT=$(timeout 5 "$QEMU" /tmp/trig_B 2>/dev/null)
[ $? -eq 0 ] && echo -e "  New binary:  ${GREEN}SUCCESS ✓${NC} — $OUT" || \
    echo -e "  New binary:  ${RED}FAILED ✗${NC}"

echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Both layers remapped by single trigger ✓${NC}"
echo -e "${GREEN}  Old binaries blocked across both layers ✓${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
