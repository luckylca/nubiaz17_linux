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

# route MultiMedia1 -> PRI_MI2S_RX (both slots)
$A cset name='PRI_MI2S_RX Audio Mixer MultiMedia1' 1,1
# make sure the dead QUAT route is off
$A cset name='QUAT_MI2S_RX Audio Mixer MultiMedia1' 0,0 2>/dev/null
# unity gain on the FE soft volume (0 = 0 dB; range 0..8192)
$A cset name='Playback 0 Volume' 0

echo "audio-setup: speaker path applied (MultiMedia1 -> PRI_MI2S_RX -> tas2555)"
