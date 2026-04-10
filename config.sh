#!/bin/bash
# ISA Remapping — Config Loader
# Reads isa.env and resolves all relative paths to absolute.
# Source this file in bash: source "$(dirname "$0")/../config.sh"
# Python reads isa.env directly via lib/config.py

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$BASE_DIR/isa.env"

# Load isa.env — strip comments and blank lines
while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    key="${key// /}"
    val="${val// /}"
    declare "$key=$val"
done < "$ENV_FILE"

# Resolve relative paths to absolute using BASE_DIR
export ISA_MAP="$ISA_MAP"
QEMU="$BASE_DIR/$QEMU_REL"
QEMU_SYSTEM="$BASE_DIR/$QEMU_SYSTEM_REL"
QEMU_BIOS="$BASE_DIR/$QEMU_BIOS_REL"
ALPINE_IMG="$BASE_DIR/$ALPINE_IMG_REL"
ALPINE_KERNEL="$BASE_DIR/$ALPINE_KERNEL_REL"
ALPINE_INITRD="$BASE_DIR/$ALPINE_INITRD_REL"
DEMO_DIR="$BASE_DIR/$DEMO_DIR_REL"
ISA_COMPILE="$BASE_DIR/isa_compile.py"
TRIGGER_SCRIPT="$BASE_DIR/trigger/isa_trigger.py"
