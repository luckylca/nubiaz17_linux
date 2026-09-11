#!/usr/bin/env python3
# inject.py — NX563J qcacld monitor-mode frame injection prober.
#
# Writes a crafted 802.11 frame (radiotap + payload) to the monitor
# interface via AF_PACKET.  With kernel patch 0009-qcacld-monitor-injection
# the driver strips radiotap and submits the frame to firmware mgmt TX
# through a hidden STA helper vdev.
#
# Default frame: broadcast probe request (safe, every STA sends these).
# A second device in monitor mode on the same channel must see it for
# the test to PASS (see README.md "Injection verification").
#
# Usage:
#   python3 inject.py [ifname] [count] [interval_ms]
#
# Frame SA: locally administered 02:4e:58:35:36:33 ("NX563"-ish), SSID
# element carries "NX563J-INJ-TEST" so the frame is unmistakable on a
# sniffer.
import socket
import struct
import sys
import time

IFACE = sys.argv[1] if len(sys.argv) > 1 else "wlan0"
COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 10
IVL_MS = int(sys.argv[3]) if len(sys.argv) > 3 else 100

SA = b"\x02\x4e\x58\x35\x36\x33"          # 02:4e:58:35:36:33 local
BCAST = b"\xff" * 6
SSID = b"NX563J-INJ-TEST"

# radiotap: v0, pad 0, len 8, present=0 (no fields)
rtap = struct.pack("<BBHI", 0, 0, 8, 0)

# 802.11 probe request: fc=0x0040, dur=0, da=bcast, sa=SA, bssid=bcast, seq=0
hdr = struct.pack("<HH", 0x0040, 0) + BCAST + SA + BCAST + struct.pack("<H", 0)
# SSID IE + supported rates IE (1-8 Mbps basic set)
ie_ssid = bytes([0, len(SSID)]) + SSID
ie_rates = bytes([1, 4]) + bytes([0x82, 0x84, 0x8b, 0x96])
frame = rtap + hdr + ie_ssid + ie_rates

s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
s.bind((IFACE, 0))

ok = 0
for i in range(COUNT):
    try:
        n = s.send(frame)
        if n == len(frame):
            ok += 1
        else:
            print(f"[{i}] short write {n}/{len(frame)}")
    except OSError as e:
        print(f"[{i}] send failed: {e}")
        break
    time.sleep(IVL_MS / 1000.0)

print(f"sent {ok}/{COUNT} probe-req (len {len(frame)}) on {IFACE}")
print("host-side OK means the driver accepted the frames; PASS requires")
print("a second sniffer on the same channel seeing SSID 'NX563J-INJ-TEST'.")
