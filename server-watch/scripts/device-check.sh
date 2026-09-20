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
if [ -x /usr/local/bin/server-watch-webview ]; then B="server-watch-webview (WebKitGTK full dashboard)"; fi
if [ -z "$B" ]; then
  for b in chromium chromium-browser google-chrome google-chrome-stable falkon firefox; do
    if command -v "$b" >/dev/null 2>&1; then B="$b"; break; fi
  done
fi
[ -n "$B" ] && pass "dashboard frontend: $B" || bad "no supported kiosk frontend installed"
if pidof lxqt-panel >/dev/null 2>&1; then
  pass "LXQt panel running"
else
  warn "LXQt panel is not running"
fi
if grep -q 'server-watch.desktop' /root/.config/lxqt/panel.conf 2>/dev/null; then
  pass "LXQt one-tap quick-launch configured"
else
  warn "Server Watch is not yet in LXQt quick-launch"
fi

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

NETIF=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
echo "       network=$NETIF"
echo "       agent_rss_kb=$(awk '/VmRSS/{print $2}' /proc/$(pidof server-watch-agent 2>/dev/null | awk '{print $1}')/status 2>/dev/null)"
echo "       load_average=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
UI_ROWS=$(ps -eo pid,pcpu,rss,comm,args 2>/dev/null | awk '$0 ~ /server-watch-(native|webview|dashboard)|WebKit(Web|Network)|chromium|firefox|falkon/ && $0 !~ /awk/ {print}')
if [ -n "$UI_ROWS" ]; then
  echo "       frontend_processes(pid cpu% rss_kb comm args):"
  echo "$UI_ROWS" | sed 's/^/         /'
  UI_RSS=$(echo "$UI_ROWS" | awk '{sum += $3} END {print sum+0}')
  echo "       frontend_total_rss_kb=$UI_RSS"
else
  echo "       frontend_processes=not-running"
fi
echo "Summary: $ok ok, $fail failed"
[ "$fail" -eq 0 ]
