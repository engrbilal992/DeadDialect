#!/bin/bash
# Shared ISA mapping generator — sourced by all scripts
# Usage: source lib/generate_mapping.sh
#        generate_mapping <seed>

generate_mapping() {
    local seed=$1
    python3 - "$seed" << 'PYEOF'
import random, os, sys, subprocess
seed = int(sys.argv[1])
OPCODES=[0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17,0x0F,0x3B,0x1B]
r=random.Random(seed); s=OPCODES[:]; r.shuffle(s)
m=dict(zip(OPCODES,s))
map_path=os.environ.get('ISA_MAP','/etc/isa/map')
os.makedirs(os.path.dirname(map_path), exist_ok=True)
lines = [f"{mapped} {o}\n" for o,mapped in m.items()]
content = "".join(lines)
try:
    with open(map_path,'w') as f:
        f.write(content)
except PermissionError:
    subprocess.run(['sudo','tee',map_path], input=content, text=True, capture_output=True, check=True)
print(f'[ISA] Mapping active (seed={seed})', file=sys.stderr)
PYEOF
}

generate_mapping_random() {
    local seed
    seed=$(python3 -c "import os; print(int.from_bytes(os.urandom(4),'big'))")
    generate_mapping "$seed"
    echo "$seed"
}
