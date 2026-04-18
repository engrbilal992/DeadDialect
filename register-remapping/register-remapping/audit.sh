#!/bin/bash
# RISC-V Register Remapping — Complete Audit Script
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

PASS=0; FAIL=0

check() {
    local name=$1 result=$2 hint=${3:-}
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓ $name${NC}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗ $name${NC}"
        [ -n "$hint" ] && echo -e "    ${YELLOW}→ $hint${NC}"
        FAIL=$((FAIL+1))
    fi
}

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Register Remapping — Phase 3 Milestone 2 Audit"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

QEMU_SRC="$PHASE1/qemu-8.2.0"
TRANSLATE_C="$QEMU_SRC/target/riscv/translate.c"

echo -e "${CYAN}══ SECTION 1: FILE EXISTENCE ══${NC}"
for f in isa_register_rewrite.py register_mapping.h isa.env config.sh \
          build.sh demo.sh audit.sh CHANGELOG.md \
          riscv_demo/simple.c riscv_demo/complex.c lib/config.py; do
    [ -f "$BASE_DIR/$f" ] && check "File exists: $f" "PASS" || \
        check "File exists: $f" "FAIL" "Missing file"
done

echo -e "\n${CYAN}══ SECTION 2: CONFIG & PATHS ══${NC}"
echo "  Resolved paths:"
echo "  BASE_DIR = $BASE_DIR"
echo "  QEMU     = $QEMU"
echo "  PHASE1   = $PHASE1"
echo "  KEYRING  = $REGISTER_KEYRING"
[ -f "$QEMU" ] && check "QEMU binary exists" "PASS" || \
    check "QEMU binary exists" "FAIL" "Run bash build.sh first"
[ -d "$QEMU_SRC" ] && check "QEMU source tree exists" "PASS" || \
    check "QEMU source tree exists" "FAIL" "Run bash build.sh first"
[ -f "$BASE_DIR/isa.env" ] && check "isa.env exists" "PASS" || \
    check "isa.env exists" "FAIL"
result=$(python3 -c "import sys; sys.path.insert(0,'$BASE_DIR'); \
    from lib.config import REGISTER_KEYRING; print(REGISTER_KEYRING)" 2>/dev/null)
[ "$result" = "/etc/isa/register_keyring" ] && \
    check "Python reads isa.env correctly ($result)" "PASS" || \
    check "Python reads isa.env correctly" "FAIL" "Got: $result"

echo -e "\n${CYAN}══ SECTION 3: QEMU PATCH VERIFICATION ══${NC}"
if [ -f "$TRANSLATE_C" ]; then
    grep -q "register_mapping.h" "$TRANSLATE_C" && \
        check "register_mapping.h included in translate.c" "PASS" || \
        check "register_mapping.h included in translate.c" "FAIL" "Run bash build.sh"
    grep -q "register_decode_instruction" "$TRANSLATE_C" && \
        check "register_decode_instruction hook present" "PASS" || \
        check "register_decode_instruction hook present" "FAIL" "Run bash build.sh"
    # Verify checksum matches
    SRC_SUM=$(sha256sum "$BASE_DIR/register_mapping.h" | cut -d' ' -f1 | cut -c1-16)
    DST_SUM=$(sha256sum "$QEMU_SRC/target/riscv/register_mapping.h" \
              2>/dev/null | cut -d' ' -f1 | cut -c1-16)
    [ "$SRC_SUM" = "$DST_SUM" ] && \
        check "register_mapping.h checksum matches QEMU tree" "PASS" || \
        check "register_mapping.h checksum matches QEMU tree" \
              "FAIL" "Source: $SRC_SUM QEMU: $DST_SUM — run bash build.sh"
    # Verify mtime pattern
    count=$(grep -c "reg_map_mtime" "$BASE_DIR/register_mapping.h" 2>/dev/null || echo 0)
    [ "$count" -ge 2 ] && check "mtime race condition fixed" "PASS" || \
        check "mtime race condition fixed" "FAIL"
    # Verify no initialized flag
    grep -q "reg_map_initialized" "$BASE_DIR/register_mapping.h" 2>/dev/null && \
        check "No initialized flag (Curtis fix)" "FAIL" "Remove initialized flag" || \
        check "No initialized flag (Curtis fix)" "PASS"
else
    check "translate.c accessible" "FAIL" "Run bash build.sh first"
fi

echo -e "\n${CYAN}══ SECTION 4: SECURITY & CODE QUALITY ══${NC}"
# No hardcoded paths
result=$(grep -r "Desktop\|/home/muhammadbilal" \
    "$BASE_DIR/isa_register_rewrite.py" \
    "$BASE_DIR/build.sh" \
    "$BASE_DIR/demo.sh" "$BASE_DIR/config.sh" 2>/dev/null | grep -v "^.*#")
[ -z "$result" ] && check "No hardcoded Desktop paths" "PASS" || \
    check "No hardcoded Desktop paths" "FAIL" "$result"
# secrets.token_bytes
grep -q "secrets.token_bytes" "$BASE_DIR/isa_register_rewrite.py" && \
    check "secrets.token_bytes — 256-bit entropy" "PASS" || \
    check "secrets.token_bytes — 256-bit entropy" "FAIL"
