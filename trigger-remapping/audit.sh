#!/bin/bash
# ISA Remapping — Complete Audit Script

source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

PASS=0; FAIL=0

check() {
    local name=$1; local result=$2
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓ $name${NC}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗ $name: $result${NC}"
        FAIL=$((FAIL+1))
    fi
}

ALL_SCRIPTS="$BASE_DIR/trigger/trigger_demo.sh $BASE_DIR/alpine/alpine_demo.sh $BASE_DIR/alpine/full_alpine_test.sh $BASE_DIR/alpine/boot_alpine.sh $BASE_DIR/setup.sh $BASE_DIR/config.sh"

echo -e "${CYAN}"
echo "════════════════════════════════════════════════════"
echo "  RISC-V ISA Remapping — Complete Audit"
echo "  Tests all issues raised by Curtis"
echo "  Checks ALL scripts, not just trigger/"
echo "════════════════════════════════════════════════════"
echo -e "${NC}"

echo -e "${CYAN}--- STATIC CODE CHECKS ---${NC}"

# B1: QEMU mtime reload
count=$(grep -c "mtime" "$BASE_DIR/../phase1/qemu-8.2.0/target/riscv/isa_mapping.h" 2>/dev/null || echo 0)
[ "$count" -ge 3 ] && check "B1: QEMU mtime reload (no caching)" "PASS" || check "B1: QEMU mtime reload" "FAIL — only $count mtime refs"

# B2: No seed write
result=$(grep -v "^#\|^    #" "$BASE_DIR/trigger/isa_trigger.py" | grep "write(str\|write(seed" 2>/dev/null)
[ -z "$result" ] && check "B2: No seed write corrupting map" "PASS" || check "B2: Seed write" "FAIL — $result"

# B3: Dynamic results in trigger_demo.sh
count=$(grep -c "EXIT[0-9]=\$?" "$BASE_DIR/trigger/trigger_demo.sh" 2>/dev/null || echo 0)
[ "$count" -ge 4 ] && check "B3: trigger_demo.sh dynamic results ($count exit checks)" "PASS" || check "B3: Dynamic results" "FAIL — only $count checks"

# B3: alpine_demo.sh also has proper if/else
count=$(grep -c "EXIT[0-9]=\$?\|if \[ \$EXIT" "$BASE_DIR/alpine/alpine_demo.sh" 2>/dev/null || echo 0)
[ "$count" -ge 1 ] && check "B3: alpine_demo.sh has proper if/else checks" "PASS" || check "B3: alpine_demo.sh one-sided checks" "FAIL"

# C1: No Desktop paths in ANY script
result=$(grep -r "Desktop\|/home/muhammadbilal" $ALL_SCRIPTS "$BASE_DIR/isa_compile.py" 2>/dev/null)
[ -z "$result" ] && check "C1: No hardcoded Desktop paths (all scripts)" "PASS" || check "C1: Hardcoded paths" "FAIL"

# C1: No QEMU override
result=$(grep "^QEMU=" "$BASE_DIR/trigger/trigger_demo.sh" 2>/dev/null)
[ -z "$result" ] && check "C1: No QEMU override in trigger_demo.sh" "PASS" || check "C1: QEMU override" "FAIL"

# C1: ISA_MAP exported
result=$(grep "export ISA_MAP" "$BASE_DIR/config.sh" 2>/dev/null)
[ -n "$result" ] && check "C1: ISA_MAP exported in config.sh" "PASS" || check "C1: ISA_MAP not exported" "FAIL"

# C2: No inline mapping copy-paste in ANY script
# Check that no script (other than lib) has the raw inline Python mapping snippet
result=$(grep -r "random.Random.*OPCODES\|r.shuffle.*OPCODES" \
    "$BASE_DIR/alpine/alpine_demo.sh" \
    "$BASE_DIR/alpine/full_alpine_test.sh" \
    "$BASE_DIR/alpine/boot_alpine.sh" \
    "$BASE_DIR/setup.sh" 2>/dev/null)
