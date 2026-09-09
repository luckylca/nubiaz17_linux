#!/bin/sh
# charge-ctl.sh — NX563J ACCA-style charge limiter (pmi8998 / qpnp-smb2).
#
# Keeps the battery between two thresholds by toggling the kernel's
# charging_enabled control:
#     capacity >= HIGH  ->  charging_enabled=0  (stop charging)
#     capacity <= LOW   ->  charging_enabled=1  (resume charging)
# between them it holds whatever state it last set (hysteresis), so the
# charger is not flapped on every percent.
#
# Thresholds are read from /etc/charge-ctl.conf (HIGH=, LOW=) if present,
# else default 90 / 80. Verified on device: writing charging_enabled flips
# POWER_SUPPLY_STATUS between "Charging" and "Not charging" immediately.
#
# Runs forever; meant to be started once at boot (rc.boot.ubuntu) with
# setsid. Logs transitions to /var/log/charge-ctl.log.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
PS=/sys/class/power_supply/battery
CONF=/etc/charge-ctl.conf
LOG=/var/log/charge-ctl.log
HIGH=90
LOW=80
INTERVAL=30

[ -r "$CONF" ] && . "$CONF"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null; }

[ -w "$PS/charging_enabled" ] || { log "FATAL: $PS/charging_enabled not writable"; exit 1; }

log "charge-ctl start (HIGH=$HIGH LOW=$LOW interval=${INTERVAL}s)"

while true; do
  cap=$(cat "$PS/capacity" 2>/dev/null)
  en=$(cat "$PS/charging_enabled" 2>/dev/null)
  online=$(cat "$PS/online" 2>/dev/null || cat /sys/class/power_supply/usb/online 2>/dev/null)
  case "$cap" in ''|*[!0-9]*) cap=-1;; esac

  if [ "$cap" -ge 0 ]; then
    if [ "$en" = "1" ] && [ "$cap" -ge "$HIGH" ]; then
      echo 0 > "$PS/charging_enabled" 2>/dev/null \
        && log "STOP  charging at ${cap}% (>= $HIGH)"
    elif [ "$en" = "0" ] && [ "$cap" -le "$LOW" ]; then
      echo 1 > "$PS/charging_enabled" 2>/dev/null \
        && log "START charging at ${cap}% (<= $LOW)"
    fi
  fi
  sleep "$INTERVAL"
done
