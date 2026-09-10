#!/usr/bin/env python3
# xwd2png.py — convert an XWD screenshot (from `xwd -root`) to PNG.
# No external deps (pure zlib PNG writer). Usage: xwd2png.py in.xwd out.png
import struct
import sys
import zlib

def main(src, dst):
    d = open(src, 'rb').read()
    hdr_sz, ver, pixfmt, depth, w, h = struct.unpack_from('>6I', d, 0)
    bpl = struct.unpack_from('>I', d, 48)[0]
    ncolors = struct.unpack_from('>I', d, 76)[0]
    img = d[hdr_sz + ncolors * 12:]
    if len(img) < bpl * h:
        raise SystemExit("truncated xwd")
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        row = img[y * bpl:(y + 1) * bpl]
        for x in range(w):
            b, g, r, _ = row[x * 4:x * 4 + 4]
            raw += bytes([r, g, b])
    def chunk(t, data):
        c = struct.pack('>I', len(data)) + t + data
        return c + struct.pack('>I', zlib.crc32(t + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 6))
           + chunk(b'IEND', b''))
    open(dst, 'wb').write(png)
    print(f"{dst}: {w}x{h}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
