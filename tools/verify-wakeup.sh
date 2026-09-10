#!/bin/sh
# verify-wakeup.sh — run from the Mac after the phone comes back on usb0.
# Checks every subsystem the user cares about and pulls an xwd screenshot
# (NEVER dd /dev/fb0 — see docs/RESEARCH.md "fb0 readback deadlock").
SSH="ssh -i work/nx563j_key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@10.42.0.1"

echo "=== identity ==="
$SSH 'uname -a; uptime; cat /proc/cmdline | grep -o "want_initramfs"'

echo "=== desktop (LXDE) ==="
$SSH 'ps aux 2>/dev/null | grep -E "Xorg|lxsession|lxpanel|openbox|pcmanfm|onboard|fbdash" | grep -v grep'
echo "--- X.log tail ---"
$SSH 'tail -5 /var/log/X.log 2>/dev/null; echo; tail -3 /var/log/fbdash.log 2>/dev/null'

echo "=== xwd screenshot (from X server memory, not fb0) ==="
# Auth cookie lives in /root/.Xauthority (startx merges it there); the
# Xorg -auth /tmp/serverauth.* file is NOT usable directly by clients.
$SSH 'DISP=$(ps aux | grep -o "[X]org -nolisten tcp :[0-9]*" | grep -o ":[0-9]*" | head -1); XAUTHORITY=/root/.Xauthority DISPLAY=$DISP xwd -root -silent -out /tmp/desk.xwd 2>/dev/null; ls -l /tmp/desk.xwd 2>/dev/null'
scp -i work/nx563j_key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@10.42.0.1:/tmp/desk.xwd work/wakeup-desktop.xwd 2>/dev/null && echo "saved work/wakeup-desktop.xwd (convert with tools/xwd2png)"

echo "=== charge-ctl ==="
$SSH 'ps aux | grep charge-ctl | grep -v grep; tail -3 /var/log/charge-ctl.log 2>/dev/null; cat /sys/class/power_supply/battery/capacity /sys/class/power_supply/battery/status 2>/dev/null'

echo "=== wifi back on STA? ==="
$SSH 'iw dev 2>/dev/null | grep -E "Interface|type"; ip -br addr show wlan0 2>/dev/null'

echo "=== bt ==="
$SSH 'hciconfig hci0 2>/dev/null | head -3'