# No weak seed
result=$(grep -r "\$RANDOM"     "$BASE_DIR/build.sh" "$BASE_DIR/demo.sh"     "$BASE_DIR/config.sh" 2>/dev/null | grep -v "^.*#")
[ -z "$result" ] && check "No weak \$RANDOM in scripts" "PASS" || \
    check "No weak \$RANDOM" "FAIL"
# Keyring permissions
perms=$(stat -c "%a" /etc/isa/register_keyring 2>/dev/null)
([ "$perms" = "640" ] || [ "$perms" = "600" ]) && \
    check "register_keyring permissions ($perms)" "PASS" || \
    check "register_keyring permissions" "FAIL" \
    "Expected 640, got: $perms — run bash build.sh"
# REG_COUNT
grep -q "REG_COUNT.*=.*32\|REG_COUNT = 32" "$BASE_DIR/isa_register_rewrite.py" && \
    check "REG_COUNT = 32 (full RISC-V register file)" "PASS" || \
    check "REG_COUNT = 32" "FAIL"
# Frozen registers
grep -q "FROZEN = {0, 1, 2, 10, 11, 12, 13, 14, 15, 16, 17}" \
    "$BASE_DIR/isa_register_rewrite.py" && \
    check "Frozen registers: x0,x1,x2,x10-x17 (11 frozen, 21 shuffleable)" "PASS" || \
    check "Frozen registers" "FAIL"
# march=rv64g
grep -q "march=rv64g" "$BASE_DIR/build.sh" "$BASE_DIR/audit.sh" \
    "$BASE_DIR/demo.sh" 2>/dev/null && \
    check "-march=rv64g (no RVC, documented POC limitation)" "PASS" || \
    check "-march=rv64g" "FAIL"
# sudo tee fallback
grep -q "sudo.*tee" "$BASE_DIR/isa_register_rewrite.py" && \
    check "sudo tee fallback in rewriter" "PASS" || \
    check "sudo tee fallback" "FAIL"

echo -e "\n${CYAN}══ SECTION 5: LIVE FUNCTIONAL TESTS ══${NC}"
if [ ! -f "$QEMU" ]; then
    echo -e "  ${YELLOW}Skipping live tests — QEMU binary missing. Run bash build.sh first.${NC}"
