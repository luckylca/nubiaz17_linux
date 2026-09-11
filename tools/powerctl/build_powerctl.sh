#!/usr/bin/env bash
set -euo pipefail

# Build tools/powerctl/powerctl: a tiny static aarch64 ELF that calls the
# reboot(2) syscall directly (poweroff / restart / bootloader), selected by
# argv[1]. Needed because the Ubuntu rootfs's /usr/sbin/{reboot,poweroff,
# halt,shutdown} are systemctl symlinks and systemd is NOT running (PID1 is
# /bin/sh /init), so all of them silently do nothing ("关机没用").
#
# Same technique as tools/reboot-bootloader: macOS clang assembles the
# aarch64 object, python3 wraps .text in a minimal ELF64 executable.
#
# Usage: tools/powerctl/build_powerctl.sh [OUTPUT]
# Default output: work/powerctl/powerctl

ROOT="$(git rev-parse --show-toplevel)"
OUT="${1:-$ROOT/work/powerctl/powerctl}"
SRC="$ROOT/tools/powerctl/powerctl.s"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

clang -target aarch64-linux-gnu -c "$SRC" -o "$TMP/powerctl.o"

mkdir -p "$(dirname "$OUT")"
python3 - "$TMP/powerctl.o" "$OUT" <<'PY'
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
