#!/bin/sh
# /root/wifi-bringup4.sh — NX563J Wi-Fi+BT bring-up v4 (PROVEN 2026-09-08:
# wlan0 + wlan1 + p2p0 created, 2.4/5 GHz scan returns 11 networks;
# BT TLV download + chip MAC proven 2026-09-09)
#
# Proven chain: perms fix -> mounts (+persist!) -> fw staging (both roots!)
#   -> irsc -> IPA uC load -> daemons (tftp_server with working RFS!)
#   -> modem boot -> QMI_IPA_INIT -> wlan_pd indication -> FW ready
#   -> qcacld probe -> wlan0
#
# Hard-won facts (each cost a boot cycle):
#   - /dev/null was once a 35-byte REGULAR FILE and mdev leaves
#     null/random/urandom 0660 root:root -> pd-mapper (uid 1000) crash-loops
#     silently. Fix perms BEFORE starting any daemon.
#   - persist (/dev/sda2) MUST be mounted RW at /mnt/vendor/persist BEFORE
#     tftp_server starts: the modem's RFS check writes
#     /vendor/rfs/msm/mpss/readwrite/server_check.txt (symlink into persist).
#     If it fails, the modem boots fine, answers QMI_IPA_INIT, then NEVER
#     starts wlan_pd (no servreg indication, no WLFW 0x45 in the router).
#     This was THE blocker for wlan_pd.
#   - On MSM8998 (IPA 3.0, GSI) ipa3_post_init is deferred until the ipa_fws
#     uC is loaded via a /dev/ipa write; without it rmnet QMI never registers
#     and QMI_IPA_INIT is never sent (v3 "no uC like stock" experiment:
#     DISPROVEN on this kernel).
#   - qcacld's hdd_parse_config_ini request_firmware() runs on a KERNEL
#     workqueue whose fs root is the INITRAMFS, not our chroot. Firmware
#     files must be staged under /proc/1/root/fwimage/... as well as the
#     chroot /fwimage, or the request falls into the unanswered usermode
#     helper, hangs 120s+, and the FW watchdog kills the probe (-22).
#   - fake logd (/root/logcatd) captures bionic liblog output to
#     /var/log/logcatd.log (pmsg/logd are absent here).
#   - Modem bounce without reboot: kill -9 the process holding
#     /dev/subsys_modem (pm-service); its keepalive restarts it and the
#     modem re-boots. wlan_pd + FW + probe all re-run cleanly.
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
# persist: REQUIRED before tftp_server (modem RFS check gates wlan_pd!)
mkdir -p /mnt/vendor/persist
mountpoint -q /mnt/vendor/persist || mount -t ext4 -o rw /dev/sda2 /mnt/vendor/persist

export LD_LIBRARY_PATH=/apex/com.android.runtime/lib64/bionic:/apex/com.android.runtime/lib64:/system/lib64:/system/lib64/vndk-29:/system/lib64/hw:/vendor/lib64:/vendor/lib64/hw
export PATH=/vendor/bin:/system/bin:$PATH

# --- 1. firmware staging (BOTH fs roots: chroot AND initramfs) -------------
mkdir -p /fwimage
[ -e /fwimage/modem.mdt ] || cp /vendor/firmware_mnt/image/* /fwimage/
cp -n /vendor/firmware/ipa_fws.* /fwimage/ 2>/dev/null
echo -n /fwimage > /sys/module/firmware_class/parameters/path
# qcacld ini/mac: requested from kworker context (initramfs root!)
mkdir -p /fwimage/wlan/qca_cld /proc/1/root/fwimage/wlan/qca_cld
cp /vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini /fwimage/wlan/qca_cld/ 2>/dev/null
cp /vendor/firmware/wlan/qca_cld/wlan_mac.bin /fwimage/wlan/qca_cld/ 2>/dev/null
cp /fwimage/wlan/qca_cld/* /proc/1/root/fwimage/wlan/qca_cld/ 2>/dev/null

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
# REQUIRED on MSM8998/GSI: only after ipa_fws loads does ipa3_post_init run
# (init_completion_obj + ipa_ready callbacks -> rmnet QMI service registers).
echo "1e00000.qcom,ipa:qcom,smp2pgpio_map_ipa_1_out" > /sys/bus/platform/drivers/ipa/bind 2>/dev/null
echo "1e00000.qcom,ipa:qcom,smp2pgpio_map_ipa_1_in"  > /sys/bus/platform/drivers/ipa/bind 2>/dev/null
echo 1 > /dev/ipa
sleep 3

# --- 5b. BT rails up BEFORE chip POR (REQUIRED for Bluetooth) ---------------
# The WCN3990's BT block is only released at chip POR when its rails are
# already on. The chip PORs with the modem boot (step 8), so unblock the
# btpower rfkill here. Found 2026-09-09: with rails off at POR the BT block
# never answers on /dev/ttyHS0 (all rails/clock/pins verified stock-identical;
# rails-on + modem bounce -> TLV download succeeds, MAC 00:a0:c6:c3:c9:3a).
for r in /sys/class/rfkill/rfkill*; do
	[ "$(cat $r/type 2>/dev/null)" = "bluetooth" ] && echo 1 > $r/state
done
mkdir -p /bt_firmware
mountpoint -q /bt_firmware || mount -o ro /dev/sde22 /bt_firmware 2>/dev/null

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
		# supplicant for scan/associate (config: /etc/wpa_supplicant/wpa_supplicant.conf)
		mkdir -p /run/wpa_supplicant
		pidof wpa_supplicant >/dev/null 2>&1 || \
			setsid wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211 \
				>>/var/log/wpa_supplicant.log 2>&1 &
		# DHCP once associated (wait up to 5 min for slow first association)
		setsid sh -c 'for i in $(seq 1 150); do
			wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state=COMPLETED" && {
				echo "associated, running udhcpc" >>/var/log/udhcpc-wlan0.log
				udhcpc -i wlan0 -n -q >>/var/log/udhcpc-wlan0.log 2>&1
				exit 0
			}
			sleep 2
		done
		echo "gave up waiting for association" >>/var/log/udhcpc-wlan0.log' >/dev/null 2>&1 &
		# BT SoC init (TLV rampatch+NVM over /dev/ttyHS0, chip FW is ready now)
		if [ -x /vendor/bin/hci_qcomm_init ]; then
			setsid sh -c "LD_LIBRARY_PATH=$LD_LIBRARY_PATH /vendor/bin/hci_qcomm_init -e -N \
				>>/var/log/hci_qcomm_init.log 2>&1" &
		fi
		exit 0
	fi
	sleep 5
done
echo "wlan0 did not appear; check dmesg and /var/log/*.log"
exit 1
