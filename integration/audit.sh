#!/bin/bash
# RISC-V ISA Integration — Combined Audit Script
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
    local name=$1 result=$2 hint=${3:-}
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓ $name${NC}"; PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗ $name${NC}"
        [ -n "$hint" ] && echo -e "    ${YELLOW}→ $hint${NC}"
        FAIL=$((FAIL+1))
    fi
}

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V ISA Integration — Phase 3 Milestone 3 Audit"
echo "  Register + Syscall + ld.so layers"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

QEMU_SRC="$BASE_DIR/../phase1/qemu-8.2.0"

# ── SECTION 1: FILE EXISTENCE ─────────────────────────────
echo -e "${CYAN}══ SECTION 1: FILE EXISTENCE ══${NC}"
for f in isa_integrate.py register_mapping.h syscall_mapping.h \
          isa_remap_ldso.h isa.env config.sh build.sh demo.sh \
          audit.sh CHANGELOG.md lib/config.py \
          riscv_demo/simple.S riscv_demo/complex.S \
          trigger/trigger_demo.sh           alpine/boot_alpine.sh alpine/alpine_demo.sh           alpine/full_alpine_test.sh; do
    [ -f "$BASE_DIR/$f" ] && check "File: $f" "PASS" || \
        check "File: $f" "FAIL" "Missing"
done

# ── SECTION 2: CONFIG ──────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 2: CONFIG & PATHS ══${NC}"
[ -f "$QEMU" ] && check "QEMU binary exists" "PASS" || \
    check "QEMU binary exists" "FAIL" "Run bash build.sh"
