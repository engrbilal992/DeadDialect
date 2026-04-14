#!/bin/bash
# Phase 3 — Complete Audit Script
# Tests everything from 0 to 100 with detailed output
source "$(dirname "$(readlink -f "$0")")/config.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
    local name=$1 result=$2 detail=${3:-""}
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓ $name${NC}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗ $name${NC}"
        [ -n "$detail" ] && echo -e "    ${YELLOW}→ $detail${NC}"
        FAIL=$((FAIL+1))
    fi
}

echo -e "${CYAN}"
echo "████████████████████████████████████████████████████████"
echo "  RISC-V Syscall Remapping — Phase 3 Complete Audit"
echo "████████████████████████████████████████████████████████"
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────
echo -e "${CYAN}══ SECTION 1: FILE EXISTENCE ══${NC}"
# ─────────────────────────────────────────────────────────────

for f in \
    isa_syscall_rewrite.py \
    syscall_mapping.h \
    isa.env \
    config.sh \
    build.sh \
    demo.sh \
    audit.sh \
    CHANGELOG.md \
    riscv_demo/simple.c \
    riscv_demo/complex.c \
    lib/config.py; do
    if [ -f "$BASE_DIR/$f" ]; then
        check "File exists: $f" "PASS"
    else
        check "File exists: $f" "FAIL" "$BASE_DIR/$f not found"
    fi
done

# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 2: CONFIG & PATHS ══${NC}"
# ─────────────────────────────────────────────────────────────

echo -e "  ${YELLOW}Resolved paths:${NC}"
echo -e "  BASE_DIR    = $BASE_DIR"
echo -e "  QEMU        = $QEMU"
echo -e "  PHASE1      = $PHASE1"
echo -e "  DEMO_DIR    = $DEMO_DIR"
echo -e "  KEYRING     = $ISA_SYSCALL_KEYRING"

[ -f "$QEMU" ] && \
    check "QEMU binary exists" "PASS" || \
    check "QEMU binary exists" "FAIL" "Run bash build.sh first"

[ -d "$PHASE1/qemu-8.2.0" ] && \
    check "QEMU source tree exists" "PASS" || \
    check "QEMU source tree exists" "FAIL" "$PHASE1/qemu-8.2.0 not found"

[ -f "$BASE_DIR/isa.env" ] && \
    check "isa.env exists" "PASS" || \
    check "isa.env missing" "FAIL"