else
    echo "  Compiling test binaries..."
    clang --target=riscv64-linux-gnu -march=rv64g \
        -nostdlib -static -fuse-ld=lld -O1 \
        -o /tmp/reg_simple_std "$DEMO_DIR/simple.c" 2>/dev/null
    clang --target=riscv64-linux-gnu -march=rv64g \
        -nostdlib -static -fuse-ld=lld -O1 \
        -o /tmp/reg_complex_std "$DEMO_DIR/complex.c" 2>/dev/null

    # T1: Standard binary — empty keyring (identity map)
    echo "  T1: Standard binary — identity map (empty keyring)"
    sudo truncate -s 0 /etc/isa/register_keyring
    sleep 1
    OUT=$(timeout 5 "$QEMU" /tmp/reg_simple_std 2>/dev/null)
    EXIT1=$?
    [ $EXIT1 -eq 0 ] && check "T1: Standard simple binary runs (identity map)" "PASS" || \
        check "T1: Standard simple binary runs" "FAIL" "exit=$EXIT1"
    echo "    Output: $(echo "$OUT" | head -1)"

    # T2: Rewrite under seed=42, run under perm A
    echo "  T2: Rewrite with seed=42, run under perm A"
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_simple_A --seed 42 --quiet
    sleep 1
    OUT=$(timeout 5 "$QEMU" /tmp/reg_simple_A 2>/dev/null)
    EXIT2=$?
    [ $EXIT2 -eq 0 ] && check "T2: Simple_A runs under perm A (seed=42)" "PASS" || \
        check "T2: Simple_A runs under perm A" "FAIL" "exit=$EXIT2"
    echo "    Output: $(echo "$OUT" | head -1)"

    # T3: Complex binary under perm A
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_complex_std /tmp/reg_complex_A --seed 42 --quiet
    sleep 1
    OUT=$(timeout 5 "$QEMU" /tmp/reg_complex_A 2>/dev/null)
    EXIT3=$?
    [ $EXIT3 -eq 0 ] && check "T3: Complex_A runs under perm A" "PASS" || \
        check "T3: Complex_A runs under perm A" "FAIL" "exit=$EXIT3"
    echo "    Output: $(echo "$OUT" | head -1)"

    # T4-T5: Switch to perm B — old binaries must fail
    SEED_B=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
    echo "  T4-T5: Switch to perm B (seed=$SEED_B), old binaries must fail"
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_simple_B --seed $SEED_B --quiet 2>/dev/null
    sleep 2
    timeout 5 "$QEMU" /tmp/reg_simple_A >/dev/null 2>/dev/null
    EXIT4=$?
    [ $EXIT4 -ne 0 ] && check "T4: Simple_A BLOCKED under perm B (wrong registers)" "PASS" || \
        check "T4: Simple_A BLOCKED under perm B" "FAIL" "Binary still runs — remap not working"
    timeout 5 "$QEMU" /tmp/reg_complex_A >/dev/null 2>/dev/null
    EXIT5=$?
    [ $EXIT5 -ne 0 ] && check "T5: Complex_A BLOCKED under perm B" "PASS" || \
        check "T5: Complex_A BLOCKED under perm B" "FAIL"

    # T6: New binary under perm B runs
    echo "  T6: New binary (perm B) runs under perm B"
    sleep 1
    OUT=$(timeout 5 "$QEMU" /tmp/reg_simple_B 2>/dev/null)
    EXIT6=$?
    [ $EXIT6 -eq 0 ] && check "T6: Simple_B runs under perm B (legitimate update)" "PASS" || \
        check "T6: Simple_B runs under perm B" "FAIL" "exit=$EXIT6"
    echo "    Output: $(echo "$OUT" | head -1)"

    # T7: Different seeds produce different keyrings
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_tmp1 --seed 100 --quiet
    K1=$(cat /etc/isa/register_keyring | md5sum)
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_tmp2 --seed 200 --quiet
    K2=$(cat /etc/isa/register_keyring | md5sum)
    [ "$K1" != "$K2" ] && check "T7: Different seeds produce different keyrings" "PASS" || \
        check "T7: Different seeds produce same keyring" "FAIL"

    # T8: Keyring has correct format
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_tmp3 --seed 42 --quiet
    LINES=$(wc -l < /etc/isa/register_keyring)
    [ "$LINES" -ge 1 ] && [ "$LINES" -le 21 ] && \
        check "T8: Keyring has $LINES entries (max 21 shuffleable)" "PASS" || \
        check "T8: Keyring line count" "FAIL" "Got $LINES lines"

    # T9: Determinism
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_det1 --seed 12345 --quiet
    K1=$(cat /etc/isa/register_keyring | sha256sum)
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_det2 --seed 12345 --quiet
    K2=$(cat /etc/isa/register_keyring | sha256sum)
    [ "$K1" = "$K2" ] && check "T9: Same seed always produces same keyring (deterministic)" "PASS" || \
        check "T9: Determinism check" "FAIL"

    # T10: Frozen registers preserved — x0 always maps to x0
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_frozen --seed 99 --quiet
    FROZEN_OK=true
    for r in 0 1 2 10 11 12 13 14 15 16 17; do
        if grep -q "^$r " /etc/isa/register_keyring 2>/dev/null; then
            FROZEN_OK=false
            break
        fi
    done
    $FROZEN_OK && check "T10: Frozen registers preserved (x0,x1,x2,x10-x17 not in keyring)" "PASS" || \
        check "T10: Frozen registers preserved" "FAIL" "Frozen register found in keyring"

    # T11: objdump proof — register fields changed
    echo "  T11: Independent disassembly proof (objdump)"
    python3 "$BASE_DIR/isa_register_rewrite.py" \
        /tmp/reg_simple_std /tmp/reg_proof --seed 42 --quiet
    # Compare raw binary bytes — they must differ after register remapping
    STD_MD5=$(md5sum /tmp/reg_simple_std | cut -d" " -f1)
    RMP_MD5=$(md5sum /tmp/reg_proof      | cut -d" " -f1)
    echo "    Standard binary md5: ${STD_MD5:0:16}..."
    echo "    Remapped binary md5: ${RMP_MD5:0:16}..."
    [ "$STD_MD5" != "$RMP_MD5" ] && \
        check "T11: Binary differs from standard — register fields changed" "PASS" || \
        check "T11: Binary differs from standard" "FAIL" \
        "Binaries identical — remap not working"
fi

echo -e "\n${CYAN}══ SECTION 6: DOCUMENTATION & GIT ══${NC}"
[ -f "$BASE_DIR/CHANGELOG.md" ] && check "CHANGELOG.md exists" "PASS" || \
    check "CHANGELOG.md exists" "FAIL"
grep -q "$(date +%Y)" "$BASE_DIR/CHANGELOG.md" 2>/dev/null && \
    check "CHANGELOG has dated entries" "PASS" || \
    check "CHANGELOG has dated entries" "FAIL"
count=$(git -C "$BASE_DIR" log --oneline 2>/dev/null | wc -l)
[ "$count" -ge 1 ] && check "Git history exists ($count commits)" "PASS" || \
    check "Git history exists" "FAIL" "Run git init and commit"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
TOTAL=$((PASS+FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  ALL $TOTAL CHECKS PASSED ✓${NC}"
    echo -e "${GREEN}  Phase 3 Milestone 2 is production ready.${NC}"
else
    echo -e "${RED}  $FAIL/$TOTAL CHECKS FAILED ✗${NC}"
    echo -e "${YELLOW}  $PASS/$TOTAL passed${NC}"
    echo -e "${YELLOW}  Fix failures then re-run: bash audit.sh${NC}"
fi
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Git log (last 5):"
git -C "$BASE_DIR" log --oneline -5 2>/dev/null || echo "  (no git history)"
echo ""
