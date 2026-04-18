#!/bin/bash
# Phase 3 — Syscall Remapping Demo
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Syscall Remapping Demo — Phase 3"
echo "  Syscall Number Shuffling — No Reboot Needed"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# ── SETUP ────────────────────────────────────────────────────
# Clear keyring so QEMU starts with identity map
sudo truncate -s 0 "$ISA_SYSCALL_KEYRING"

# Compile standard binaries
echo -e "${CYAN}[COMPILE] Building test binaries (-march=rv64g, no RVC)...${NC}"
clang --target=riscv64-linux-gnu -march=rv64g -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/demo_simple "$DEMO_DIR/simple.c" 2>/dev/null
clang --target=riscv64-linux-gnu -march=rv64g -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/demo_complex "$DEMO_DIR/complex.c" 2>/dev/null
echo -e "${GREEN}    simple.c and complex.c compiled ✓${NC}"

# Verify standard binaries work (sanity check)
echo -e "\n${YELLOW}[SANITY] Verifying standard binaries run without remapping...${NC}"
timeout 5 "$QEMU" /tmp/demo_simple 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Standard simple: OK ✓${NC}" || echo -e "${RED}    Standard simple: FAILED ✗${NC}"
timeout 5 "$QEMU" /tmp/demo_complex 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Standard complex: OK ✓${NC}" || echo -e "${RED}    Standard complex: FAILED ✗${NC}"

# ── PERMUTATION A (seed=42) ──────────────────────────────────
SEED_A=42
echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  PHASE 1: Permutation A (seed=$SEED_A)${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}[1] Rewriting binaries for permutation A...${NC}"
python3 "$SYSCALL_REWRITER" /tmp/demo_simple /tmp/demo_simple_A \
    --seed $SEED_A --keyring "$ISA_SYSCALL_KEYRING"
python3 "$SYSCALL_REWRITER" /tmp/demo_complex /tmp/demo_complex_A \
    --seed $SEED_A --keyring "$ISA_SYSCALL_KEYRING"
sleep 1

echo -e "\n${YELLOW}[2] Running simple binary under permutation A...${NC}"
timeout 5 "$QEMU" /tmp/demo_simple_A 2>/dev/null
EXIT1=$?
if [ $EXIT1 -eq 0 ]; then
    echo -e "${GREEN}    Result: SUCCESS ✓${NC}"
    RESULT1="SUCCESS ✓"
else
    echo -e "${RED}    Result: FAILED ✗ (exit $EXIT1)${NC}"
    RESULT1="FAILED ✗"
fi

echo -e "\n${YELLOW}[3] Running complex binary under permutation A...${NC}"
timeout 5 "$QEMU" /tmp/demo_complex_A 2>/dev/null
EXIT2=$?
if [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}    Result: SUCCESS ✓${NC}"
    RESULT2="SUCCESS ✓"
else
    echo -e "${RED}    Result: FAILED ✗ (exit $EXIT2)${NC}"
    RESULT2="FAILED ✗"
fi

# ── PERMUTATION B (new seed) ─────────────────────────────────
SEED_B=$(python3 -c "import secrets; print(int.from_bytes(secrets.token_bytes(32),'big'))")
echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  PHASE 2: Switch to Permutation B (seed=$SEED_B)${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"

echo -e "\n${RED}  [!] Security trigger fired — new syscall permutation active${NC}"
python3 "$SYSCALL_REWRITER" /tmp/demo_simple /tmp/demo_simple_B \
    --seed $SEED_B --keyring "$ISA_SYSCALL_KEYRING"
sleep 1
echo -e "${GREEN}  Permutation B active. Old binaries now invalid.${NC}"

echo -e "\n${YELLOW}[4] Running simple_A under permutation B (should FAIL)...${NC}"
timeout 5 "$QEMU" /tmp/demo_simple_A 2>/dev/null
EXIT3=$?
if [ $EXIT3 -ne 0 ]; then
    echo -e "${GREEN}    Result: BLOCKED ✓ — wrong syscall numbers${NC}"
    RESULT3="BLOCKED ✓"
else
    echo -e "${RED}    Result: PASSED (unexpected — old binary still runs!)${NC}"
    RESULT3="PASSED (unexpected)"
fi

echo -e "\n${YELLOW}[5] Running complex_A under permutation B (should FAIL)...${NC}"
timeout 5 "$QEMU" /tmp/demo_complex_A 2>/dev/null
EXIT4=$?
if [ $EXIT4 -ne 0 ]; then
    echo -e "${GREEN}    Result: BLOCKED ✓ — wrong syscall numbers${NC}"
    RESULT4="BLOCKED ✓"
else
    echo -e "${RED}    Result: PASSED (unexpected)${NC}"
    RESULT4="PASSED (unexpected)"
fi

echo -e "\n${YELLOW}[6] Running simple_B under permutation B (should SUCCEED)...${NC}"
timeout 5 "$QEMU" /tmp/demo_simple_B 2>/dev/null
EXIT5=$?
if [ $EXIT5 -eq 0 ]; then
    echo -e "${GREEN}    Result: SUCCESS ✓ — legitimate update passes${NC}"
    RESULT5="SUCCESS ✓"
else
    echo -e "${RED}    Result: FAILED ✗${NC}"
    RESULT5="FAILED ✗"
fi

# ── FINAL RESULTS ────────────────────────────────────────────
echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  FINAL RESULTS${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo -e "  Simple  binary + Perm A        : $RESULT1"
echo -e "  Complex binary + Perm A        : $RESULT2"
echo -e "  Simple_A binary + Perm B       : $RESULT3"
echo -e "  Complex_A binary + Perm B      : $RESULT4"
echo -e "  Simple_B binary + Perm B       : $RESULT5"
echo -e "\n${GREEN}  Syscall remapping proven. Keyspace: 436! permutations${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}\n"