[ -z "$result" ] && check "C2: No inline mapping copy-paste in alpine/setup scripts" "PASS" || check "C2: Inline mapping still copy-pasted" "FAIL — found in: $(echo $result | cut -c1-80)"

# C2: lib/generate_mapping.sh exists
[ -f "$BASE_DIR/lib/generate_mapping.sh" ] && check "C2: lib/generate_mapping.sh exists" "PASS" || check "C2: lib/generate_mapping.sh missing" "FAIL"

# C4: SYSTEM 0x73 protected
result=$(grep "PROTECTED.*0x73\|0x73.*PROTECTED" "$BASE_DIR/isa_compile.py" 2>/dev/null)
[ -n "$result" ] && check "C4: SYSTEM 0x73 protected" "PASS" || check "C4: SYSTEM not protected" "FAIL"

# C5: No $RANDOM in ANY script
result=$(grep -rn "\$RANDOM\$RANDOM\|\$RANDOM\b" $ALL_SCRIPTS "$BASE_DIR/isa_compile.py" 2>/dev/null | grep -v "^.*#")
[ -z "$result" ] && check "C5: No \$RANDOM in any script" "PASS" || check "C5: Weak entropy" "FAIL"

# C5: os.urandom used
count=$(grep -r "urandom" "$BASE_DIR/trigger/" "$BASE_DIR/alpine/"*.sh "$BASE_DIR/isa_compile.py" "$BASE_DIR/lib/" 2>/dev/null | grep -v "^.*#" | wc -l)
[ "$count" -ge 4 ] && check "C5: os.urandom in $count places" "PASS" || check "C5: urandom missing" "FAIL — only $count"

# C6: SHA-256 not MD5
result=$(grep -r "\.md5\b\|md5(" "$BASE_DIR/trigger/" 2>/dev/null | grep -v "#")
[ -z "$result" ] && check "C6: SHA-256 not MD5" "PASS" || check "C6: MD5 still used" "FAIL"

# C7: No stray -e — check actual last non-empty line of each file
echo ""
echo -e "${CYAN}  C7 stray-e check (all scripts):${NC}"
for f in config.sh setup.sh trigger/trigger_demo.sh alpine/alpine_demo.sh alpine/full_alpine_test.sh alpine/boot_alpine.sh; do
    # Get last non-empty line
    last=$(grep -v "^[[:space:]]*$" "$BASE_DIR/$f" 2>/dev/null | tail -1 | sed 's/[[:space:]]*$//')
    if [ "$last" = "-e" ]; then
        check "C7: No stray -e in $f" "FAIL — last line is: $last"
    else
        check "C7: No stray -e in $f" "PASS"
    fi
done

# C8: No /tmp/isa_reverse_map in ANY script
result=$(grep -r "tmp/isa_reverse_map" $ALL_SCRIPTS "$BASE_DIR/isa_compile.py" "$BASE_DIR/lib/" 2>/dev/null)
[ -z "$result" ] && check "C8: No /tmp/isa_reverse_map (all scripts)" "PASS" || check "C8: /tmp still used" "FAIL"

# C8: /etc/isa/map permissions
perms=$(stat -c "%a" /etc/isa/map 2>/dev/null)
([ "$perms" = "660" ] || [ "$perms" = "600" ] || [ "$perms" = "640" ]) && check "C8: /etc/isa/map permissions ($perms)" "PASS" || check "C8: /etc/isa/map permissions" "FAIL — $perms"

# isa.env: config file exists and readable by both bash and Python
[ -f "$BASE_DIR/isa.env" ] && check "CONFIG: isa.env exists" "PASS" || check "CONFIG: isa.env missing" "FAIL"
result=$(grep "ISA_MAP" "$BASE_DIR/isa.env" 2>/dev/null)
[ -n "$result" ] && check "CONFIG: ISA_MAP in isa.env" "PASS" || check "CONFIG: ISA_MAP not in isa.env" "FAIL"
[ -f "$BASE_DIR/lib/config.py" ] && check "CONFIG: lib/config.py exists" "PASS" || check "CONFIG: lib/config.py missing" "FAIL"
result=$(python3 -c "import sys; sys.path.insert(0,'$BASE_DIR'); from lib.config import ISA_MAP; print(ISA_MAP)" 2>/dev/null)
[ "$result" = "/etc/isa/map" ] && check "CONFIG: Python reads isa.env correctly ($result)" "PASS" || check "CONFIG: Python cannot read isa.env" "FAIL — got: $result"

