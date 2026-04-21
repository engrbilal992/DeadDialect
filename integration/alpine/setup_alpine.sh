#!/bin/bash
# Alpine Linux RISC-V Setup Script
# Run once to download and set up Alpine on any machine
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Alpine Linux RISC-V Setup ==="

# 1. Download Alpine rootfs
if [ ! -f alpine-minirootfs-3.20.0-riscv64.tar.gz ]; then
    echo "[1/6] Downloading Alpine 3.20.0 riscv64 rootfs..."
    wget -q https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/riscv64/alpine-minirootfs-3.20.0-riscv64.tar.gz
else
    echo "[1/6] Alpine rootfs already downloaded"
fi

# 2. Download Debian RISC-V kernel
if [ ! -f kernel_extract/boot/vmlinux-6.19.11+deb14-riscv64 ]; then
    echo "[2/6] Downloading Debian RISC-V kernel..."
    wget -q https://deb.debian.org/debian/pool/main/l/linux/linux-binary-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb
    wget -q https://deb.debian.org/debian/pool/main/l/linux/linux-modules-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb
    dpkg-deb -x linux-binary-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb kernel_extract/
    dpkg-deb -x linux-modules-6.19.11+deb14-riscv64_6.19.11-1_riscv64.deb modules_extract/
else
    echo "[2/6] Kernel already extracted"
fi

# 3. Download RISC-V busybox
if [ ! -f busybox_extract/usr/bin/busybox ]; then
    echo "[3/6] Downloading RISC-V busybox..."
    wget -q https://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.37.0-10.1_riscv64.deb
    dpkg-deb -x busybox-static_1.37.0-10.1_riscv64.deb busybox_extract/
else
    echo "[3/6] Busybox already downloaded"
fi

# 4. Create disk image
if [ ! -f alpine-riscv64.img ]; then
    echo "[4/6] Creating Alpine disk image..."
    qemu-img create -f raw alpine-riscv64.img 1G
    mkfs.ext4 alpine-riscv64.img
    mkdir -p mnt
    sudo mount -o loop alpine-riscv64.img mnt
    sudo tar xzf alpine-minirootfs-3.20.0-riscv64.tar.gz -C mnt
    sudo umount mnt
else
    echo "[4/6] Disk image already exists"
fi

# 5. Build initramfs
echo "[5/6] Building initramfs..."
KVER="6.19.11+deb14-riscv64"
MODDIR="modules_extract/usr/lib/modules/$KVER/kernel"
mkdir -p initramfs/{bin,lib/modules/$KVER,proc,sys,dev,newroot}
cp busybox_extract/usr/bin/busybox initramfs/bin/
cp $MODDIR/drivers/virtio/virtio_mmio.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/drivers/block/virtio_blk.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/net/core/failover.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/drivers/net/net_failover.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/drivers/net/virtio_net.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/lib/crc/crc16.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/fs/mbcache.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/fs/jbd2/jbd2.ko.xz initramfs/lib/modules/$KVER/
cp $MODDIR/fs/ext4/ext4.ko.xz initramfs/lib/modules/$KVER/

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
find . | cpio -o -H newc | gzip > ../initramfs.cpio.gz
cd ..

echo "[6/6] Setup complete! Run boot_alpine.sh to start Alpine"
echo ""
echo "Once inside Alpine, configure network:"
echo "  ip link set eth0 up"
echo "  ip addr add 10.0.2.15/24 dev eth0"
echo "  ip route add default via 10.0.2.2"
echo "  echo nameserver 8.8.8.8 > /etc/resolv.conf"
echo "  apk update"
