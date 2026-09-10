#!/bin/sh
# thermal-ctl.sh — NX563J thermal SAFETY daemon (MSM8998 / SD835).
#
# User decision: keep ONLY the "no solder-joint damage" safety line — no
# comfort throttling. So exactly two protections, nothing else:
#
#   1. SoC CRIT: hottest tsens sensor >= CRIT (0.1 C units) caps BOTH
#      clusters to CRIT_BIG / CRIT_LITTLE and forces charging OFF via the
#      /tmp/thermal-hold file (charge-ctl.sh respects it). Caps and hold
#      release when the hottest sensor drops below CRIT - HYST.
#   2. Battery: power_supply "temp" >= BATT_STOP (0.1 C units) forces
#      charging off until <= BATT_START.
#
# It also sets the cpufreq governor once at start (GOVERNOR=interactive):
# not a throttle — the downstream SD835 norm, idles far cooler than
# performance, full speed on demand. Set GOVERNOR= empty to skip.
#
# Overrides in /etc/thermal-ctl.conf. Temps in 0.1 C, freqs in kHz.
# Runs forever; started once at boot from rc.boot.ubuntu with setsid.
# Logs transitions to /var/log/thermal-ctl.log.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
CONF=/etc/thermal-ctl.conf
LOG=/var/log/thermal-ctl.log
HOLD=/tmp/thermal-hold
PS=/sys/class/power_supply/battery

INTERVAL=5
GOVERNOR=interactive

# the one and only SoC safety line (0.1 C) + release hysteresis
CRIT=850
HYST=50
CRIT_BIG=1056000
CRIT_LITTLE=1094400

# battery charge guard (0.1 C — power_supply "temp" is tenths of a degree)
BATT_STOP=450
BATT_START=430

[ -r "$CONF" ] && . "$CONF"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null; }

# hottest tsens reading, in 0.1 C (tsens report tenths; millidegree zones
# like battery/pm8998_tz are filtered out by the <1000 check)
soc_temp() {
  max=0
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(cat "$z" 2>/dev/null) || continue
    case "$t" in ''|*[!0-9]*) continue;; esac
    [ "$t" -lt 1000 ] && [ "$t" -gt "$max" ] && max=$t
  done
  echo "$max"
}

batt_temp() { cat "$PS/temp" 2>/dev/null; }

cap_cluster() { # $1=first cpu of the 4-core cluster, $2=khz
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_max_freq; do
    case "$c" in
      *cpu$1/*|*cpu$(($1+1))/*|*cpu$(($1+2))/*|*cpu$(($1+3))/*)
        [ -w "$c" ] && echo "$2" > "$c" 2>/dev/null ;;
    esac
  done
}

restore_all() {
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    [ -w "$c/scaling_max_freq" ] && \
      cat "$c/cpuinfo_max_freq" > "$c/scaling_max_freq" 2>/dev/null
  done
}

set_governor() {
  [ -n "$GOVERNOR" ] || return 0
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
    [ -w "$c" ] && echo "$GOVERNOR" > "$c" 2>/dev/null
  done
  log "governor -> $GOVERNOR"
}

charge_hold_on() {
  [ -e "$HOLD" ] && return 0
  echo 0 > "$PS/charging_enabled" 2>/dev/null
  : > "$HOLD"
  log "charging FORCED OFF (thermal hold)"
}

charge_hold_off() {
  [ -e "$HOLD" ] || return 0
  rm -f "$HOLD"
  log "thermal hold released (charge-ctl may resume)"
}

trap 'restore_all; charge_hold_off; log "thermal-ctl exit, caps restored"; exit 0' TERM INT

set_governor
crit=0
log "thermal-ctl start (CRIT=$CRIT hyst=$HYST batt=$BATT_STOP/$BATT_START interval=${INTERVAL}s gov=${GOVERNOR:-unchanged})"

while true; do
  soc=$(soc_temp)
  bat=$(batt_temp)
  case "$soc" in ''|*[!0-9]*) soc=0;; esac
  case "$bat" in ''|*[!0-9]*) bat=0;; esac

  if [ "$crit" -eq 0 ] && [ "$soc" -ge "$CRIT" ]; then
    crit=1
    cap_cluster 4 "$CRIT_BIG"; cap_cluster 0 "$CRIT_LITTLE"
    log "CRIT  soc=${soc} batt=${bat}: big -> $CRIT_BIG little -> $CRIT_LITTLE"
  elif [ "$crit" -eq 1 ] && [ "$soc" -lt $((CRIT - HYST)) ]; then
    crit=0
    restore_all
    log "CLEAR soc=${soc} batt=${bat}: full speed restored"
  fi

  if [ "$crit" -eq 1 ] || { [ "$bat" -gt 0 ] && [ "$bat" -ge "$BATT_STOP" ]; }; then
    charge_hold_on
  elif [ -e "$HOLD" ] && [ "$crit" -eq 0 ] && \
       { [ "$bat" -eq 0 ] || [ "$bat" -le "$BATT_START" ]; }; then
    charge_hold_off
  fi

  sleep "$INTERVAL"
done
