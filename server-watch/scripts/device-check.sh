#!/usr/bin/env sh
# Run on the NX563J Ubuntu rootfs after installation.
set -u

ok=0
fail=0
pass() { echo "[OK]   $*"; ok=$((ok+1)); }
warn() { echo "[WARN] $*"; }
bad() { echo "[FAIL] $*"; fail=$((fail+1)); }

[ "$(uname -m 2>/dev/null)" = "aarch64" ] && pass "architecture aarch64" || warn "architecture: $(uname -m 2>/dev/null)"
[ -x /usr/local/bin/server-watch-agent ] && pass "agent binary installed" || bad "agent binary missing"
[ -x /usr/local/bin/server-watch-dashboard ] && pass "dashboard launcher installed" || bad "dashboard launcher missing"
[ -f /etc/server-watch/config.yaml ] && pass "config installed" || bad "config missing"

if wget -q -O /tmp/server-watch-health.$$ http://127.0.0.1:8765/api/health 2>/dev/null; then
  pass "agent HTTP health endpoint"
  cat /tmp/server-watch-health.$$; echo
else
  bad "agent HTTP health endpoint unavailable"
fi
rm -f /tmp/server-watch-health.$$

if [ -S /var/run/docker.sock ]; then
  pass "docker socket present"
else
  warn "docker socket not present"
fi

B=""
for b in chromium chromium-browser google-chrome google-chrome-stable falkon firefox; do
  if command -v "$b" >/dev/null 2>&1; then B="$b"; break; fi
done
[ -n "$B" ] && pass "dashboard browser: $B" || bad "no supported kiosk browser installed"

if pidof Xorg >/dev/null 2>&1; then
  pass "Xorg running"
else
  warn "Xorg is not running right now"
fi

BAT=""
for f in /sys/class/power_supply/*/type; do
  [ -r "$f" ] || continue
  [ "$(cat "$f" 2>/dev/null)" = "Battery" ] && BAT="${f%/type}" && break
done
if [ -n "$BAT" ]; then
  pass "battery sysfs: $BAT"
  [ -r "$BAT/capacity" ] && echo "       capacity=$(cat "$BAT/capacity")%"
  [ -r "$BAT/temp" ] && echo "       raw_temp=$(cat "$BAT/temp")"
else
  warn "battery sysfs not found"
fi

TC=$(ls -d /sys/class/thermal/thermal_zone* 2>/dev/null | wc -l)
echo "       thermal_zones=$TC"
[ "$TC" -gt 0 ] && pass "thermal zones available" || warn "no thermal zones"

echo "       network=$(awk '$2==\"00000000\"{print $1; exit}' /proc/net/route 2>/dev/null)"
echo "       agent_rss_kb=$(awk '/VmRSS/{print $2}' /proc/$(pidof server-watch-agent 2>/dev/null | awk '{print $1}')/status 2>/dev/null)"
echo "Summary: $ok ok, $fail failed"
[ "$fail" -eq 0 ]
