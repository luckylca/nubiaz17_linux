#!/bin/sh
# /root/desktop.sh — NX563J X desktop launcher (Ubuntu target).
#
# Started by fbdash when the DESKTOP touch button is tapped. Ordering
# matters (the JDI cmd-mode panel re-suspends within a second when no
# process holds /dev/fb0 open):
#
#   1. we open fb0 FIRST (fd 9) and signal readiness
#   2. fbdash sees the flag, exits, releases its fb0 fd - the panel
#      never sees a last-close
#   3. startx runs the X session (fbdev driver, evdev touch)
#   4. when the session ends, restart fbdash and release our fd
#
# Log: /var/log/X.log
PATH=/bin:/sbin:/usr/bin:/usr/sbin

exec 9</dev/fb0 || exit 1
touch /tmp/desk-ready

# wait for fbdash to let go (it polls the flag for up to 5 s)
i=0
while pidof fbdash >/dev/null 2>&1 && [ $i -lt 24 ]; do
  i=$((i + 1))
  sleep 0.5 2>/dev/null || sleep 1
done
rm -f /tmp/desk-ready

export DISPLAY=:0
startx >/var/log/X.log 2>&1

# session over: bring the dashboard back
exec 9<&-
# Restart the dashboard with auto-launch disabled: the desktop session just
# ended (or failed), so we must not immediately re-enter it — that would
# trap a failing desktop in a launch/fail/relaunch loop. The user can still
# tap DESKTOP to re-enter by hand.
FBDASH_NOAUTOLAUNCH=1 setsid /root/fbdash/fbdash >/var/log/fbdash.log 2>&1 &
