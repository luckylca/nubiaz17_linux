#!/usr/bin/env bash
set -euo pipefail

# Build the NX563J diagnostic initramfs (cpio newc, gzipped, deterministic).
#
# Downloads a pinned Debian arm64 busybox-static package, assembles a minimal
# root around initramfs/init, and emits work/diag-initramfs.cpio.gz.
# This script never touches the phone.

ROOT="$(git rev-parse --show-toplevel)"
BUSYBOX_DEB_URL="https://ftp.debian.org/debian/pool/main/b/busybox/busybox-static_1.35.0-4+deb12u1+b1_arm64.deb"
BUSYBOX_DEB_SHA256="732c9135564fc71337e0e05fb4da4d11e6c28c1834bce3e405e575afef2a52f5"
WORK="$ROOT/work/diag-initramfs"
OUT="$WORK/diag-initramfs.cpio.gz"

command -v python3 >/dev/null

mkdir -p "$WORK"
cd "$WORK"

if [[ ! -f busybox-static_arm64.deb ]]; then
  echo "Downloading pinned busybox-static (arm64)"
  curl -fsSL --retry 5 --retry-delay 5 "$BUSYBOX_DEB_URL" -o busybox-static_arm64.deb
fi

ACTUAL="$(shasum -a 256 busybox-static_arm64.deb | awk '{print $1}')"
if [[ "$ACTUAL" != "$BUSYBOX_DEB_SHA256" ]]; then
  echo "ERROR: busybox deb hash mismatch: $ACTUAL" >&2
  exit 1
fi

rm -rf root data-extract
mkdir -p root/bin root/dev root/proc root/sys root/config root/mnt/logdisk data-extract
tar -xf busybox-static_arm64.deb -C data-extract
tar -xf data-extract/data.tar.xz -C root ./bin/busybox
chmod 755 root/bin/busybox

cp "$ROOT/initramfs/init" root/init
chmod 755 root/init

# Static fallback nodes are synthesized directly into the cpio below (the
# archive encodes device metadata; no local mknod is needed). devtmpfs or
# mdev covers the rest at boot.
FILELIST="$WORK/filelist.txt"
(cd root && find . | LC_ALL=C sort) > "$FILELIST"

python3 - "$FILELIST" <<'PY'
import gzip
import os
import stat
import struct
import sys

root = "root"
out_path = "diag-initramfs.cpio.gz"

def newc_header(ino, mode, uid, gid, nlink, mtime, filesize, devmajor,
                devminor, rdevmajor, rdevminor, name):
    namesize = len(name) + 1
    fields = [ino, mode, uid, gid, nlink, mtime, filesize, devmajor,
              devminor, rdevmajor, rdevminor, namesize, 0]
    return b"070701" + b"".join(f"{f & 0xffffffff:08x}".encode() for f in fields)

entries = []
with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.strip()
        if line in (".", ""):
            continue
        entries.append(line)

# Synthetic device nodes: (name, mode, major, minor). Inserted in sorted
# order among the real files; excluded if a real file already exists.
SYNTH_DEVS = [
    ("dev/console", 0o600, 5, 1),
    ("dev/null",    0o666, 1, 3),
    ("dev/zero",    0o666, 1, 5),
]
existing = {e[2:] if e.startswith("./") else e for e in entries}
synth = [s for s in SYNTH_DEVS if s[0] not in existing]

ino = 0
data = bytearray()

def pad4(buf):
    while len(buf) % 4:
        buf += b"\0"

def emit(name, mode, nlink, rdevmajor, rdevminor, payload):
    global ino, data
    ino += 1
    data += newc_header(ino, mode, 0, 0, nlink, 0, len(payload),
                        3, 1, rdevmajor, rdevminor, name)
    data += name.encode() + b"\0"
    pad4(data)
    data += payload
    pad4(data)

records = []
for rel in entries:
    path = os.path.join(root, rel)
    name = rel[2:] if rel.startswith("./") else rel
    st = os.lstat(path)
    mode = stat.S_IMODE(st.st_mode)
    rdevmajor = rdevminor = 0
    payload = b""
    nlink = 1
    if stat.S_ISDIR(st.st_mode):
        mode |= stat.S_IFDIR
        nlink = 2
    elif stat.S_ISLNK(st.st_mode):
        mode |= stat.S_IFLNK
        payload = os.readlink(path).encode()
    elif stat.S_ISCHR(st.st_mode):
        mode |= stat.S_IFCHR
        rdevmajor, rdevminor = os.major(st.st_rdev), os.minor(st.st_rdev)
    elif stat.S_ISBLK(st.st_mode):
        mode |= stat.S_IFBLK
        rdevmajor, rdevminor = os.major(st.st_rdev), os.minor(st.st_rdev)
    else:
        mode |= stat.S_IFREG
        with open(path, "rb") as fh:
            payload = fh.read()
    records.append((name, mode, nlink, rdevmajor, rdevminor, payload))

for n, m, maj, mnr in synth:
    records.append((n, stat.S_IFCHR | m, 1, maj, mnr, b""))

# Fully sorted emission keeps every parent directory ahead of its children.
records.sort(key=lambda r: r[0])
for name, mode, nlink, rdevmajor, rdevminor, payload in records:
    emit(name, mode, nlink, rdevmajor, rdevminor, payload)

data += newc_header(0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, "TRAILER!!!")
data += b"TRAILER!!!\0"
pad4(data)

with open(out_path, "wb") as fh:
    with gzip.GzipFile(filename="", mode="wb", fileobj=fh, mtime=0,
                       compresslevel=9) as gz:
        gz.write(bytes(data))
PY

echo "Built $OUT"
shasum -a 256 "$OUT"
