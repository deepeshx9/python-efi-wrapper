import struct
import os

stub_path = 'efi_stub_extracted/usr/lib/systemd/boot/efi/linuxx64.efi.stub'

# Parse the raw PE32+ header to find the true Image Base
with open(stub_path, 'rb') as f:
    f.seek(0x3C) # e_lfanew pointer
    pe_offset = struct.unpack('<I', f.read(4))[0]
    
    # In a 64-bit PE file, the Image Base is exactly 48 bytes past the PE signature
    # (4 bytes for signature + 20 for COFF header + 24 into Optional Header)
    f.seek(pe_offset + 48)
    image_base = struct.unpack('<Q', f.read(8))[0]

print(f"\n[+] Detected PE Image Base: {hex(image_base)}")

# Define our section offsets relative to whatever the Image Base is
offsets = {
    '.osrel': 0x20000,
    '.cmdline': 0x30000,
    '.linux': 0x2000000,
    '.initrd': 0x3000000
}

# Dynamically construct the objcopy command
cmd = (
    f"x86_64-linux-gnu-objcopy "
    f"--add-section .osrel=/dev/null --change-section-vma .osrel={hex(image_base + offsets['.osrel'])} "
    f"--add-section .cmdline=cmdline.txt --change-section-vma .cmdline={hex(image_base + offsets['.cmdline'])} "
    f"--add-section .linux=bzImage --change-section-vma .linux={hex(image_base + offsets['.linux'])} "
    f"--add-section .initrd=initramfs.cpio.gz --change-section-vma .initrd={hex(image_base + offsets['.initrd'])} "
    f"{stub_path} boot.efi"
)

print("[+] Fusing sections into boot.efi...")
if os.system(cmd) == 0:
    print("[+] Success! boot.efi created.\n")
else:
    print("[-] objcopy failed.")
