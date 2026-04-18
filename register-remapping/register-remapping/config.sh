#!/bin/bash
# Register Remapping — Config Loader
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$BASE_DIR/isa.env"

while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key="${key// /}"; val="${val// /}"
    declare "$key=$val"
done < "$ENV_FILE"

export REGISTER_KEYRING="$REGISTER_KEYRING"
QEMU="$BASE_DIR/$QEMU_REL"
DEMO_DIR="$BASE_DIR/$DEMO_DIR_REL"
PHASE1="$(realpath "$BASE_DIR/../phase1")"
ISA_COMPILE="$BASE_DIR/isa_register_rewrite.py"
