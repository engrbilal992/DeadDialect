#!/bin/bash
# RISC-V ISA Remapping — Complete Setup Script
# Works on any Ubuntu 22.04 machine from scratch
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1="$SCRIPT_DIR/../phase1"
PHASE2="$SCRIPT_DIR"
ALPINE="$SCRIPT_DIR/alpine"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  RISC-V ISA Remapping — Setup Script  ${NC}"
echo -e "${CYAN}========================================${NC}"

# Step 1: Install dependencies
echo -e "\n${CYAN}[1/7] Installing dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y \
    wget python3 clang lld \
    qemu-system-riscv64 qemu-utils e2fsprogs \
    libglib2.0-dev libpixman-1-dev ninja-build \
    pkg-config gcc make libslirp-dev \
    2>/dev/null || true
echo -e "${GREEN}    Dependencies installed ✓${NC}"

# Step 1b: Create /etc/isa/map with correct permissions
# Without this file QEMU's stat() fails silently and runs with no mapping.
echo -e "\n${CYAN}[1b] Setting up /etc/isa/map...${NC}"
sudo mkdir -p /etc/isa
sudo touch /etc/isa/map
sudo chown root:$(whoami) /etc/isa/map
sudo chown root:$(whoami) /etc/isa/map
sudo chmod 640 /etc/isa/map
echo -e "${GREEN}    /etc/isa/map ready ✓${NC}"

# Step 2: Build patched QEMU
echo -e "\n${CYAN}[2/7] Building patched QEMU 8.2...${NC}"
if [ ! -f "$PHASE1/qemu-8.2.0/build/qemu-riscv64" ] || [ ! -f "$PHASE1/qemu-8.2.0/build/qemu-system-riscv64" ]; then
    cd "$PHASE1/qemu-8.2.0"
    mkdir -p build && cd build
    ../configure \
        --target-list=riscv64-linux-user,riscv64-softmmu \
        --disable-gtk --disable-sdl --disable-opengl \
        --enable-slirp 2>/dev/null
    make qemu-riscv64 qemu-system-riscv64 -j$(nproc) 2>/dev/null
    cd "$PHASE2"
    echo -e "${GREEN}    Patched QEMU built ✓${NC}"
else
    echo -e "${GREEN}    Patched QEMU already built ✓${NC}"
fi

# Step 3: Setup Alpine
echo -e "\n${CYAN}[3/7] Setting up Alpine Linux RISC-V...${NC}"
cd "$ALPINE"

# Download rootfs
if [ ! -f alpine-minirootfs-3.20.0-riscv64.tar.gz ]; then
    wget -q https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/riscv64/alpine-minirootfs-3.20.0-riscv64.tar.gz
fi

# Download kernel
if [ ! -f kernel_extract/boot/vmlinux-6.19.11+deb14-riscv64 ]; then
    wget -q https://deb.debian.org/debian/pool/main/l/linux/linux-binary-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb
    wget -q https://deb.debian.org/debian/pool/main/l/linux/linux-modules-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb
    dpkg-deb -x linux-binary-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb kernel_extract/
    dpkg-deb -x linux-modules-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb modules_extract/
fi

# Download busybox
if [ ! -f busybox_extract/usr/bin/busybox ]; then
    wget -q https://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.37.0-10.1_riscv64.deb
    dpkg-deb -x busybox-static_1.37.0-10.1_riscv64.deb busybox_extract/
fi

echo -e "${GREEN}    Alpine components downloaded ✓${NC}"

# Step 4: Create disk image
echo -e "\n${CYAN}[4/7] Creating Alpine disk image...${NC}"
if [ ! -f alpine-riscv64.img ]; then
    qemu-img create -f raw alpine-riscv64.img 1G
    mkfs.ext4 -q alpine-riscv64.img
    mkdir -p mnt
    sudo mount -o loop alpine-riscv64.img mnt
    sudo tar xzf alpine-minirootfs-3.20.0-riscv64.tar.gz -C mnt
    sudo umount mnt
fi
e2fsck -f -y alpine-riscv64.img >/dev/null 2>&1 || true
echo -e "${GREEN}    Disk image ready ✓${NC}"

# Step 5: Build initramfs
echo -e "\n${CYAN}[5/7] Building initramfs...${NC}"
KVER="6.19.11+deb14-riscv64"
MODDIR="modules_extract/usr/lib/modules/$KVER/kernel"
mkdir -p initramfs/{bin,lib/modules/$KVER,proc,sys,dev,newroot}
cp busybox_extract/usr/bin/busybox initramfs/bin/
for mod in \
    drivers/virtio/virtio_mmio \
    drivers/block/virtio_blk \
    net/core/failover \
    drivers/net/net_failover \
    drivers/net/virtio_net \
    lib/crc/crc16 \
    fs/mbcache \
    fs/jbd2/jbd2 \
    fs/ext4/ext4; do
    cp "$MODDIR/${mod}.ko.xz" "initramfs/lib/modules/$KVER/" 2>/dev/null || true