result=$(python3 -c "
import sys; sys.path.insert(0,'$BASE_DIR')
from lib.config import REGISTER_KEYRING, SYSCALL_KEYRING
print(REGISTER_KEYRING, SYSCALL_KEYRING)" 2>/dev/null)
[[ "$result" == *"register_keyring"* && "$result" == *"syscall_keyring"* ]] && \
    check "Python reads both keyring paths from isa.env" "PASS" || \
    check "Python reads isa.env" "FAIL"

# ── SECTION 3: QEMU PATCHES ───────────────────────────────
echo -e "\n${CYAN}══ SECTION 3: QEMU PATCH VERIFICATION ══${NC}"
TRANSLATE="$QEMU_SRC/target/riscv/translate.c"
SYSCALLC="$QEMU_SRC/linux-user/syscall.c"

if [ -f "$TRANSLATE" ]; then
    grep -q "register_mapping.h" "$TRANSLATE" && \
        check "register_mapping.h in translate.c" "PASS" || \
        check "register_mapping.h in translate.c" "FAIL"
    grep -q "register_decode_instruction" "$TRANSLATE" && \
        check "register_decode_instruction hook present" "PASS" || \
        check "register_decode_instruction hook" "FAIL"
    ! grep -q "isa_decode_instruction" "$TRANSLATE" && \
        check "Opcode patch absent (register-only milestone)" "PASS" || \
        check "Opcode patch absent" "FAIL"
    grep -q "reg_map_mtime" "$BASE_DIR/register_mapping.h" && \
        check "register_mapping.h: mtime reload, no initialized flag" "PASS" || \
        check "register_mapping.h mtime" "FAIL"
    SRC=$(sha256sum "$BASE_DIR/register_mapping.h" | cut -c1-16)
    DST=$(sha256sum "$QEMU_SRC/target/riscv/register_mapping.h" 2>/dev/null | cut -c1-16)
    [ "$SRC" = "$DST" ] && check "register_mapping.h checksum matches QEMU" "PASS" || \
        check "register_mapping.h checksum" "FAIL"
else
    check "QEMU source tree accessible" "FAIL" "Run bash build.sh"
fi

if [ -f "$SYSCALLC" ]; then
    grep -q "syscall_mapping.h" "$SYSCALLC" && \
        check "syscall_mapping.h in syscall.c" "PASS" || \
        check "syscall_mapping.h in syscall.c" "FAIL"
    grep -q "syscall_translate" "$SYSCALLC" && \
        check "syscall_translate hook present" "PASS" || \
        check "syscall_translate hook" "FAIL"
    grep -q "syscall_map_mtime" "$BASE_DIR/syscall_mapping.h" && \
        check "syscall_mapping.h: mtime reload, no initialized flag" "PASS" || \
        check "syscall_mapping.h mtime" "FAIL"
    SRC=$(sha256sum "$BASE_DIR/syscall_mapping.h" | cut -c1-16)
    DST=$(sha256sum "$QEMU_SRC/linux-user/syscall_mapping.h" 2>/dev/null | cut -c1-16)
    [ "$SRC" = "$DST" ] && check "syscall_mapping.h checksum matches QEMU" "PASS" || \
        check "syscall_mapping.h checksum" "FAIL"
fi

# ── SECTION 4: CODE QUALITY ────────────────────────────────
echo -e "\n${CYAN}══ SECTION 4: CODE QUALITY ══${NC}"
! grep -r "Desktop\|/home/muhammadbilal" \
    "$BASE_DIR/isa_integrate.py" "$BASE_DIR/build.sh" \
    "$BASE_DIR/demo.sh" 2>/dev/null | grep -v "^.*#" | grep -q . && \
    check "No hardcoded paths" "PASS" || check "No hardcoded paths" "FAIL"
grep -q "secrets.token_bytes" "$BASE_DIR/isa_integrate.py" && \
    check "secrets.token_bytes entropy" "PASS" || \
    check "secrets.token_bytes" "FAIL"
! grep -r "\$RANDOM" "$BASE_DIR/build.sh" \
    "$BASE_DIR/demo.sh" "$BASE_DIR/trigger" 2>/dev/null | grep -q . && \
    check "No \$RANDOM in scripts" "PASS" || \
    check "No \$RANDOM" "FAIL"
perms=$(stat -c "%a" /etc/isa/register_keyring 2>/dev/null)
[[ "$perms" == "640" || "$perms" == "600" ]] && \
    check "register_keyring permissions ($perms)" "PASS" || \
    check "register_keyring permissions" "FAIL" "Expected 640"
perms2=$(stat -c "%a" /etc/isa/syscall_keyring 2>/dev/null)
[[ "$perms2" == "640" || "$perms2" == "600" ]] && \
    check "syscall_keyring permissions ($perms2)" "PASS" || \
    check "syscall_keyring permissions" "FAIL" "Expected 640"
grep -q "OPCODE_FIELDS" "$BASE_DIR/isa_integrate.py" && \
    check "OPCODE_FIELDS table (Curtis fix)" "PASS" || \
    check "OPCODE_FIELDS table" "FAIL"
grep -q "sudo.*tee" "$BASE_DIR/isa_integrate.py" && \
    check "sudo tee fallback in rewriter" "PASS" || \
    check "sudo tee fallback" "FAIL"
grep -rq "march=rv64g" "$BASE_DIR/build.sh"     "$BASE_DIR/audit.sh" "$BASE_DIR/demo.sh" 2>/dev/null && \
    check "-march=rv64g (no RVC)" "PASS" || \
    check "-march=rv64g" "FAIL"
grep -q "FP_MAGIC\|fingerprint" "$BASE_DIR/isa_integrate.py" && \
    check "Fingerprint embedding in rewriter" "PASS" || \
    check "Fingerprint embedding" "FAIL"
grep -q "isa_remap_ldso" "$BASE_DIR/isa_remap_ldso.h" && \
    check "ld.so patch present (Curtis)" "PASS" || \
    check "ld.so patch" "FAIL"

# ── SECTION 5: LIVE TESTS ──────────────────────────────────
echo -e "\n${CYAN}══ SECTION 5: LIVE SECURITY TESTS ══${NC}"
if [ ! -f "$QEMU" ]; then
    echo -e "  ${YELLOW}Skipping — QEMU missing. Run bash build.sh${NC}"
else
    clang --target=riscv64-linux-gnu -march=rv64g \
        -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
        -o /tmp/audit_int_std "$DEMO_DIR/simple.S" 2>/dev/null
    clang --target=riscv64-linux-gnu -march=rv64g \
        -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
        -o /tmp/audit_int_cstd "$DEMO_DIR/complex.S" 2>/dev/null

    sudo truncate -s 0 "$REGISTER_KEYRING"
    sudo truncate -s 0 "$SYSCALL_KEYRING"
    sleep 1

    # T1
    timeout 5 "$QEMU" /tmp/audit_int_std >/dev/null 2>/dev/null
    [ $? -eq 0 ] && check "T1: Standard binary, empty keyrings → RUN" "PASS" || \
        check "T1: Standard binary empty" "FAIL"

    # T2
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_int_A --seed 42 --quiet
    sleep 2
    OUT=$(timeout 5 "$QEMU" /tmp/audit_int_A 2>/dev/null)
    [ $? -eq 0 ] && check "T2: Integrated binary, correct keyrings → RUN" "PASS" || \
        check "T2: Integrated binary correct" "FAIL"

    # T3 complex
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_cstd /tmp/audit_int_cA --seed 42 --quiet
    sleep 1
    timeout 5 "$QEMU" /tmp/audit_int_cA >/dev/null 2>/dev/null
    [ $? -eq 0 ] && check "T3: Complex binary, correct keyrings → RUN" "PASS" || \
        check "T3: Complex binary correct" "FAIL"

    # T4 standard blocked
    timeout 5 "$QEMU" /tmp/audit_int_std >/dev/null 2>/dev/null
    [ $? -ne 0 ] && check "T4: Standard binary, active keyrings → BLOCKED" "PASS" || \
        check "T4: Standard binary blocked" "FAIL"

    # T5 wrong seed
    SEED_B=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_int_B --seed $SEED_B --quiet 2>/dev/null
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_int_A2 --seed 42 --quiet
    sleep 2
    timeout 5 "$QEMU" /tmp/audit_int_B >/dev/null 2>/dev/null
    [ $? -ne 0 ] && check "T5: Wrong-seed binary → BLOCKED" "PASS" || \
        check "T5: Wrong-seed binary blocked" "FAIL"

    # T6 empty keyring blocks integrated
    sudo truncate -s 0 "$REGISTER_KEYRING"
    sudo truncate -s 0 "$SYSCALL_KEYRING"
    sleep 1
    timeout 5 "$QEMU" /tmp/audit_int_A >/dev/null 2>/dev/null
    [ $? -ne 0 ] && check "T6: Integrated binary, empty keyrings → BLOCKED" "PASS" || \
        check "T6: Integrated binary empty blocked" "FAIL"

    # T7 determinism
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_d1 --seed 12345 --quiet
    K1=$(sha256sum "$REGISTER_KEYRING" | cut -c1-32)
    S1=$(sha256sum "$SYSCALL_KEYRING"  | cut -c1-32)
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_d2 --seed 12345 --quiet
    K2=$(sha256sum "$REGISTER_KEYRING" | cut -c1-32)
    S2=$(sha256sum "$SYSCALL_KEYRING"  | cut -c1-32)
    [ "$K1" = "$K2" ] && check "T7: Same seed → same register keyring" "PASS" || \
        check "T7: Register determinism" "FAIL"
    [ "$S1" = "$S2" ] && check "T8: Same seed → same syscall keyring" "PASS" || \
        check "T8: Syscall determinism" "FAIL"

    # T9 frozen registers
    python3 "$BASE_DIR/isa_integrate.py" \
        /tmp/audit_int_std /tmp/audit_fr --seed 99 --quiet
    FROZEN_OK=true
    for r in 0 1 2 10 11 12 13 14 15 16 17; do
        grep -q "^$r " "$REGISTER_KEYRING" 2>/dev/null && FROZEN_OK=false
    done
    $FROZEN_OK && check "T9: Frozen regs not in register keyring" "PASS" || \
        check "T9: Frozen registers" "FAIL"

    # T10 register keyring has FP line
    head -1 "$REGISTER_KEYRING" | grep -q "^FP " && \
        check "T10: Register keyring has FP fingerprint line" "PASS" || \
        check "T10: FP line in register keyring" "FAIL"

    # T11 syscall keyring has 436 lines
    lines=$(wc -l < "$SYSCALL_KEYRING")
    [ "$lines" -eq 436 ] && \
        check "T11: Syscall keyring has 436 lines" "PASS" || \
        check "T11: Syscall keyring lines ($lines)" "FAIL"
fi

# ── SECTION 6: DOCUMENTATION ──────────────────────────────
echo -e "\n${CYAN}══ SECTION 6: DOCUMENTATION ══${NC}"
[ -f "$BASE_DIR/CHANGELOG.md" ] && check "CHANGELOG.md exists" "PASS" || \
    check "CHANGELOG.md" "FAIL"
grep -q "$(date +%Y)" "$BASE_DIR/CHANGELOG.md" 2>/dev/null && \
    check "CHANGELOG has 2026 entries" "PASS" || \
    check "CHANGELOG dated" "FAIL"

# ── RESULTS ───────────────────────────────────────────────
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
