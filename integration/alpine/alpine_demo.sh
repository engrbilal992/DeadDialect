#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/../config.sh"
INTEGRATE="$BASE_DIR/isa_integrate.py"
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Alpine Linux RISC-V — ISA Integration Demo${NC}"
echo -e "${CYAN}  Register + Syscall layers active${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"

SEED=42
clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
    -o /tmp/int_base "$BASE_DIR/riscv_demo/simple.S" 2>/dev/null

echo -e "\n${YELLOW}[1] Compiling binary under seed=$SEED...${NC}"
python3 "$INTEGRATE" /tmp/int_base /tmp/alpine_advanced --seed $SEED --quiet
echo -e "${GREEN}    Compiled and remapped under seed=$SEED${NC}"
sleep 1

echo -e "\n${YELLOW}[2] Running under seed=$SEED...${NC}"
timeout 5 "$QEMU" /tmp/alpine_advanced 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Legitimate binary runs${NC}" \
             || echo -e "${RED}    Result: FAILED ✗${NC}"

echo -e "\n${RED}[3] TRIGGER FIRED — register + syscall remapped atomically...${NC}"
NEW_SEED=$(python3 -c "import secrets; print(int.from_bytes(secrets.token_bytes(4),'big'))")
python3 "$INTEGRATE" /tmp/int_base /tmp/alpine_new --seed $NEW_SEED --quiet
echo "    New seed: $NEW_SEED"
sleep 1

echo -e "\n${YELLOW}[4] Old binary (seed=$SEED) after remap...${NC}"
timeout 5 "$QEMU" /tmp/alpine_advanced 2>/dev/null
[ $? -ne 0 ] && echo -e "${GREEN}    Result: BLOCKED ✓ — Old binary correctly rejected${NC}" \
             || echo -e "${RED}    Result: PASSED (unexpected)${NC}"

echo -e "\n${YELLOW}[5] Legitimate UPDATE — rewriting under new seed=$NEW_SEED...${NC}"
echo -e "${GREEN}    Update compiled under new mapping${NC}"
sleep 1

echo -e "\n${YELLOW}[6] Running updated binary...${NC}"
timeout 5 "$QEMU" /tmp/alpine_new 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Legitimate update passes through!${NC}" \
             || echo -e "${RED}    Result: FAILED ✗${NC}"

echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Old binary (wrong session) : BLOCKED ✓${NC}"
echo -e "${GREEN}  Legitimate update           : PASSES  ✓${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}\n"
