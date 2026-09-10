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
# Kernel-init env has HOME=/ — without this startx looks for //.xinitrc and
# the whole X session ends up with HOME=/ (lxpanel reads //.config etc).
export HOME=/root
export USER=root

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

# Touch translator: the rmi4 device advertises BTN_TOOL_FINGER, so X's evdev
# driver classifies it as a *touchpad* and drops BTN_TOUCH (taps never
# click). touch-forward grabs event4 and re-emits a plain single-touch
# stream on a uinput clone (/dev/input/nx563j-touch) that evdev treats as a
# touchscreen. Only run it while X owns the screen — the grab would starve
# fbdash of its own button taps.
/root/touch-forward >/var/log/touch-forward.log 2>&1 &
TF_PID=$!
i=0
while [ ! -e /dev/input/nx563j-touch ] && [ $i -lt 20 ]; do
  i=$((i + 1)); sleep 0.5 2>/dev/null || sleep 1
done

# NOTE: do NOT run a FBIOPAN_DISPLAY ticker here — panning at 10 Hz while
# Xorg runs deadlocks the mdss dsi_event thread (D-state, screen frozen,
# only a reboot clears it). The panel is fed by mdss autorefresh
# (msm_cmd_autorefresh_en, set in rc.boot.ubuntu) instead.
#
# But autorefresh only ACTIVATES on the next commit, and Xorg's fbdev
# driver never commits — so the panel keeps showing the last fbdash frame
# until exactly ONE pan lands. Worse, the fbdash→Xorg handoff can leave
# the panel blanked, and a pan while blanked just fails EPERM. So: wait
# for the X server, unblank, re-arm autorefresh, then kick ONCE. Bounded
# retries on EPERM only (failed pans never reach the commit path).
(
  i=0
  while ! pidof Xorg >/dev/null 2>&1 && [ $i -lt 60 ]; do
    i=$((i + 1)); sleep 0.5 2>/dev/null || sleep 1
  done
  sleep 3 2>/dev/null || sleep 3
  i=0
  while [ $i -lt 5 ]; do
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
    echo 1 > /sys/class/graphics/fb0/msm_cmd_autorefresh_en 2>/dev/null
    python3 /root/fb-kick.py >/dev/null 2>&1 && break
    i=$((i + 1)); sleep 2 2>/dev/null || sleep 2
  done
) &

startx >/var/log/X.log 2>&1

# session over: release the touch grab and bring the dashboard back
kill $TF_PID 2>/dev/null
exec 9<&-
# Restart the dashboard with auto-launch disabled: the desktop session just
# ended (or failed), so we must not immediately re-enter it — that would
# trap a failing desktop in a launch/fail/relaunch loop. The user can still
# tap DESKTOP to re-enter by hand.
FBDASH_NOAUTOLAUNCH=1 setsid /root/fbdash/fbdash >/var/log/fbdash.log 2>&1 &
