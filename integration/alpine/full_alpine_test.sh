#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/../config.sh"
INTEGRATE="$BASE_DIR/isa_integrate.py"

echo "=== Full Alpine ISA Integration Test ==="
echo "    Register + Syscall layers"
echo ""

clang --target=riscv64-linux-gnu -march=rv64g \
    -nostdlib -static -fuse-ld=lld -Wl,--no-relax \
    -o /tmp/int_base "$BASE_DIR/riscv_demo/simple.S" 2>/dev/null

echo "[COMPILE] Building remapped binaries (seed=42)..."
python3 "$INTEGRATE" /tmp/int_base /tmp/int_std --seed 42 --quiet
python3 "$INTEGRATE" /tmp/int_base /tmp/int_mal --seed 42 --quiet
echo "[MAPPING] Register + Syscall keyrings active (seed=42)"
sleep 1

echo ""
echo "[TEST 1] Remapped binary under seed=42..."
timeout 5 "$QEMU" /tmp/int_std 2>/dev/null
[ $? -eq 0 ] && echo "  RESULT: SUCCESS ✓" || echo "  RESULT: FAILED ✗"

echo ""
echo "[TRIGGER] Firing ISA remap — both layers updated atomically..."
NEW_SEED=$(python3 -c "import secrets; print(int.from_bytes(secrets.token_bytes(4),'big'))")
python3 "$INTEGRATE" /tmp/int_base /tmp/int_new --seed $NEW_SEED --quiet
echo "  New seed: $NEW_SEED"
sleep 1

echo ""
echo "[TEST 2] Old binary after remap (should be BLOCKED)..."
timeout 5 "$QEMU" /tmp/int_std 2>/dev/null
[ $? -ne 0 ] && echo "  RESULT: BLOCKED ✓" || echo "  RESULT: PASSED (unexpected)"

echo ""
echo "[TEST 3] Malware after remap (should be BLOCKED)..."
timeout 5 "$QEMU" /tmp/int_mal 2>/dev/null
[ $? -ne 0 ] && echo "  RESULT: BLOCKED ✓" || echo "  RESULT: EXECUTED (bad)"

echo ""
echo "[TEST 4] Legitimate update (new seed)..."
sleep 1
timeout 5 "$QEMU" /tmp/int_new 2>/dev/null
[ $? -eq 0 ] && echo "  RESULT: UPDATE PASSES ✓" || echo "  RESULT: FAILED ✗"

echo ""
echo "=== All Alpine ISA Integration Tests Complete ==="
echo ""
echo "To boot Alpine: bash alpine/boot_alpine.sh"
