#!/bin/sh
# desktop-start.sh — enter the X desktop from the dashboard, by hand.
# Same thing tapping the DESKTOP button on the dashboard does.
PATH=/bin:/sbin:/usr/bin:/usr/sbin
if pidof Xorg >/dev/null 2>&1; then
  echo "X already running"; exit 0
fi
rm -f /tmp/desk-ready
setsid /root/desktop.sh >/dev/null 2>&1 </dev/null &
