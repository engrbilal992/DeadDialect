#!/bin/bash
# Alpine Linux RISC-V — Integration Boot Script
# Boots Alpine under patched QEMU with ISA remapping active
source "$(dirname "$(readlink -f "$0")")/../config.sh"

ALPINE_DIR="$(dirname "$(readlink -f "$0")")"
QEMU_SYS="$(realpath "$BASE_DIR/../phase1/qemu-8.2.0/build/qemu-system-riscv64" 2>/dev/null)"
QEMU_BIOS="$(realpath "$BASE_DIR/../phase1/qemu-8.2.0/pc-bios/opensbi-riscv64-generic-fw_dynamic.bin" 2>/dev/null)"

echo "████████████████████████████████████████████████████████"
echo "  RISC-V Alpine Linux — ISA Integration Boot"
echo "  Register + Syscall remapping active"
echo "████████████████████████████████████████████████████████"
echo ""
echo "[ISA] Booting Alpine under patched QEMU..."
echo "[ISA] Register keyring: $REGISTER_KEYRING"
echo "[ISA] Syscall keyring:  $SYSCALL_KEYRING"
echo ""
echo "Press Ctrl+A then X to exit QEMU"
echo ""

"$QEMU_SYS" \
    -machine virt \
    -nographic \
    -m 512M \
    -bios "$QEMU_BIOS" \
    -kernel "$ALPINE_DIR/kernel_extract/boot/vmlinux-6.19.11+deb14-riscv64" \
    -initrd "$ALPINE_DIR/initramfs.cpio.gz" \
    -drive file="$ALPINE_DIR/alpine-riscv64.img",format=raw,id=hd0,if=none \
    -device virtio-blk-device,drive=hd0 \
    -append "root=/dev/vda rw console=ttyS0" \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0
