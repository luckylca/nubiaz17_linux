#!/bin/sh
# audio-fw-watchdog.sh — reload tas2555 firmware whenever playback starts
# (task #22)
#
# Root cause: the tas2555 driver drops its firmware image when the amp powers
# down (stream end -> Enable: 0). On the next stream start, setup_clocks
# prints "Firmware not loaded" and the enable runs WITHOUT the startup/unmute
# program -> amp stays silent. Firmware block CRC checks also need live I2S
# clocks, so the load must happen WHILE a stream is running.
#
# NOTE: this q6asm driver reports the pcm state as "DRAINING" the whole time
# (never "RUNNING", verified 2026-09-14), so key on owner_pid instead: its
# presence means a stream is open on the playback device.

CARD=0
STATUS=/proc/asound/card$CARD/pcm0p/sub0/status
LOG=/var/log/audio-fw-watchdog.log
state=closed

echo "$(date) watchdog started" >>$LOG
while true; do
    grep -q owner_pid $STATUS 2>/dev/null && cur=open || cur=closed
    if [ "$cur" = open ] && [ "$state" != open ]; then
        amixer -c$CARD -q cset name='TAS_FWLoad' 1 2>/dev/null
        echo "$(date) playback opened -> TAS_FWLoad poked" >>$LOG
    fi
    state=$cur
    sleep 0.3
done
