#!/usr/bin/env python3
"""fbgrab.py — convert an NX563J fb0 raw dump to PNG (BGRX, stride 4352).

Usage:
  ssh -i work/nx563j_key root@10.42.0.1 'dd if=/dev/fb0 bs=4352 count=1920 2>/dev/null' \
      | python3 tools/fbgrab.py out.png
"""
import struct
import sys
import zlib

W, H, STRIDE = 1080, 1920, 4352


def png(path, rows):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rows)
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def main():
    data = sys.stdin.buffer.read()
    if len(data) < STRIDE * H:
        print(f"short read: {len(data)} bytes, want {STRIDE * H}", file=sys.stderr)
        sys.exit(1)
    rows = []
    for y in range(H):
        line = data[y * STRIDE : y * STRIDE + W * 4]
        row = bytearray(W * 3)
        for x in range(W):
            b, g, r = line[x * 4], line[x * 4 + 1], line[x * 4 + 2]
            row[x * 3 : x * 3 + 3] = bytes((r, g, b))
        rows.append(bytes(row))
    png(sys.argv[1], rows)


if __name__ == "__main__":
    main()