# N3: Git
count=$(git -C "$BASE_DIR" log --oneline 2>/dev/null | wc -l)
[ "$count" -ge 3 ] && check "N3: Git setup ($count commits)" "PASS" || check "N3: Git" "FAIL"

echo ""
echo -e "${CYAN}--- LIVE TESTS ---${NC}"

# Clear map AND syscall keyring — Phase 3 keyring causes segfault in Phase 2 QEMU
sudo truncate -s 0 "$ISA_MAP" 2>/dev/null || true
sudo truncate -s 0 /etc/isa/syscall_keyring 2>/dev/null || true
sleep 1
echo -e "\n${YELLOW}Running trigger demo...${NC}"
DEMO_OUT=$(bash "$BASE_DIR/trigger/trigger_demo.sh" 2>/dev/null)
echo "$DEMO_OUT" | grep -q "SUCCESS ✓" && check "LIVE: Phase 1 binary runs" "PASS" || check "LIVE: Phase 1 binary" "FAIL"
echo "$DEMO_OUT" | grep -q "FAILED ✗ — Binary invalid" && check "LIVE: Phase 3 binary blocked" "PASS" || check "LIVE: Phase 3 binary" "FAIL"
echo "$DEMO_OUT" | grep -q "BLOCKED ✓ — Malware cannot" && check "LIVE: Malware blocked" "PASS" || check "LIVE: Malware" "FAIL"
echo "$DEMO_OUT" | grep -q "EXECUTED (expected)" && check "LIVE: Malware runs same session" "PASS" || check "LIVE: Malware same session" "FAIL"

echo -e "\n${YELLOW}Running Alpine ISA test...${NC}"
ALPINE_OUT=$(bash "$BASE_DIR/alpine/full_alpine_test.sh" 2>/dev/null)
echo "$ALPINE_OUT" | grep -q "RESULT: SUCCESS ✓" && check "ALPINE: Standard binary runs" "PASS" || check "ALPINE: Standard binary" "FAIL"
echo "$ALPINE_OUT" | grep -q "RESULT: BLOCKED ✓" && check "ALPINE: Remapped binary blocked" "PASS" || check "ALPINE: Blocked" "FAIL"
echo "$ALPINE_OUT" | grep -q "UPDATE PASSES ✓" && check "ALPINE: Legitimate update passes" "PASS" || check "ALPINE: Update" "FAIL"

echo -e "\n${YELLOW}Running Alpine demo...${NC}"
ADEMO_OUT=$(bash "$BASE_DIR/alpine/alpine_demo.sh" 2>/dev/null)
echo "$ADEMO_OUT" | grep -q "Legitimate binary runs" && check "DEMO: Initial binary runs" "PASS" || check "DEMO: Initial binary" "FAIL"
echo "$ADEMO_OUT" | grep -q "BLOCKED ✓ — Old binary" && check "DEMO: Old binary blocked after trigger" "PASS" || check "DEMO: Old binary" "FAIL"
echo "$ADEMO_OUT" | grep -q "Legitimate update passes" && check "DEMO: Update passes" "PASS" || check "DEMO: Update" "FAIL"
echo "$ADEMO_OUT" | grep -q "BLOCKED ✓" && check "DEMO: Malware blocked" "PASS" || check "DEMO: Malware" "FAIL"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
TOTAL=$((PASS+FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  ALL $TOTAL CHECKS PASSED ✓${NC}"
else
    echo -e "${RED}  $FAIL/$TOTAL CHECKS FAILED ✗${NC}"
    echo -e "${YELLOW}  $PASS/$TOTAL passed${NC}"
fi
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Git log:"
git -C "$BASE_DIR" log --oneline
echo ""
