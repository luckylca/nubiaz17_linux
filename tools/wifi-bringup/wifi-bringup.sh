#!/bin/sh
# /root/wifi-bringup.sh — NX563J Wi-Fi bring-up via stock Qualcomm userspace.
#
# The WCN3990 Wi-Fi firmware runs as protection domain wlan_pd under the
# modem. The modem only stays alive and announces wlan_pd when its
# expected AP-side QMI peers (rmt_storage/qmuxd/netmgrd + peripheral
# manager) are running. Those are bionic binaries on the stock vendor
# partition; run them under a minimal bionic runtime bind-mounted from
# the stock system partition (runtime APEX) — the Halium approach.
#
# Prereqs (on device):
#   /dev/sde41 (vendor) mounted ro at /tmp/vendor
#   /dev/sda9  (system SAR root) mounted ro at /tmp/system
#
# Usage: sh /root/wifi-bringup.sh

set -x
V=/tmp/vendor
S=/tmp/system/system
RT=$S/apex/com.android.runtime.release

# --- 1. bionic runtime at absolute Android paths -------------------------
mkdir -p /apex/com.android.runtime /system
mountpoint -q /apex/com.android.runtime || mount --bind $RT /apex/com.android.runtime
mountpoint -q /system || mount --bind $S /system

export LD_LIBRARY_PATH=/apex/com.android.runtime/lib64/bionic:/system/lib64:$V/lib64
export PATH=$V/bin:/system/bin:$PATH

# --- 2. make modem crashes survivable ------------------------------------
for s in /sys/bus/msm_subsys/devices/subsys*; do
	[ "$(cat $s/name)" = "modem" ] && echo related > $s/restart_level
done

# --- 2b. Android-style by-name partition links (rmt_storage needs
# modemst1/modemst2/fsc/fsg; ueventd makes these on stock) ---------------
mkdir -p /dev/block/bootdevice/by-name
for u in /sys/class/block/sd*/uevent; do
	dev=$(basename $(dirname $u))
	pn=$(grep -a "^PARTNAME=" $u | cut -d= -f2)
	[ -n "$pn" ] && ln -sf /dev/$dev /dev/block/bootdevice/by-name/$pn
done

# --- 3. start QMI/EFS peers before the modem boots -----------------------
# rmt_storage: modem EFS/file access (firmware_mnt, NV, calibration)
# qmuxd/netmgrd: QMI control/data peers the modem expects
# pd-mapper: protection-domain service map for wlan_pd discovery
# (keepalive wrappers: they exit when the modem bounces, restart them)
for d in rmt_storage netmgrd pd-mapper; do
	if [ -x $V/bin/$d ]; then
		setsid sh -c "while true; do $V/bin/$d >>/var/log/$d.log 2>&1; sleep 2; done" \
			>/dev/null 2>&1 &
		echo "keepalive started for $d"
	else
		echo "$d not present, skipping"
	fi
done
sleep 2

# --- 4. register the wlan driver (waits for FW ready) ---------------------
[ -e /dev/wlan ] || mknod /dev/wlan c 226 0
( echo ON > /dev/wlan ) &
sleep 1

# --- 5. boot the modem (hold the device open = keep it powered) ----------
# NOTE: busybox exec has no -a; mark the holder with a pidfile instead.
if [ ! -f /tmp/modem.hold.pid ] || ! kill -0 "$(cat /tmp/modem.hold.pid)" 2>/dev/null; then
	setsid sh -c 'exec 9<>/dev/subsys_modem; echo $$ > /tmp/modem.hold.pid; while true; do sleep 3600; done' \
		>/dev/null 2>&1 &
	sleep 1
fi
echo "modem holder pid: $(cat /tmp/modem.hold.pid 2>/dev/null)"

# --- 6. watch ------------------------------------------------------------
echo "watching for wlan0 (Ctrl-C to stop)..."
for i in $(seq 1 36); do
	if [ -d /sys/class/net/wlan0 ]; then
		echo "WLAN0 IS UP"
		ip link set wlan0 up
		exit 0
	fi
	sleep 5
done
echo "wlan0 did not appear; check dmesg and /var/log/*.log"
exit 1
