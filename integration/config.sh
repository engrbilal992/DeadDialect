#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$BASE_DIR/isa.env"
while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key="${key// /}"; val="${val// /}"
    declare "$key=$val"
done < "$ENV_FILE"
export REGISTER_KEYRING SYSCALL_KEYRING
if [ -f "$BASE_DIR/$QEMU_REL" ]; then
    QEMU="$BASE_DIR/$QEMU_REL"
else
    QEMU=$(which qemu-riscv64 2>/dev/null || echo "")
fi
DEMO_DIR="$BASE_DIR/$DEMO_DIR_REL"
