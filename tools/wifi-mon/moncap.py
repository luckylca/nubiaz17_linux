#!/usr/bin/env python3
# moncap.py — NX563J qcacld monitor-mode capture verifier.
#
# Opens a raw AF_PACKET socket on the monitor interface and counts frames.
# In monitor mode qcacld delivers 802.11 frames prefixed with a radiotap
# header (magic 0x00 0x00 at bytes 0-1 with version 0). We report:
#   - total frames seen
#   - how many start with a valid radiotap header
#   - the 802.11 frame-type histogram (beacon / data / probe / ...)
#
# Usage: python3 moncap.py [ifname] [seconds]
import socket
import struct
import sys
import time
import collections

IFACE = sys.argv[1] if len(sys.argv) > 1 else "wlan0"
SECS = float(sys.argv[2]) if len(sys.argv) > 2 else 15

s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
s.bind((IFACE, 0))
s.settimeout(1.0)

FTYPE = {0: "mgmt", 1: "ctrl", 2: "data"}
SUB = {
    (0, 8): "beacon", (0, 4): "probe-req", (0, 5): "probe-rsp",
    (0, 11): "auth", (0, 0): "assoc-req", (0, 12): "deauth",
}

total = 0
rtap_ok = 0
hist = collections.Counter()
t0 = time.time()
while time.time() - t0 < SECS:
    try:
        pkt = s.recv(65535)
    except socket.timeout:
        continue
    total += 1
    if len(pkt) < 10:
        hist["short"] += 1
        continue
    # radiotap: version(0) pad(0) len(u16) ...
    if pkt[0] == 0 and pkt[1] == 0:
        rt_len = struct.unpack_from("<H", pkt, 2)[0]
        if 8 <= rt_len <= len(pkt) - 10:
            rtap_ok += 1
            fc = pkt[rt_len:]
            if len(fc) >= 2:
                ftype = (fc[0] >> 2) & 3
                fsub = (fc[0] >> 4) & 15
                name = SUB.get((ftype, fsub), FTYPE.get(ftype, str(ftype)))
                hist[name] += 1
                continue
    hist["non-radiotap"] += 1

print("iface=%s secs=%.0f" % (IFACE, SECS))
print("total_frames=%d radiotap_ok=%d" % (total, rtap_ok))
for k, v in hist.most_common():
    print("  %-12s %d" % (k, v))
print("VERDICT: %s" % ("MONITOR MODE WORKING" if rtap_ok > 0 else "no radiotap frames"))
