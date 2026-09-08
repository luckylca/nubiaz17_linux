#!/bin/sh
# /root/wifi-bringup2.sh — NX563J Wi-Fi bring-up v2 (full recipe, correct order)
#
# Chain (all proven on device 2026-09-08):
#   bionic runtime mounts -> firmware staging -> kernel perms -> irsc ->
#   smp2p bind -> IPA uC FW -> QMI daemons -> modem hold -> /dev/wlan ON
#
# Kernel facts this script works around:
#   - firmware_class.path must be written WITHOUT trailing newline
#     (sysfs write keeps the '\n' in fw_path_para -> silent open failure)
#   - ipa3_smp2p_probe returns -ENXIO (not EPROBE_DEFER) when it races
#     ahead of ipa3_ctx -> smp2p devices never bind -> bind them by hand
#   - IPA init only completes after the ipa_fws uC firmware is loaded,
#     triggered by writing to /dev/ipa (stock: a daemon does this)
#   - rmt_storage serves the modem EFS via /dev/uio0 (0660 root:root by
#     default; the daemon drops to uid 9999 -> needs 0666)
#   - netmgrd reads /system/vendor/etc/data/netmgr_config.xml (needs the
#     /system + /vendor bind mounts) and opens /dev/diag as uid 1001
#   - the WCN3990 runs as wlan_pd under the modem; the modem must boot
#     with its full expected AP-side peer set present
set -x

# --- 0. base mounts (idempotent) ------------------------------------------
mkdir -p /tmp/vendor /tmp/system
mountpoint -q /tmp/vendor || mount -o ro /dev/sde41 /tmp/vendor
mountpoint -q /tmp/system || mount -o ro /dev/sda9 /tmp/system
mkdir -p /vendor /system /apex/com.android.runtime
mountpoint -q /vendor || mount --bind /tmp/vendor /vendor
mountpoint -q /system || mount --bind /tmp/system/system /system
mountpoint -q /apex/com.android.runtime || \
	mount --bind /system/apex/com.android.runtime.release /apex/com.android.runtime
mkdir -p /vendor/firmware_mnt
mountpoint -q /vendor/firmware_mnt || mount -o ro /dev/sde10 /vendor/firmware_mnt

export LD_LIBRARY_PATH=/apex/com.android.runtime/lib64/bionic:/apex/com.android.runtime/lib64:/system/lib64:/system/lib64/vndk-29:/system/lib64/hw:/vendor/lib64:/vendor/lib64/hw
export PATH=/vendor/bin:/system/bin:$PATH

# --- 1. firmware staging on rootfs (visible from any context) -------------
mkdir -p /fwimage
[ -e /fwimage/modem.mdt ] || cp /vendor/firmware_mnt/image/* /fwimage/
cp -n /vendor/firmware/ipa_fws.* /fwimage/ 2>/dev/null
echo -n /fwimage > /sys/module/firmware_class/parameters/path

# --- 2. device node perms --------------------------------------------------
chmod 0666 /dev/diag /dev/uio0 2>/dev/null

# --- 2b. Android by-name links (rmt_storage EFS partitions) ----------------
mkdir -p /dev/block/bootdevice/by-name
for u in /sys/class/block/sd*/uevent; do
	dev=$(basename $(dirname $u))
	pn=$(grep -a "^PARTNAME=" $u | cut -d= -f2)
	[ -n "$pn" ] && ln -sf /dev/$dev /dev/block/bootdevice/by-name/$pn
done

# --- 3. modem crash containment --------------------------------------------
for s in /sys/bus/msm_subsys/devices/subsys*; do
	[ "$(cat $s/name)" = "modem" ] && echo related > $s/restart_level
done

# --- 4. IPC router security config (stops "waiting for IPC Security Conf") -
/vendor/bin/irsc_util /vendor/etc/sec_config

# --- 5. IPA: bind smp2p children, then trigger uC firmware load ------------
echo "1e00000.qcom,ipa:qcom,smp2pgpio_map_ipa_1_out" > /sys/bus/platform/drivers/ipa/bind 2>/dev/null
echo "1e00000.qcom,ipa:qcom,smp2pgpio_map_ipa_1_in"  > /sys/bus/platform/drivers/ipa/bind 2>/dev/null
echo 1 > /dev/ipa
sleep 3

# --- 6. QMI / peripheral daemons (keepalive) --------------------------------
kd() { # kd <name> [args...]
	name=$1; shift
	setsid sh -c "while true; do LD_LIBRARY_PATH=$LD_LIBRARY_PATH /vendor/bin/$name \$@ >>/var/log/$name.log 2>&1; sleep 2; done" \
		>/dev/null 2>&1 &
	echo "keepalive: $name"
}
kd rmt_storage
kd netmgrd
kd cnd
kd pd-mapper
kd tftp_server
kd pm-service
kd time_daemon
kd ipacm
sleep 2
kd pm-proxy
# cnss-daemon wants -n (no daemonize) -l (logcat); run foreground-logged
setsid sh -c "while true; do LD_LIBRARY_PATH=$LD_LIBRARY_PATH /vendor/bin/cnss-daemon -n -dd >>/var/log/cnss-daemon.log 2>&1; sleep 2; done" \
	>/dev/null 2>&1 &
echo "keepalive: cnss-daemon"

# --- 7. register wlan driver (waits for FW ready) ---------------------------
[ -e /dev/wlan ] || mknod /dev/wlan c 226 0
( echo ON > /dev/wlan ) &
sleep 1

# --- 8. boot the modem (hold open = powered) --------------------------------
if [ ! -f /tmp/modem.hold.pid ] || ! kill -0 "$(cat /tmp/modem.hold.pid 2>/dev/null)" 2>/dev/null; then
	setsid sh -c 'exec 9<>/dev/subsys_modem; echo $$ > /tmp/modem.hold.pid; while true; do sleep 3600; done' \
		>/dev/null 2>&1 &
fi

# --- 9. watch ----------------------------------------------------------------
echo "watching for wlan0 ..."
for i in $(seq 1 60); do
	if [ -d /sys/class/net/wlan0 ]; then
		echo "WLAN0 IS UP"
		ip link set wlan0 up
		exit 0
	fi
	sleep 5
done
echo "wlan0 did not appear; check dmesg and /var/log/*.log"
exit 1
