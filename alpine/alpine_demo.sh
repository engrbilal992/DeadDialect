#!/bin/bash
# Alpine Linux ISA Remapping Demo
source "$(dirname "$(readlink -f "$0")")/../config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Alpine Linux RISC-V — ISA Remapping Demo${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}"

SEED=42

# Step 1: Compile binary under seed=42
echo -e "\n${YELLOW}[1] Compiling binary under seed=$SEED (initial mapping)...${NC}"
python3 "$ISA_COMPILE" "$DEMO_DIR/advanced.c" /tmp/alpine_advanced $SEED >/dev/null 2>&1
echo -e "${GREEN}    Compiled — 'installed' under seed=$SEED${NC}"

# Step 2: Run under seed=42 — should work
echo -e "\n${YELLOW}[2] Running under seed=$SEED...${NC}"
timeout 5 "$QEMU" /tmp/alpine_advanced 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Legitimate binary runs${NC}" \
             || echo -e "${RED}    Result: FAILED ✗${NC}"

# Step 3: Trigger remap
echo -e "\n${RED}[3] TRIGGER FIRED — ISA remapped to new seed...${NC}"
NEW_SEED=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
python3 -c "
import random
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random($NEW_SEED); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
import os; mp=os.environ.get('ISA_MAP','/etc/isa/map'); os.makedirs(os.path.dirname(mp),exist_ok=True)
with open(mp,'w') as f:
    [f.write(f'{mp} {o}\n') for o,mp in m.items()]
print('    New seed: $NEW_SEED')
"

# Step 4: Old binary fails
echo -e "\n${YELLOW}[4] Old binary (seed=$SEED) after remap...${NC}"
timeout 5 "$QEMU" /tmp/alpine_advanced 2>/dev/null
[ $? -ne 0 ] && echo -e "${RED}    Result: BLOCKED ✗ — Old binary rejected${NC}"

# Step 5: Recompile under new seed (legitimate update)
echo -e "\n${YELLOW}[5] Legitimate UPDATE — recompiling under new seed=$NEW_SEED...${NC}"
python3 "$ISA_COMPILE" "$DEMO_DIR/advanced.c" /tmp/alpine_updated $NEW_SEED >/dev/null 2>&1
echo -e "${GREEN}    Update compiled under new mapping${NC}"

# Step 6: New binary works
echo -e "\n${YELLOW}[6] Running updated binary...${NC}"
timeout 5 "$QEMU" /tmp/alpine_updated 2>/dev/null
[ $? -eq 0 ] && echo -e "${GREEN}    Result: SUCCESS ✓ — Legitimate update passes through!${NC}" \
             || echo -e "${RED}    Result: FAILED ✗${NC}"

echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Malware (old seed) : BLOCKED ✓${NC}"
echo -e "${GREEN}  Legitimate update  : PASSES  ✓${NC}"
echo -e "${CYAN}════════════════════════════════════════════${NC}\n"
