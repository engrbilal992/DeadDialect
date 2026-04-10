#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/../config.sh"

echo "=== Full Alpine ISA Remapping Test ==="
echo ""

# Generate mapping
python3 -c "
import random
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random(42); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
import os; os.makedirs(os.path.dirname(os.environ.get('ISA_MAP','/etc/isa/map')), exist_ok=True)
with open(os.environ.get('ISA_MAP','/etc/isa/map'),'w') as f:
    [f.write(f'{mp} {o}\n') for o,mp in m.items()]
print('[MAPPING] ISA active seed=42')
"

# Compile test binaries
echo "[COMPILE] Building standard binaries..."
python3 "$ISA_COMPILE" "$DEMO_DIR/advanced.c" /tmp/alpine_std 42 >/dev/null 2>&1
python3 "$ISA_COMPILE" "$DEMO_DIR/malware_sim.c" /tmp/alpine_mal 42 >/dev/null 2>&1

echo "[TEST 1] Standard binary under seed=42..."
timeout 5 "$QEMU" /tmp/alpine_std 2>/dev/null | head -2
[ $? -eq 0 ] && echo "  RESULT: SUCCESS ✓" || echo "  RESULT: FAILED ✗"

echo ""
echo "[TRIGGER] Firing ISA remap..."
NEW_SEED=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
python3 -c "
import random
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random($NEW_SEED); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
import os; os.makedirs(os.path.dirname(os.environ.get('ISA_MAP','/etc/isa/map')), exist_ok=True)
with open(os.environ.get('ISA_MAP','/etc/isa/map'),'w') as f:
    [f.write(f'{mp} {o}\n') for o,mp in m.items()]
print(f'  New seed: $NEW_SEED')
"

echo ""
echo "[TEST 2] Old binary after remap (should fail)..."
timeout 5 "$QEMU" /tmp/alpine_std 2>/dev/null
[ $? -ne 0 ] && echo "  RESULT: BLOCKED ✓" || echo "  RESULT: PASSED (unexpected)"

echo ""
echo "[TEST 3] Malware after remap (should be blocked)..."
timeout 5 "$QEMU" /tmp/alpine_mal 2>/dev/null
[ $? -ne 0 ] && echo "  RESULT: BLOCKED ✓" || echo "  RESULT: EXECUTED (bad)"

echo ""
echo "[TEST 4] Legitimate update (recompile under new seed)..."
python3 "$ISA_COMPILE" "$DEMO_DIR/advanced.c" /tmp/alpine_updated $NEW_SEED >/dev/null 2>&1
timeout 5 "$QEMU" /tmp/alpine_updated 2>/dev/null | head -2
[ $? -eq 0 ] && echo "  RESULT: UPDATE PASSES ✓" || echo "  RESULT: FAILED ✗"

echo ""
echo "=== All Alpine ISA Tests Complete ==="

echo ""
echo "=== NOTE: Boot Alpine manually to verify inside-Alpine tests ==="
echo "Run: bash alpine/boot_alpine.sh"
echo "Inside Alpine run:"
echo "  /root/advanced > /dev/null && echo 'Standard: PASS'"
echo "  /root/advanced_remapped 2>/dev/null; [ \$? -eq 132 ] && echo 'Remapped: BLOCKED'"
echo "  /root/malware > /dev/null && echo 'Malware: runs'"
echo "  /root/malware_remapped 2>/dev/null; [ \$? -eq 132 ] && echo 'Malware remapped: BLOCKED'"
