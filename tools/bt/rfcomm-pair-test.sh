#!/bin/bash
# rfcomm-pair-test.sh — one-shot RFCOMM pairing test vs Mac incoming port.
# Run ONCE on a fresh boot (stale half-dead ACL handles poison retries).
# Requires: user watching the Mac screen to click the pairing dialog.
set -x
MAC=3C:A6:F6:06:2E:09
CH=3

# 1. free BT coexistence (stuck wpa scan starves page/inquiry scan)
pkill -f "wpa_supplican[t]"
# 2. blueman holds the BlueZ agent — remove the conflict
pkill -f "blueman-apple[t]"
pkill -f "blueman-tra[y]"
sleep 1

# 3. sanity: supervisor-managed stack untouched
hciconfig hci0 | head -3
pidof bluetoothd || { echo "bluetoothd missing, abort"; exit 1; }

# 4. standing agent: DisplayYesNo + queued yes for RequestConfirmation
nohup bash -c '(printf "agent DisplayYesNo\ndefault-agent\npairable on\ndiscoverable on\nyes\nyes\nyes\nyes\n"; sleep 240) | bluetoothctl >>/var/log/agent-rfcomm.log 2>&1' >/dev/null 2>&1 </dev/null &
sleep 5
grep -c "Agent registered" /var/log/agent-rfcomm.log

# 5. line-buffered btmon evidence capture
nohup timeout 120 stdbuf -oL btmon > /var/log/rfcomm-btmon.log 2>&1 </dev/null &
sleep 1

# 6. device-initiated ACL + RFCOMM (Mac inbound page is broken; outbound works)
timeout 12 hcitool cc $MAC && echo "ACL up"
rfcomm connect /dev/rfcomm0 $MAC $CH > /var/log/rfcomm-connect.log 2>&1 &
RFPID=$!
sleep 15
ls -l /dev/rfcomm0 && echo "RFCOMM TTY UP" || echo "RFCOMM FAILED"
