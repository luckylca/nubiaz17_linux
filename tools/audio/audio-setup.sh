#!/bin/sh
# audio-setup.sh — NX563J speaker path bring-up (task #22)
#
# Hardware chain (verified 2026-09-14):
#   MultiMedia1 FE -> 'PRI_MI2S_RX Audio Mixer MultiMedia1' -> AFE PRI_MI2S_RX
#   -> TLMM gpio65-68 (muxed by prim MI2S DAI itself on startup)
#   -> tas2555 smart amp (i2c 6-004c) -> speaker
#
# The tas2555 needs (a) I2S clocks RUNNING and (b) firmware (re)loaded per
# playback session — audio-fw-watchdog.sh handles that. This script only
# sets the static mixer path. Run after the sound card registers.
#
# NOTE: QUAT_MI2S route does NOT work — the sound DT node lacks the
# "quat-mi2s-active" pinctrl states (msm_get_pinctrl fails, pins never muxed)
# and nubia's hw_gpio_ctrl has claimed gpio59/60 anyway. PRI_MI2S is the
# stock mixer_paths route and needs no DT fix.

CARD=0
for i in $(seq 1 30); do
    [ -e /proc/asound/card$CARD/pcm0p ] && break
    sleep 1
done
[ -e /proc/asound/card$CARD/pcm0p ] || { echo "audio-setup: no sound card" >&2; exit 1; }

A="amixer -c$CARD -q"

# PulseAudio runs as the pulse user in system mode; the q6asm nodes are
# root:root 0600, so without this the sink fails with a misleading
# "No such file or directory" (2026-09-14).
chmod 0666 /dev/snd/* 2>/dev/null

# cset with read-back verification: right after card registration the
# routing service can silently eat a cset (cold boot 2026-09-14: route
# stayed off, first playback went nowhere, zero AFE/tas2555 activity).
set_route() { # set_route <name> <value> <want-substring>
    for i in $(seq 1 10); do
        $A cset name="$1" "$2" >/dev/null 2>&1
        amixer -c$CARD cget name="$1" 2>/dev/null | grep -q "$3" && return 0
        sleep 1
    done
    echo "audio-setup: FAILED to set $1" >&2
    return 1
}

# route MultiMedia1 -> PRI_MI2S_RX (both slots)
set_route 'PRI_MI2S_RX Audio Mixer MultiMedia1' 1,1 'values=on'
# make sure the dead QUAT route is off
$A cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 0,0 2>/dev/null
# unity gain on the FE soft volume (0 = 0 dB; range 0..8192)
$A cset name='Playback 0 Volume' 0 2>/dev/null

echo "audio-setup: speaker path applied (MultiMedia1 -> PRI_MI2S_RX -> tas2555)"

# PulseAudio system instance (task #29) — must start only AFTER the card
# exists, else module-alsa-sink device=hw:0,0 fails at load and pulse comes
# up with zero sinks (seen on cold boot 2026-09-14).
# Config: /etc/pulse/system.pa (sink speaker = hw:0,0, tsched=0, 48 kHz).
if [ -x /usr/bin/pulseaudio ] && ! pidof pulseaudio >/dev/null 2>&1; then
	mkdir -p /var/run/pulse
	setsid /usr/bin/pulseaudio --system -D --exit-idle-time=-1 \
		>>/var/log/pulseaudio.log 2>&1 &
	echo "audio-setup: pulseaudio started"
fi
