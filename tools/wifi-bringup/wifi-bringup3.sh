#!/bin/sh
# /root/wifi-bringup3.sh — NX563J Wi-Fi bring-up v3 (stock-faithful variant)
#
# v3 differences vs v2 (from stock boot forensics 2026-09-08):
#   - stock NEVER loads the IPA uC and never binds the IPA smp2p children
#     before wlan_pd starts (uC stays unloaded for the whole stock boot);
#     v2 did both before the modem boot. Step removed entirely.
#   - stock /dev nodes (null/urandom/...) are world-accessible; our mdev
#     leaves them 0660 root:root (and /dev/null was once a regular file!),
#     which silently crash-loops pd-mapper (uid 1000) and breaks other
#     daemons. Fix perms BEFORE starting any daemon.
#   - vndservicemanager runs before pm-service (HIDL registration).
#   - fake logd (/root/logcatd) captures bionic liblog output to
#     /var/log/logcatd.log (pmsg/logd are absent here).
set -x

# --- -1. base device node sanity (BEFORE anything else) --------------------
[ -c /dev/null ] || { rm -f /dev/null; mknod /dev/null c 1 3; }
chmod 0666 /dev/null /dev/zero /dev/full /dev/random /dev/urandom 2>/dev/null

# fake logd for bionic daemons (liblog -> /dev/socket/logdw)
[ -x /root/logcatd ] && ! pidof logcatd >/dev/null 2>&1 && \
	setsid /root/logcatd >> /var/log/logcatd.log 2>&1 &

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

# --- 5. REMOVED (v3): no IPA smp2p bind, no IPA uC load --------------------
# Stock boots wlan_pd with the uC unloaded; pre-loading it changes the
# modem's QMI_IPA_INIT path. Keep the IPA block untouched.

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
# pm-service registers a HIDL service: vndservicemanager must exist first
if ! pidof vndservicemanager >/dev/null 2>&1; then
	setsid sh -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH /vendor/bin/vndservicemanager /dev/vndbinder >>/var/log/vndsm.log 2>&1" \
		>/dev/null 2>&1 &
	sleep 1
fi
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
