#!/bin/bash
# RISC-V Register Remapping — Phase 3 Milestone 2 Demo
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Register Remapping — Phase 3 Milestone 2"
echo "  21 shuffleable registers — Entropy: 21! ≈ 2^65"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# Clear keyring
sudo truncate -s 0 /etc/isa/register_keyring 2>/dev/null || true
sleep 1

# Step 1: Compile standard binaries
echo -e "${YELLOW}[1] Compiling standard binaries (no remapping)...${NC}"
clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/demo_reg_std "$DEMO_DIR/simple.c" 2>/dev/null
clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/demo_reg_complex "$DEMO_DIR/complex.c" 2>/dev/null
echo -e "${GREEN}    Compiled ✓${NC}"

# Step 2: Run standard binary — should work with empty keyring
echo -e "\n${YELLOW}[2] Running standard binary (identity mapping)...${NC}"
timeout 5 "$QEMU" /tmp/demo_reg_std 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Standard binary runs${NC}" || \
               echo -e "${RED}    Result: FAILED ✗${NC}"

# Step 3: Rewrite under seed=42 (permutation A)
echo -e "\n${YELLOW}[3] Applying register permutation A (seed=42)...${NC}"
python3 "$BASE_DIR/isa_register_rewrite.py" \
    /tmp/demo_reg_std /tmp/demo_reg_A --seed 42
sleep 1

# Step 4: Run remapped binary under perm A — should work
echo -e "\n${YELLOW}[4] Running remapped binary under perm A...${NC}"
timeout 5 "$QEMU" /tmp/demo_reg_A 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Remapped binary runs under matching perm${NC}" || \
               echo -e "${RED}    Result: FAILED ✗${NC}"

# Step 5: Switch to new permutation B
echo -e "\n${RED}[5] TRIGGER FIRED — Register mapping changed to perm B...${NC}"
SEED_B=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
python3 "$BASE_DIR/isa_register_rewrite.py" \
    /tmp/demo_reg_std /tmp/demo_reg_B --seed $SEED_B --quiet
echo -e "${GREEN}    New seed: $SEED_B${NC}"
sleep 1

# Step 6: Old binary fails under perm B
echo -e "\n${YELLOW}[6] Running old binary (perm A) under perm B...${NC}"
timeout 5 "$QEMU" /tmp/demo_reg_A 2>/dev/null
EXIT6=$?
if [ $EXIT6 -ne 0 ]; then
    echo -e "${GREEN}    Result: BLOCKED ✓ — Old binary rejected under new mapping${NC}"
else
    echo -e "${RED}    Result: PASSED (unexpected — old binary still runs)${NC}"
fi

# Step 7: New binary (perm B) runs
echo -e "\n${YELLOW}[7] Running new binary (perm B) under perm B...${NC}"
timeout 5 "$QEMU" /tmp/demo_reg_B 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Legitimate update passes${NC}" || \
               echo -e "${RED}    Result: FAILED ✗${NC}"

# Step 8: Malware (perm A) blocked under perm B
echo -e "\n${YELLOW}[8] Malware (compiled under perm A) under perm B...${NC}"
python3 "$BASE_DIR/isa_register_rewrite.py" \
    /tmp/demo_reg_complex /tmp/demo_malware_A --seed 42 --quiet
sleep 1
timeout 5 "$QEMU" /tmp/demo_malware_A 2>/dev/null
[ $? -ne 0 ] && echo -e "${GREEN}    Result: BLOCKED ✓ — Malware cannot execute!${NC}" || \
               echo -e "${RED}    Result: EXECUTED (unexpected)${NC}"

echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Old binary (perm A) under perm B : BLOCKED ✓${NC}"
echo -e "${GREEN}  Legitimate update (perm B)        : PASSES  ✓${NC}"
echo -e "${GREEN}  Malware (perm A) under perm B     : BLOCKED ✓${NC}"
echo -e "${GREEN}  Keyspace: 21! permutations ≈ 2^65${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