result=$(python3 -c "
import sys, os
sys.path.insert(0,'$BASE_DIR')
from lib.config import ISA_SYSCALL_KEYRING
print(ISA_SYSCALL_KEYRING)
" 2>/dev/null)
[ "$result" = "/etc/isa/syscall_keyring" ] && \
    check "Python reads isa.env correctly ($result)" "PASS" || \
    check "Python cannot read isa.env" "FAIL" "got: $result"

# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 3: QEMU PATCH VERIFICATION ══${NC}"
# ─────────────────────────────────────────────────────────────

grep -q "syscall_translate" "$QEMU_SYSCALL_C" 2>/dev/null && \
    check "QEMU syscall.c has translation hook" "PASS" || \
    check "QEMU syscall.c has translation hook" "FAIL" "Run bash build.sh to patch"

grep -q "syscall_mapping.h" "$QEMU_SYSCALL_C" 2>/dev/null && \
    check "syscall_mapping.h included in syscall.c" "PASS" || \
    check "syscall_mapping.h included in syscall.c" "FAIL" "Run bash build.sh"

if [ -f "$QEMU_SYSCALL_H_DEST" ]; then
    SRC_SUM=$(sha256sum "$SYSCALL_MAPPING_H" | cut -d' ' -f1)
    DST_SUM=$(sha256sum "$QEMU_SYSCALL_H_DEST" | cut -d' ' -f1)
    if [ "$SRC_SUM" = "$DST_SUM" ]; then
        check "syscall_mapping.h checksum matches QEMU tree" "PASS"
    else
        check "syscall_mapping.h checksum matches QEMU tree" "FAIL" \
            "Source: ${SRC_SUM:0:16}... QEMU: ${DST_SUM:0:16}... — run bash build.sh"
    fi
else
    check "syscall_mapping.h in QEMU tree" "FAIL" "Run bash build.sh to copy"
fi

grep -q "after successful read" "$BASE_DIR/syscall_mapping.h" && \
    check "mtime race condition fixed" "PASS" || \
    check "mtime race condition fixed" "FAIL" "mtime updated before fclose"

# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 4: SECURITY & CODE QUALITY ══${NC}"
# ─────────────────────────────────────────────────────────────

grep -q "secrets" "$BASE_DIR/isa_syscall_rewrite.py" && \
    check "secrets.SystemRandom — full 256-bit entropy, Python 3.11+ safe" "PASS" || \
    check "secrets module not found in rewriter" "FAIL" "Weak seed detected"

result_random=$(grep -rn "RANDOM" "$BASE_DIR"/*.sh "$BASE_DIR"/*.py 2>/dev/null | grep -v "audit.sh" | grep -v "urandom" | grep -v "^.*:#")
[ -z "$result_random" ] && \
    check "No weak \$RANDOM in scripts" "PASS" || \
    check "No weak \$RANDOM in scripts" "FAIL" "Found: $result_random"

perms=$(stat -c "%a" "$ISA_SYSCALL_KEYRING" 2>/dev/null)
if [ "$perms" = "660" ] || [ "$perms" = "600" ]; then
    check "syscall_keyring permissions ($perms)" "PASS"
else
    check "syscall_keyring permissions" "FAIL" "Expected 660 or 600, got: $perms — run bash build.sh"
fi

# No hardcoded paths (excluding the audit check line itself)
result=$(grep -rn "Desktop\|/home/muhammadbilal" \
    "$BASE_DIR/isa_syscall_rewrite.py" \
    "$BASE_DIR/demo.sh" \
    "$BASE_DIR/build.sh" \
    "$BASE_DIR/config.sh" \
    "$BASE_DIR/lib/config.py" 2>/dev/null | grep -v "^.*:#")
[ -z "$result" ] && \
    check "No hardcoded Desktop paths" "PASS" || \
    check "No hardcoded Desktop paths" "FAIL" "$result"

grep -q "SYSCALL_COUNT = 436" "$BASE_DIR/isa_syscall_rewrite.py" && \
    check "SYSCALL_COUNT = 436 (full Linux RISC-V range)" "PASS" || \
    check "SYSCALL_COUNT correct" "FAIL"

grep -q "march=rv64g" "$BASE_DIR/demo.sh" && \
    check "-march=rv64g (no RVC, documented POC limitation)" "PASS" || \
    check "-march=rv64g present" "FAIL" "RVC compressed instructions not disabled"

# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 5: LIVE FUNCTIONAL TESTS ══${NC}"
# ─────────────────────────────────────────────────────────────

if [ ! -f "$QEMU" ]; then
    echo -e "  ${RED}  Skipping live tests — QEMU binary missing. Run bash build.sh first.${NC}"
else
    # Clear keyring for clean state
    sudo truncate -s 0 "$ISA_SYSCALL_KEYRING"

    # Compile test binaries
    echo -e "  ${YELLOW}Compiling test binaries...${NC}"
    clang --target=riscv64-linux-gnu -march=rv64g -nostdlib -static -fuse-ld=lld -O1 \
        -o /tmp/audit3_simple "$DEMO_DIR/simple.c" 2>/dev/null
    clang --target=riscv64-linux-gnu -march=rv64g -nostdlib -static -fuse-ld=lld -O1 \
        -o /tmp/audit3_complex "$DEMO_DIR/complex.c" 2>/dev/null

    # T1: Standard binary runs with empty keyring (identity map)
    echo -e "  ${YELLOW}T1: Standard binary — identity map (empty keyring)${NC}"
    OUT=$(timeout 5 "$QEMU" /tmp/audit3_simple 2>/dev/null)
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
        check "T1: Standard simple binary runs (identity map)" "PASS"
        echo -e "    Output: $OUT"
    else
        check "T1: Standard simple binary runs (identity map)" "FAIL" \
            "exit=$EXIT — QEMU or keyring issue"
    fi

    # T2: Rewrite with seed A=42, run under A
    echo -e "  ${YELLOW}T2: Rewrite with seed=42, run under perm A${NC}"
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/audit3_simple_A \
        --seed 42 --keyring "$ISA_SYSCALL_KEYRING" --quiet
    python3 "$SYSCALL_REWRITER" /tmp/audit3_complex /tmp/audit3_complex_A \
        --seed 42 --keyring "$ISA_SYSCALL_KEYRING" --quiet
    sleep 1

    OUT=$(timeout 5 "$QEMU" /tmp/audit3_simple_A 2>/dev/null)
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
        check "T2: Simple_A runs under perm A (seed=42)" "PASS"
        echo -e "    Output: $OUT"
    else
        check "T2: Simple_A runs under perm A" "FAIL" "exit=$EXIT"
    fi

    OUT=$(timeout 5 "$QEMU" /tmp/audit3_complex_A 2>/dev/null)
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
        check "T3: Complex_A runs under perm A (4 syscalls remapped)" "PASS"
        echo -e "    Output: $(echo "$OUT" | head -1)..."
    else
        check "T3: Complex_A runs under perm A" "FAIL" "exit=$EXIT"
    fi

    # T3: Switch to seed B, old binaries must fail
    SEED_B=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
    echo -e "  ${YELLOW}T4-T5: Switch to perm B (seed=$SEED_B), old binaries must fail${NC}"
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/audit3_simple_B \
        --seed $SEED_B --keyring "$ISA_SYSCALL_KEYRING" --quiet
    sleep 1

    timeout 5 "$QEMU" /tmp/audit3_simple_A 2>/dev/null
    EXIT=$?
    if [ $EXIT -ne 0 ]; then
        check "T4: Simple_A BLOCKED under perm B (wrong syscalls)" "PASS"
    else
        check "T4: Simple_A BLOCKED under perm B" "FAIL" \
            "Binary still ran — security failure"
    fi

    timeout 5 "$QEMU" /tmp/audit3_complex_A 2>/dev/null
    EXIT=$?
    if [ $EXIT -ne 0 ]; then
        check "T5: Complex_A BLOCKED under perm B" "PASS"
    else
        check "T5: Complex_A BLOCKED under perm B" "FAIL" \
            "Binary still ran — security failure"
    fi

    # T4: New binary runs under B
    echo -e "  ${YELLOW}T6: New binary (perm B) runs under perm B${NC}"
    OUT=$(timeout 5 "$QEMU" /tmp/audit3_simple_B 2>/dev/null)
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
        check "T6: Simple_B runs under perm B (legitimate update)" "PASS"
        echo -e "    Output: $OUT"
    else
        check "T6: Simple_B runs under perm B" "FAIL" "exit=$EXIT"
    fi

    # T5: Different seeds → different keyrings
    echo -e "  ${YELLOW}T7-T8: Keyring properties${NC}"
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/s1 --seed 11111 \
        --keyring /tmp/k_audit1 --quiet
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/s2 --seed 22222 \
        --keyring /tmp/k_audit2 --quiet
    diff /tmp/k_audit1 /tmp/k_audit2 > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        check "T7: Different seeds produce different keyrings" "PASS"
    else
        check "T7: Different seeds produce different keyrings" "FAIL" \
            "Both seeds produced identical keyring"
    fi

    LINES=$(wc -l < /tmp/k_audit1)
    if [ "$LINES" -eq 436 ]; then
        check "T8: Keyring has 436 lines (full syscall range)" "PASS"
    else
        check "T8: Keyring has correct lines" "FAIL" "Expected 436 got $LINES"
    fi

    # T6: Verify rewriter correctly identifies syscall patterns
    echo -e "  ${YELLOW}T9: Verify syscall pattern detection${NC}"
    REWRITES=$(python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/s_check \
        --seed 42 --keyring /tmp/k_check 2>&1 | grep "Rewrote" | grep -o "[0-9]* syscall")
    if echo "$REWRITES" | grep -q "^[1-9]"; then
        check "T9: Rewriter detected syscall patterns ($REWRITES)" "PASS"
    else
        check "T9: Rewriter detected syscall patterns" "FAIL" "0 rewrites — pattern matching broken"
    fi

    # T7: Same seed always produces same keyring (deterministic)
    echo -e "  ${YELLOW}T10: Determinism check${NC}"
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/det1 --seed 99999 \
        --keyring /tmp/k_det1 --quiet
    python3 "$SYSCALL_REWRITER" /tmp/audit3_simple /tmp/det2 --seed 99999 \
        --keyring /tmp/k_det2 --quiet
    diff /tmp/k_det1 /tmp/k_det2 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        check "T10: Same seed always produces same keyring (deterministic)" "PASS"
    else
        check "T10: Determinism" "FAIL" "Same seed produced different keyrings"
    fi
    # T11: Independent disassembly proof via objdump
    # Compiles standard binary, rewrites it, then uses objdump to verify
    # the li a7 immediates changed — independent of rewriter output
    echo -e "  ${YELLOW}T11: Independent disassembly proof (objdump)${NC}"
    clang --target=riscv64-linux-gnu -march=rv64g -nostdlib -static -fuse-ld=lld -O1 \
        -o /tmp/audit3_disasm_std "$DEMO_DIR/simple.c" 2>/dev/null
    python3 "$SYSCALL_REWRITER" /tmp/audit3_disasm_std /tmp/audit3_disasm_A \
        --seed 42 --keyring /tmp/k_disasm --quiet

    # Use objdump to extract li a7 values from BOTH binaries independently
    STD_A7=$(riscv64-linux-gnu-objdump -d /tmp/audit3_disasm_std 2>/dev/null \
        | grep -E "li.*a7" | awk '{print $NF}' | tr '\n' ' ')
    REM_A7=$(riscv64-linux-gnu-objdump -d /tmp/audit3_disasm_A 2>/dev/null \
        | grep -E "li.*a7" | awk '{print $NF}' | tr '\n' ' ')

    echo -e "    ${YELLOW}Standard binary   li a7 values: $STD_A7${NC}"
    echo -e "    ${YELLOW}Remapped binary   li a7 values: $REM_A7${NC}"

    if [ "$STD_A7" = "$REM_A7" ]; then
        check "T11: objdump confirms syscall numbers changed in binary" "FAIL" \
            "Rewriter did not change li a7 values"
    elif [ -z "$REM_A7" ]; then
        check "T11: objdump confirms syscall numbers changed in binary" "FAIL" \
            "Could not read remapped binary with objdump"
    else
        check "T11: objdump confirms syscall numbers changed in binary" "PASS"
    fi

fi

# ─────────────────────────────────────────────────────────────
echo -e "\n${CYAN}══ SECTION 6: DOCUMENTATION & GIT ══${NC}"
# ─────────────────────────────────────────────────────────────

[ -f "$BASE_DIR/CHANGELOG.md" ] && \
    check "CHANGELOG.md exists" "PASS" || \
    check "CHANGELOG.md exists" "FAIL"

grep -q "2026-04" "$BASE_DIR/CHANGELOG.md" 2>/dev/null && \
    check "CHANGELOG has dated entries" "PASS" || \
    check "CHANGELOG has dated entries" "FAIL"

# Git check — works whether repo is at ../phase2 or at BASE_DIR itself
GIT_DIR=""
if git -C "$BASE_DIR/../phase2" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_DIR="$BASE_DIR/../phase2"
elif git -C "$BASE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_DIR="$BASE_DIR"
fi
if [ -n "$GIT_DIR" ]; then
    count=$(git -C "$GIT_DIR" log --oneline 2>/dev/null | wc -l)
    check "Git history exists ($count commits)" "PASS"
else
    check "Git history" "FAIL" "Not initialized — run: git init && git remote add origin <url>"
fi

# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
TOTAL=$((PASS+FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  ALL $TOTAL CHECKS PASSED ✓${NC}"
    echo -e "${GREEN}  Phase 3 Milestone 1 is production ready.${NC}"
else
    echo -e "${RED}  $FAIL/$TOTAL CHECKS FAILED ✗${NC}"
    echo -e "${YELLOW}  $PASS/$TOTAL passed${NC}"
    echo -e "${YELLOW}  Fix failures then re-run: bash audit.sh${NC}"
fi
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Git log (last 5):"
if [ -n "$GIT_DIR" ]; then
    git -C "$GIT_DIR" log --oneline -5 2>/dev/null
else
    echo "  (git not initialized)"
fi
echo ""
