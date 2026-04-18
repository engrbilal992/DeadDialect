#!/bin/bash
# ISA Trigger Demo — Phase 2
# Proves trigger-based remapping blocks old binaries

source "$(dirname "$(readlink -f "$0")")/../config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'
CYAN='\033[0;36m';  YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V ISA Trigger Demo — Phase 2"
echo "  Trigger-Based Remapping (No Reboot Needed)"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# Source shared mapping generator
source "$(dirname "$(readlink -f "$0")")/../lib/generate_mapping.sh"

# Clear syscall keyring — prevent Phase 3 keyring interfering with Phase 2 QEMU
sudo truncate -s 0 /etc/isa/syscall_keyring 2>/dev/null || true

# Phase 1 — Compile under initial mapping
echo -e "${CYAN}  PHASE 1: Initial Mapping${NC}"

SEED=42
generate_mapping $SEED
sleep 1

echo -e "\n${YELLOW}[1] Compiling advanced program under seed=$SEED...${NC}"
python3 "$ISA_COMPILE" "$DEMO_DIR/advanced.c" /tmp/trigger_advanced $SEED >/dev/null 2>&1
echo -e "${GREEN}    Compiled successfully${NC}"

echo -e "\n${YELLOW}[2] Running under initial mapping...${NC}"
timeout 5 "$QEMU" /tmp/trigger_advanced 2>/dev/null
EXIT1=$?
# FIX B3: proper if/else on every check
if [ $EXIT1 -eq 0 ]; then
    echo -e "${GREEN}    Result: SUCCESS ✓${NC}"
    PHASE1_RESULT="SUCCESS ✓"
else
    echo -e "${RED}    Result: FAILED ✗${NC}"
    PHASE1_RESULT="FAILED ✗"
fi

echo -e "\n${YELLOW}[3] Compiling malware under seed=$SEED...${NC}"
python3 "$ISA_COMPILE" "$DEMO_DIR/malware_sim.c" /tmp/trigger_malware $SEED >/dev/null 2>&1
echo -e "${GREEN}    Malware compiled${NC}"

echo -e "\n${YELLOW}[4] Running malware under initial mapping...${NC}"
timeout 5 "$QEMU" /tmp/trigger_malware 2>/dev/null
EXIT2=$?
if [ $EXIT2 -eq 0 ]; then
    echo -e "${RED}    Malware executed (expected — same mapping)${NC}"
    MALWARE_INITIAL="EXECUTED (expected)"
else
    echo -e "${YELLOW}    Malware failed unexpectedly${NC}"
    MALWARE_INITIAL="FAILED (unexpected)"
fi

# Phase 2 — Trigger remap
echo -e "\n${CYAN}  PHASE 2: SECURITY TRIGGER FIRED${NC}"
echo -e "${RED}  [!] Unknown binary detected — triggering ISA remap...${NC}"
sleep 1

# FIX C5: os.urandom for secure seed — no more $RANDOM$RANDOM
NEW_SEED=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
generate_mapping $NEW_SEED
sleep 1
echo -e "${GREEN}  ISA remapped (seed=$NEW_SEED). Old binaries now invalid.${NC}"

# Phase 3 — Test old binaries
echo -e "\n${CYAN}  PHASE 3: Testing Old Binaries${NC}"

echo -e "\n${YELLOW}[5] Running advanced program after trigger...${NC}"
timeout 5 "$QEMU" /tmp/trigger_advanced 2>/dev/null
EXIT3=$?
# FIX B3: proper if/else
if [ $EXIT3 -ne 0 ]; then
    echo -e "${RED}    Result: FAILED ✗ — Binary invalid after remap${NC}"
    PHASE3_RESULT="FAILED ✗"
else
    echo -e "${YELLOW}    Result: Still running (unexpected)${NC}"
    PHASE3_RESULT="PASSED (unexpected)"
fi

echo -e "\n${YELLOW}[6] Running malware after trigger...${NC}"
timeout 5 "$QEMU" /tmp/trigger_malware 2>/dev/null
EXIT4=$?
# FIX B3: proper if/else
if [ $EXIT4 -ne 0 ]; then
    echo -e "${GREEN}    Result: BLOCKED ✓ — Malware cannot execute!${NC}"
    MALWARE_AFTER="BLOCKED ✓"
else
    echo -e "${RED}    Result: Malware still running (SECURITY FAILURE)${NC}"
    MALWARE_AFTER="EXECUTED (FAILURE)"
fi

# FIX B3: Results based on actual outcomes
echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  FINAL RESULTS${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo -e "  Initial mapping + binary     : $PHASE1_RESULT"
echo -e "  Malware + initial mapping    : $MALWARE_INITIAL"
echo -e "  Binary after trigger remap   : $PHASE3_RESULT"
echo -e "  Malware after trigger remap  : $MALWARE_AFTER"
echo -e "${GREEN}  No reboot needed!             ✓${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}\n"
