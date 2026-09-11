#!/bin/sh
# inject-test.sh — on-device injection test (NX563J, qcacld monitor mode).
#
# Run over usb0 ssh (Wi-Fi STA will go down!).  Sequence:
#   1. stop STA userspace, switch con_mode 0 -> 4
#   2. bring monitor wlan0 up on the requested channel
#   3. run inject.py, then dump the mon-inject dmesg lines
#
# Host-side "sent N/N" only proves the driver accepted frames.  Real PASS
# needs a second sniffer on the same channel seeing SSID NX563J-INJ-TEST.
#
# Usage: sh inject-test.sh [channel] [count]
set -u
CH=${1:-36}
COUNT=${2:-10}

echo "== pre: kernel = $(uname -r)"
uname -a | grep -q . || exit 1

pkill wpa_supplicant 2>/dev/null; pkill dhclient 2>/dev/null
ip link set wlan0 down 2>/dev/null
sleep 1

echo "== switch con_mode -> 4 (monitor)"
echo 4 > /sys/module/wlan/parameters/con_mode || { echo "FAIL: con_mode write"; exit 1; }
sleep 4
iw dev | grep -A2 wlan0

ip link set wlan0 up || { echo "FAIL: ifup"; exit 1; }
iw dev wlan0 set channel "$CH" || { echo "FAIL: set channel $CH"; exit 1; }
sleep 1

dmesg -c > /tmp/inject-dmesg-before.txt 2>/dev/null || dmesg > /tmp/inject-dmesg-before.txt

echo "== inject $COUNT frames on channel $CH"
python3 /root/inject.py wlan0 "$COUNT" 100
sleep 2

echo "== mon-inject dmesg:"
dmesg | grep -i "mon-inject\|mon tx" || echo "(no mon-inject lines — driver silent)"

echo
echo "== next: check the second sniffer for SSID NX563J-INJ-TEST"
echo "== to restore:  ip link set wlan0 down; echo 0 > /sys/module/wlan/parameters/con_mode; sleep 4; sh /root/wifi-bringup4.sh"
