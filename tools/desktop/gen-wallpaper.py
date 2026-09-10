#!/usr/bin/env python3
# gen-wallpaper.py — generate /usr/share/backgrounds/nx-ubuntu.png on-device.
#
# Ubuntu-style diagonal gradient (dark aubergine -> aubergine -> orange
# glow), 1920x1080 landscape. Pure stdlib (zlib), no image assets, no PIL.
import struct
import zlib

W, H = 1920, 1080
C1 = (44, 0, 30)     # 2C001E dark aubergine (top-left)
C2 = (119, 33, 111)  # 77216F aubergine (mid)
C3 = (233, 84, 32)   # E95420 ubuntu orange (bottom-right glow)

rows = []
for y in range(H):
    row = bytearray([0])  # PNG filter byte: none
    fy = y / H
    for x in range(W):
        t = x / W * 0.55 + fy * 0.45
        if t < 0.65:
            f = t / 0.65
            a, b = C1, C2
        else:
            f = (t - 0.65) / 0.35
            a, b = C2, C3
        row += bytes(int(a[i] + (b[i] - a[i]) * f) for i in range(3))
    rows.append(bytes(row))
raw = b"".join(rows)


def chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data)))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 6))
       + chunk(b"IEND", b""))
with open("/usr/share/backgrounds/nx-ubuntu.png", "wb") as f:
    f.write(png)
print("wallpaper written:", len(png), "bytes")
