#!/bin/bash
# Alpine Linux RISC-V Boot Script — Patched QEMU 8.2
source "$(dirname "$(readlink -f "$0")")/../config.sh"

python3 -c "
import random, os
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
seed=int.from_bytes(os.urandom(4),'big')
r=random.Random(seed); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
map_path=os.environ.get('ISA_MAP','/etc/isa/map'); os.makedirs(os.path.dirname(map_path),exist_ok=True)
with open(map_path,'w') as f:
    [f.write(f'{mp} {o}\n') for o,mp in m.items()]
print(f'[ISA] Mapping active (seed={seed})')
"

$QEMU_SYSTEM \
    -machine virt \
    -nographic \
    -m 512M \
    -bios $QEMU_BIOS \
    -kernel "$ALPINE_KERNEL" \
    -initrd "$ALPINE_INITRD" \
    -drive file="$ALPINE_IMG",format=raw,id=hd0,if=none \
    -device virtio-blk-device,drive=hd0 \
    -append "root=/dev/vda rw console=ttyS0" \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0
