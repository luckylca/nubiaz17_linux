#!/bin/sh
# thermal-ctl.sh — NX563J userspace thermal manager (MSM8998 / SD835).
#
# The downstream kernel exposes the sensors (tsens_tz_sensor*, battery,
# pm8998_tz) and the knobs (cpufreq scaling_max_freq, qpnp-smb2
# charging_enabled) but nothing in this rootfs acts on them — this daemon
# closes that loop:
#
#   * reads the hottest tsens sensor (units: 0.1 C) every INTERVAL seconds
#   * tiers with hysteresis, capping the big cluster (cpu4-7) first, then
#     the little cluster (cpu0-3):
#         < WARM    : full speed (restore cpuinfo_max_freq)
#         >= WARM   : big  -> WARM_BIG
#         >= HOT    : big  -> HOT_BIG,  little -> HOT_LITTLE
#         >= CRIT   : big  -> CRIT_BIG, little -> CRIT_LITTLE
#                     + charging forced OFF (hold file) until < CRIT-HYST
#   * battery guard: batt >= BATT_STOP (millideg C) also forces charging
#     off until <= BATT_START, independent of SoC tier
#   * optionally sets the cpufreq governor at start (GOVERNOR=; empty =
#     leave alone). performance pegs the clocks and idles hot (~70 C on
#     tsens); interactive is the downstream SD835 norm and idles much
#     cooler, so that is the default.
#
# Charging interplay with charge-ctl.sh: this daemon never RE-enables
# charging. It stops charging and drops /tmp/thermal-hold; charge-ctl.sh
# must skip its own "START" while that file exists, and will resume
# charging on its normal hysteresis once the hold is gone.
#
# All thresholds/frequencies can be overridden in /etc/thermal-ctl.conf.
# Temps are in 0.1 C units (tsens native), frequencies in kHz.
# Runs forever; started once at boot from rc.boot.ubuntu with setsid.
# Logs tier transitions to /var/log/thermal-ctl.log.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
CONF=/etc/thermal-ctl.conf
LOG=/var/log/thermal-ctl.log
HOLD=/tmp/thermal-hold
PS=/sys/class/power_supply/battery

INTERVAL=5
GOVERNOR=interactive

# tier thresholds (0.1 C) and hysteresis
WARM=720
HOT=780
CRIT=850
HYST=30

# frequency caps (kHz) — must exist in scaling_available_frequencies
WARM_BIG=1958400
HOT_BIG=1497600
HOT_LITTLE=1555200
CRIT_BIG=1056000
CRIT_LITTLE=1094400

# battery charge guard (0.1 C — power_supply "temp" is tenths of a degree,
# NOT millidegrees like the thermal_zone of the same name)
BATT_STOP=450
BATT_START=430

[ -r "$CONF" ] && . "$CONF"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG" 2>/dev/null; }

# hottest tsens reading, in 0.1 C; empty if the sensors vanish
soc_temp() {
  max=0
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(cat "$z" 2>/dev/null) || continue
    case "$t" in ''|*[!0-9]*) continue;; esac
    # tsens sensors report 0.1 C (3-4 digits); skip millidegree zones
    [ "$t" -lt 1000 ] && [ "$t" -gt "$max" ] && max=$t
  done
  echo "$max"
}

batt_temp() { cat "$PS/temp" 2>/dev/null; }

cap_cluster() { # $1=first cpu, $2=khz
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_max_freq; do
    case "$c" in
      *cpu$1/*|*cpu$(($1+1))/*|*cpu$(($1+2))/*|*cpu$(($1+3))/*)
        [ -w "$c" ] && echo "$2" > "$c" 2>/dev/null ;;
    esac
  done
}

restore_cluster() { # $1=first cpu
  for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
    case "$c" in
      *cpu$1/*|*cpu$(($1+1))/*|*cpu$(($1+2))/*|*cpu$(($1+3))/*)
        [ -w "$c/scaling_max_freq" ] && \
          cat "$c/cpuinfo_max_freq" > "$c/scaling_max_freq" 2>/dev/null ;;
    esac
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

# clean up on kill so a manual restart never leaves caps stuck
trap 'restore_cluster 0; restore_cluster 4; charge_hold_off; log "thermal-ctl exit, caps restored"; exit 0' TERM INT

set_governor
tier=-1
log "thermal-ctl start (WARM=$WARM HOT=$HOT CRIT=$CRIT hyst=$HYST interval=${INTERVAL}s gov=${GOVERNOR:-unchanged})"

while true; do
  soc=$(soc_temp)
  bat=$(batt_temp)
  case "$soc" in ''|*[!0-9]*) soc=0;; esac
  case "$bat" in ''|*[!0-9]*) bat=0;; esac

  # tier selection with hysteresis on the way down
  new=$tier
  if [ "$soc" -ge "$CRIT" ]; then new=3
  elif [ "$soc" -ge "$HOT" ]; then new=2
  elif [ "$soc" -ge "$WARM" ]; then new=1
  elif [ "$tier" -eq 3 ] && [ "$soc" -lt $((CRIT - HYST)) ]; then new=2
  elif [ "$tier" -eq 2 ] && [ "$soc" -lt $((HOT - HYST)) ]; then new=1
  elif [ "$tier" -eq 1 ] && [ "$soc" -lt $((WARM - HYST)) ]; then new=0
  elif [ "$tier" -lt 0 ]; then new=0
  fi

  if [ "$new" != "$tier" ]; then
    case "$new" in
      0) restore_cluster 0; restore_cluster 4
         log "tier NORMAL  soc=${soc} batt=${bat}: full speed" ;;
      1) cap_cluster 4 "$WARM_BIG"
         log "tier WARM    soc=${soc} batt=${bat}: big -> $WARM_BIG" ;;
      2) cap_cluster 4 "$HOT_BIG"; cap_cluster 0 "$HOT_LITTLE"
         log "tier HOT     soc=${soc} batt=${bat}: big -> $HOT_BIG little -> $HOT_LITTLE" ;;
      3) cap_cluster 4 "$CRIT_BIG"; cap_cluster 0 "$CRIT_LITTLE"
         log "tier CRIT    soc=${soc} batt=${bat}: big -> $CRIT_BIG little -> $CRIT_LITTLE" ;;
    esac
    tier=$new
  fi

  # charging hold: CRIT SoC temp or hot battery
  if [ "$tier" -eq 3 ] || { [ "$bat" -gt 0 ] && [ "$bat" -ge "$BATT_STOP" ]; }; then
    charge_hold_on
  elif [ -e "$HOLD" ] && [ "$tier" -lt 3 ] && \
       { [ "$bat" -eq 0 ] || [ "$bat" -le "$BATT_START" ]; }; then
    charge_hold_off
  fi

  sleep "$INTERVAL"
done
