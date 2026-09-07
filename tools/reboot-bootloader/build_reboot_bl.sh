#!/usr/bin/env bash
set -euo pipefail

# Build tools/reboot-bootloader/reboot-bl: a 175-byte static aarch64 ELF that
# calls reboot(LINUX_REBOOT_CMD_RESTART2, "bootloader") so the device drops
# straight into fastboot from a Linux shell. busybox reboot (both the Debian
# 1.35 static build in the initramfs and Alpine 1.36 in the rootfs) ignores
# the reason argument, so this tiny stub is the only way to reach fastboot
# without physical buttons.
#
# Toolchain: macOS clang (LLVM integrated assembler targets aarch64-linux
# objects fine) + python3 to wrap the .text section in a minimal ELF64
# executable. No cross-binutils needed.
#
# Usage: tools/reboot-bootloader/build_reboot_bl.sh [OUTPUT]
# Default output: work/reboot-bl/reboot-bl

ROOT="$(git rev-parse --show-toplevel)"
OUT="${1:-$ROOT/work/reboot-bl/reboot-bl}"
SRC="$ROOT/tools/reboot-bootloader/reboot_bl.s"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

clang -target aarch64-linux-gnu -c "$SRC" -o "$TMP/reboot_bl.o"

mkdir -p "$(dirname "$OUT")"
python3 - "$TMP/reboot_bl.o" "$OUT" <<'PY'
import struct
import sys

obj = open(sys.argv[1], "rb").read()
assert obj[:4] == b"\x7fELF" and obj[4] == 2 and obj[5] == 1

(e_shoff,) = struct.unpack_from("<Q", obj, 0x28)
(e_shentsize,) = struct.unpack_from("<H", obj, 0x3A)
(e_shnum,) = struct.unpack_from("<H", obj, 0x3C)
(e_shstrndx,) = struct.unpack_from("<H", obj, 0x3E)

def shdr(i):
    off = e_shoff + i * e_shentsize
    return struct.unpack_from("<IIQQQQ", obj, off)

strtab_off = shdr(e_shstrndx)[4]
def secname(n):
    end = obj.index(b"\0", strtab_off + n)
    return obj[strtab_off + n:end].decode()

text = None
for i in range(e_shnum):
    name, _typ, _flags, _addr, off, size = shdr(i)
    if secname(name) == ".text":
        text = obj[off:off + size]
assert text, "no .text section"

BASE = 0x400000
EHDR = 64
PHDR = 56
code_off = EHDR + PHDR

ehdr = struct.pack("<16sHHIQQQIHHHHHH",
    b"\x7fELF" + bytes([2, 1, 1, 0]) + bytes(8),
    2,          # ET_EXEC
    183,        # EM_AARCH64
    1,
    BASE + code_off,
    EHDR, 0, 0,
    EHDR, PHDR, 1, 0, 0, 0)
phdr = struct.pack("<IIQQQQQQ",
    1,          # PT_LOAD
    5,          # R+X
    0, BASE, BASE,
    code_off + len(text), code_off + len(text),
    0x1000)

with open(sys.argv[2], "wb") as fh:
    fh.write(ehdr + phdr + text)
PY

echo "Built $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
shasum -a 256 "$OUT"
