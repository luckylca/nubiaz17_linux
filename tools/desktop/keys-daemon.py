#!/usr/bin/env python3
# keys-daemon.py — physical key handling for the NX563J Ubuntu desktop.
#
#   power key (qpnp_pon, KEY_POWER)      short press = screen off/on
#   volume up   (gpio-keys, KEY_VOLUMEUP)   speaker volume +5%
#   volume down (qpnp_pon, KEY_VOLUMEDOWN)  speaker volume -5%
#
# Volume goes through PulseAudio (system instance, socket
# /var/run/pulse/native): soft attenuation 0-100%, persists across streams.
# (Before 2026-09-14 they adjusted brightness because the ADSP was dead;
# then one day of raw 'Playback 0 Volume' which is boost-only 0..+82 dB and
# resets to 0 on every stream close — see task #29.)
# Brightness lives on the panel slider / brightness-slider.py.
#
# Screen-off is real power saving: backlight to 0 (lcd-backlight + wled)
# plus FB_BLANK_POWERDOWN. Wake reverses it in the order proven by
# desktop.sh: unblank, re-arm mdss autorefresh, ONE fb-kick pan (never
# loop the pan — a ticker deadlocks the mdss dsi_event thread), restore
# brightness. While the screen is off the touch forwarder is SIGSTOPped
# so phantom taps cannot reach X.
#
# Started from /root/.xinitrc (desktop session scope). Log:
# /var/log/keys-daemon.log
import os
import select
import signal
import struct
import subprocess
import sys
import time

EV_KEY = 0x01
KEY_POWER = 116
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
EVENT = struct.Struct("qqHHi")  # arm64 evdev: sec, usec, type, code, value

LCD = "/sys/class/leds/lcd-backlight/brightness"
WLED = "/sys/class/leds/wled/brightness"
FB_BLANK = "/sys/class/graphics/fb0/blank"
FB_AUTOREFRESH = "/sys/class/graphics/fb0/msm_cmd_autorefresh_en"
LOG = open("/var/log/keys-daemon.log", "a", buffering=1)

# keycode -> device name fragment (resolved at start)
WANT = {
    "qpnp_pon": {KEY_POWER, KEY_VOLUMEDOWN},
    "gpio-keys": {KEY_VOLUMEUP},
}


def log(msg):
    LOG.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))


def find_event(name):
    for ev in sorted(os.listdir("/sys/class/input")):
        if not ev.startswith("event"):
            continue
        try:
            with open("/sys/class/input/%s/device/name" % ev) as f:
                if f.read().strip() == name:
                    return "/dev/input/" + ev
        except OSError:
            continue
    return None


def write(path, value):
    try:
        with open(path, "w") as f:
            f.write("%s\n" % value)
    except OSError as e:
        log("write %s=%s failed: %s" % (path, value, e))


def read(path, default):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return default


class Screen:
    def __init__(self):
        self.off = False
        self.saved_lcd = 128
        self.saved_wled = 2048

    def _grab(self, grab):
        # Phantom-tap shield while the screen is off. EVIOCGRAB does not
        # work here (observed EBUSY 2026-09-13): touch-forward permanently
        # grabs the real panel device, and something in X holds the uinput
        # clone. Freeze the forwarder instead — no events, no taps.
        try:
            pids = subprocess.check_output(["pgrep", "-f", "touch-forward"])
        except subprocess.CalledProcessError:
            return
        for pid in pids.split():
            try:
                os.kill(int(pid), signal.SIGSTOP if grab else signal.SIGCONT)
            except (ProcessLookupError, ValueError):
                pass
        log("touch-forward %s" % ("STOPPED" if grab else "RESUMED"))

    def _ungrab(self):
        self._grab(False)

    def toggle(self):
        if self.off:
            self.wake()
        else:
            self.sleep()

    def sleep(self):
        self.saved_lcd = read(LCD, 128)
        self.saved_wled = read(WLED, 2048)
        self._grab(True)
        write(LCD, 0)
        write(WLED, 0)
        write(FB_BLANK, 4)  # FB_BLANK_POWERDOWN
        self.off = True
        log("screen OFF (saved lcd=%d wled=%d)" % (self.saved_lcd, self.saved_wled))

    def wake(self):
        write(FB_BLANK, 0)
        write(FB_AUTOREFRESH, 1)
        # exactly ONE pan to re-enter commit context; never loop this
        subprocess.call(["python3", "/root/fb-kick.py"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        write(LCD, self.saved_lcd or 128)
        write(WLED, self.saved_wled or 2048)
        self._ungrab()
        self.off = False
        log("screen ON")


PULSE_ENV = dict(os.environ, PULSE_SERVER="unix:/var/run/pulse/native")
VOL_STEP_PCT = 5


def _pulse_volume():
    """Current PulseAudio speaker volume in percent, or None if pulse is down."""
    try:
        out = subprocess.check_output(
            ["pactl", "get-sink-volume", "speaker"],
            env=PULSE_ENV, stderr=subprocess.DEVNULL).decode()
        return int(out.split("/")[1].strip().rstrip("%"))
    except (subprocess.CalledProcessError, IndexError, ValueError):
        return None


def volume_step(delta_pct):
    """Adjust speaker volume through PulseAudio (persists across streams and
    can attenuate below 0 dB, unlike the raw 'Playback 0 Volume' kcontrol
    whose range is 0..8192 = 0..+82 dB boost only, and which resets to 0
    every time the stream closes). Falls back to the raw kcontrol if pulse
    is not running."""
    cur = _pulse_volume()
    if cur is not None:
        new = max(0, min(100, cur + delta_pct))
        subprocess.call(["pactl", "set-sink-volume", "speaker", "%d%%" % new],
                        env=PULSE_ENV,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log("volume %d%% -> %d%%" % (cur, new))
        return
    # fallback: raw FE softvol (boost-only, resets on stream close)
    try:
        out = subprocess.check_output(
            ["amixer", "-c0", "cget", "name=Playback 0 Volume"],
            stderr=subprocess.DEVNULL).decode()
        cur = int(out.split(": values=")[1].split(",")[0].split()[0])
    except (subprocess.CalledProcessError, IndexError, ValueError):
        cur = 0
    new = max(0, min(8192, cur + delta_pct * 80))
    subprocess.call(["amixer", "-c0", "-q", "cset",
                     "name=Playback 0 Volume", str(new)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("volume(raw) %d -> %d" % (cur, new))


def main():
    fds = {}
    for name, codes in WANT.items():
        path = find_event(name)
        if not path:
            log("device %s not found" % name)
            continue
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        fds[fd] = codes
        log("watching %s (%s) for %s" % (path, name, sorted(codes)))
    if not fds:
        log("no key devices found, exiting")
        return 1

    screen = Screen()
    log("keys-daemon ready")
    while True:
        r, _, _ = select.select(list(fds), [], [])
        for fd in r:
            try:
                data = os.read(fd, EVENT.size * 8)
            except OSError:
                continue
            for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _sec, _usec, etype, code, value = EVENT.unpack_from(data, off)
                if etype != EV_KEY or code not in fds[fd]:
                    continue
                if code == KEY_POWER and value == 1:
                    screen.toggle()
                elif code == KEY_VOLUMEUP and value in (1, 2):
                    volume_step(+VOL_STEP_PCT)
                elif code == KEY_VOLUMEDOWN and value in (1, 2):
                    volume_step(-VOL_STEP_PCT)


if __name__ == "__main__":
    sys.exit(main() or 0)
