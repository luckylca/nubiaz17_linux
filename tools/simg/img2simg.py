#!/usr/bin/env python3
"""img2simg.py — convert a raw ext4 image to Android sparse format.

Android sparse image format (as produced by AOSP img2simg):
  header:  <IHHHHIIII  magic=0xed26ff3a, major=1, minor=0,
           file_hdr_sz=28, chunk_hdr_sz=12, blk_sz, total_blks,
           total_chunks, image_checksum(0=unused)
  chunk:   <HHII       type, reserved(0), chunk_sz (blocks), total_sz (bytes)
  types:   0xCAC1 raw (data follows), 0xCAC2 fill (4-byte value follows),
           0xCAC3 don't-care (no data), 0xCAC4 crc32

Zero blocks become don't-care chunks; everything else is coalesced into
raw chunks (capped to keep memory bounded).

Usage: img2simg.py INPUT.raw OUTPUT.sparse
"""
import struct
import sys

MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE = 0xCAC1, 0xCAC2, 0xCAC3
BLK = 4096
MAX_RAW_CHUNK_BLKS = 4096  # 16 MiB per raw chunk


def main(src_path, dst_path):
    with open(src_path, "rb") as f:
        data = f.read()
    if len(data) % BLK:
        raise SystemExit(f"input size {len(data)} not a multiple of {BLK}")
    total_blks = len(data) // BLK

    # First pass: classify blocks into runs
    runs = []  # (type, start_blk, nblk, fill_val)
    i = 0
    while i < total_blks:
        blk = data[i * BLK:(i + 1) * BLK]
        if blk == b"\0" * BLK:
            j = i
            while j < total_blks and data[j * BLK:(j + 1) * BLK] == b"\0" * BLK:
                j += 1
            runs.append((DONT_CARE, i, j - i, None))
            i = j
        else:
            j = i
            while (j < total_blks
                   and data[j * BLK:(j + 1) * BLK] != b"\0" * BLK
                   and j - i < MAX_RAW_CHUNK_BLKS):
                j += 1
            runs.append((RAW, i, j - i, None))
            i = j

    with open(dst_path, "wb") as out:
        out.write(struct.pack("<IHHHHIIII", MAGIC, 1, 0, 28, 12,
                              BLK, total_blks, len(runs), 0))
        for typ, start, nblk, _ in runs:
            if typ == DONT_CARE:
                out.write(struct.pack("<HHII", DONT_CARE, 0, nblk, 12))
            else:
                payload = data[start * BLK:(start + nblk) * BLK]
                out.write(struct.pack("<HHII", RAW, 0, nblk, 12 + len(payload)))
                out.write(payload)
    print(f"{src_path} ({len(data)} B) -> {dst_path}: "
          f"{len(runs)} chunks, {total_blks} blocks")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
