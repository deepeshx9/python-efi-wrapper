#!/bin/bash
set -e

# Just for testing; assumes the host is ARM64 and target is x64.

echo "===================================================="
echo "  EFI-PYTHON WRAPPER: TEST CODE  "
echo "===================================================="
echo "Host Architecture: ARM64 (Snapdragon/WSL)"
echo "Target Architecture: x86_64"
echo "===================================================="


# CROSS-COMPILE MINIMAL x86_64 KERNEL

echo -e "\n[1/4] Preparing Minimal Linux Kernel..."

if [ ! -d "linux-6.8.9" ]; then
    echo "Downloading Kernel Source..."
    wget -q --show-progress https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.8.9.tar.xz
    tar -xf linux-6.8.9.tar.xz
fi

cd linux-6.8.9
if [ ! -f "arch/x86/boot/bzImage" ]; then
    echo "Compiling x86_64 KVM Guest Kernel..."
    make ARCH=x86 defconfig
    make ARCH=x86 kvm_guest.config
    make ARCH=x86 CROSS_COMPILE=x86_64-linux-gnu- -j$(nproc) bzImage
fi
cp arch/x86/boot/bzImage ../
cd ..


# CROSS-COMPILE STATIC MICROPYTHON & INITRAMFS

echo -e "\n[2/4] Building Static MicroPython & Initramfs..."

if [ ! -d "micropython" ]; then
    echo "Cloning MicroPython..."
    git clone https://github.com/micropython/micropython.git
fi

cd micropython
echo "Building Host mpy-cross..."
make -C mpy-cross

cd ports/unix
echo "Cross-compiling Static x86_64 MicroPython..."
make clean
make CC=x86_64-linux-gnu-gcc CROSS_COMPILE=x86_64-linux-gnu- LDFLAGS_EXTRA="-static" MICROPY_PY_FFI=0 MICROPY_PY_BTREE=0 -j$(nproc)
cd ../../../

echo "Constructing Initramfs Filesystem..."
mkdir -p initramfs/{bin,dev,proc,sys}

if [ ! -f "initramfs/bin/busybox" ]; then
    wget -q --show-progress https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox -O initramfs/bin/busybox
    chmod +x initramfs/bin/busybox
fi
ln -sf busybox initramfs/bin/sh
cp micropython/ports/unix/build-standard/micropython initramfs/bin/

cat << 'EOF' > initramfs/main.py
import sys
import os

print("\n" + "="*40)
print(" 🐍 HELLO FROM EFI PYTHON! 🐍 ")
print("="*40 + "\n")

print(f"Python version: {sys.version}")
print(f"Platform: {sys.platform}")
print("\nBoot sequence complete. Dropping to REPL...")
EOF

cat << 'EOF' > initramfs/init
#!/bin/sh
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox mount -t devtmpfs none /dev

/bin/micropython /main.py
exec /bin/micropython
EOF
chmod +x initramfs/init

echo "Packing Initramfs..."
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..


# DYNAMIC PE FUSION (UKI CREATION)

echo -e "\n[3/4] Fusing Unified Kernel Image (boot.efi)..."

rm -rf efi_stub_extracted systemd-boot.deb boot.efi cmdline.txt
echo -n "console=ttyS0 quiet" > cmdline.txt

echo "Fetching Immutable systemd-boot Stub..."
wget -q "https://snapshot.debian.org/archive/debian/20231009T000000Z/pool/main/s/systemd/systemd-boot-efi_254.5-1_amd64.deb" -O systemd-boot.deb
dpkg -x systemd-boot.deb efi_stub_extracted

cat << 'EOF' > build_uki.py
import struct
import os

stub_path = 'efi_stub_extracted/usr/lib/systemd/boot/efi/linuxx64.efi.stub'

with open(stub_path, 'rb') as f:
    f.seek(0x3C)
    pe_offset = struct.unpack('<I', f.read(4))[0]
    f.seek(pe_offset + 48)
    image_base = struct.unpack('<Q', f.read(8))[0]

print(f"Detected Stub PE Image Base: {hex(image_base)}")

offsets = {
    '.osrel': 0x20000,
    '.cmdline': 0x30000,
    '.linux': 0x2000000,
    '.initrd': 0x3000000
}

cmd = (
    f"x86_64-linux-gnu-objcopy "
    f"--add-section .osrel=/dev/null --change-section-vma .osrel={hex(image_base + offsets['.osrel'])} "
    f"--add-section .cmdline=cmdline.txt --change-section-vma .cmdline={hex(image_base + offsets['.cmdline'])} "
    f"--add-section .linux=bzImage --change-section-vma .linux={hex(image_base + offsets['.linux'])} "
    f"--add-section .initrd=initramfs.cpio.gz --change-section-vma .initrd={hex(image_base + offsets['.initrd'])} "
    f"{stub_path} boot.efi"
)

if os.system(cmd) != 0:
    print("[-] FATAL: objcopy failed.")
    exit(1)
EOF

python3 build_uki.py

# QEMU LAUNCH

echo -e "\n[4/4] Launching EFI Environment in QEMU..."

mkdir -p efi_drive/EFI/BOOT
mv boot.efi efi_drive/EFI/BOOT/BOOTX64.EFI

OVMF_PATH=$(find /usr/share -name "OVMF.fd" -o -name "OVMF_CODE.fd" 2>/dev/null | head -n 1)

if [ -z "$OVMF_PATH" ]; then
    echo "[-] FATAL: OVMF UEFI firmware not found. Please run: sudo apt install ovmf"
    exit 1
fi

echo "[+] UEFI Firmware found at: $OVMF_PATH"
echo "[+] Starting emulation... (Press Ctrl+A, then X to exit)"
sleep 2

qemu-system-x86_64 -nographic \
    -m 512M \
    -bios "$OVMF_PATH" \
    -drive format=raw,file=fat:rw:efi_drive