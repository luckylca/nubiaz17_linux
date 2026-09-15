#!/bin/sh
# restore-mission.sh — safe con_mode 4 -> 0 switch-back after injection.
#
# 2026-09-15 hard lesson: writing con_mode=0 while the injection helper
# vdev still exists crashes the WLAN firmware (err_qdi: Asserted in
# ratectrl_11ac_, Root PD crashed, subsystem-restart cascade, full hang).
# The v6 teardown fix only covers switch-back AFTER cleanup completes.
#
# This script waits for "mon-inject: helper vdev .* destroyed" in dmesg
# (with a hard timeout), only then writes con_mode=0, and restarts
# wpa_supplicant afterwards.
#
# Usage: sh restore-mission.sh
set -u

echo "== waiting for helper vdev teardown (max 150s)"
ok=0
for i in $(seq 1 30); do
  # only look at dmesg lines from THIS boot, after the last injection
  if dmesg | grep -q "mon-inject: helper vdev .* destroyed"; then
    ok=1; break
  fi
  sleep 5
done

if [ "$ok" != 1 ]; then
  echo "FAIL: helper vdev not destroyed within 150s — DO NOT write con_mode."
  echo "Safest recovery: leave it, or reboot (echo b > /proc/sysrq-trigger)."
  exit 1
fi

# settle a moment after teardown
sleep 5

echo "== con_mode -> 0"
wok=0
for t in 1 2 3 4 5; do
  echo 0 > /sys/module/wlan/parameters/con_mode 2>/dev/null && { wok=1; break; }
  echo "con_mode attempt $t EIO, retry in 4s"
  sleep 4
done
[ "$wok" = 1 ] || { echo "FAIL: con_mode write keeps failing; do NOT force. Reboot."; exit 1; }
sleep 4
[ "$(cat /sys/module/wlan/parameters/con_mode)" = 0 ] || {
  echo "FAIL: con_mode still $(cat /sys/module/wlan/parameters/con_mode)"; exit 1; }

ip link set wlan0 up 2>/dev/null
(wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211 2>/dev/null &)
sleep 2
wpa_cli -i wlan0 status 2>/dev/null | head -2
echo "== mission mode restored"