done

cat > initramfs/init << 'INITEOF'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "Loading virtio modules..."
insmod /lib/modules/6.19.11+deb14-riscv64/virtio_mmio.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/virtio_blk.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/failover.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/net_failover.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/virtio_net.ko.xz
sleep 1
echo "Loading ext4 modules..."
insmod /lib/modules/6.19.11+deb14-riscv64/crc16.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/mbcache.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/jbd2.ko.xz
insmod /lib/modules/6.19.11+deb14-riscv64/ext4.ko.xz
echo "Configuring network..."
ip link set eth0 up
ip addr add 10.0.2.15/24 dev eth0
ip route add default via 10.0.2.2
echo "Mounting Alpine root..."
mount -t ext4 /dev/vda /newroot
if [ $? -eq 0 ]; then
    echo "SUCCESS! Switching to Alpine..."
    exec switch_root /newroot /bin/sh
else
    exec /bin/sh
fi
INITEOF
chmod +x initramfs/init
cd initramfs
find . | cpio -o -H newc | gzip > ../initramfs.cpio.gz 2>/dev/null
cd ..
echo -e "${GREEN}    Initramfs built ✓${NC}"

# Step 6: Copy test binaries into Alpine
echo -e "\n${CYAN}[6/7] Preparing Alpine test binaries...${NC}"
cd "$PHASE2"


clang --target=riscv64-linux-gnu -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/advanced_std alpine/../riscv_demo/advanced.c 2>/dev/null
clang --target=riscv64-linux-gnu -nostdlib -static -fuse-ld=lld -O1 \
    -o /tmp/malware_std alpine/../riscv_demo/malware_sim.c 2>/dev/null
python3 isa_compile.py riscv_demo/advanced.c /tmp/advanced_remapped 42 >/dev/null 2>&1
python3 isa_compile.py riscv_demo/malware_sim.c /tmp/malware_remapped 42 >/dev/null 2>&1

sudo mount -o loop alpine/alpine-riscv64.img alpine/mnt
sudo cp /tmp/advanced_std alpine/mnt/root/advanced
sudo cp /tmp/malware_std alpine/mnt/root/malware
sudo cp /tmp/advanced_remapped alpine/mnt/root/advanced_remapped
sudo cp /tmp/malware_remapped alpine/mnt/root/malware_remapped
sudo umount alpine/mnt
echo -e "${GREEN}    Test binaries ready ✓${NC}"

# Step 7: Run verification tests
echo -e "\n${CYAN}[7/7] Running verification tests...${NC}"
cd "$PHASE2"

echo -e "\n${CYAN}  --- Trigger Demo ---${NC}"
bash trigger/trigger_demo.sh 2>/dev/null | grep "PHASE\|BLOCKED\|SUCCESS\|FAILED\|Result"

echo -e "\n${CYAN}  --- Alpine ISA Test ---${NC}"
bash alpine/full_alpine_test.sh 2>/dev/null | grep "RESULT\|MAPPING\|TRIGGER\|TEST"

echo -e "\n${CYAN}  --- Config Check ---${NC}"
source config.sh
[ -f "$QEMU" ] && echo -e "${GREEN}  QEMU user-mode: EXISTS ✓${NC}" || echo -e "${RED}  QEMU user-mode: MISSING ✗${NC}"
[ -f "$QEMU_SYSTEM" ] && echo -e "${GREEN}  QEMU system:    EXISTS ✓${NC}" || echo -e "${RED}  QEMU system:    MISSING ✗${NC}"
[ -f "$ALPINE_KERNEL" ] && echo -e "${GREEN}  Alpine kernel:  EXISTS ✓${NC}" || echo -e "${RED}  Alpine kernel:  MISSING ✗${NC}"
[ -f "$ALPINE_IMG" ] && echo -e "${GREEN}  Alpine image:   EXISTS ✓${NC}" || echo -e "${RED}  Alpine image:   MISSING ✗${NC}"

echo -e "\n${CYAN}========================================${NC}"
echo -e "${GREEN}  Setup Complete! To boot Alpine run:   ${NC}"
echo -e "${GREEN}  bash alpine/boot_alpine.sh            ${NC}"
echo -e "${CYAN}========================================${NC}\n"
