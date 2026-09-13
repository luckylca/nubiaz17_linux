#!/usr/bin/env python3
# keys-daemon.py — physical key handling for the NX563J Ubuntu desktop.
#
#   power key (qpnp_pon, KEY_POWER)      short press = screen off/on
#   volume up   (gpio-keys, KEY_VOLUMEUP)   brightness +8%
#   volume down (qpnp_pon, KEY_VOLUMEDOWN)  brightness -8%
#
# Volume keys adjust BRIGHTNESS for now: the ADSP is still dead (task #22),
# so there is no sound card and no audio volume to change. Remap to real
# volume once #22 lands.
#
# Screen-off is real power saving: backlight to 0 (lcd-backlight + wled)
# plus FB_BLANK_POWERDOWN. Wake reverses it in the order proven by
# desktop.sh: unblank, re-arm mdss autorefresh, ONE fb-kick pan (never
# loop the pan — a ticker deadlocks the mdss dsi_event thread), restore
# brightness. While the screen is off both touch devices are EVIOCGRABed
# so phantom taps cannot reach X.
#
# Started from /root/.xinitrc (desktop session scope). Log:
# /var/log/keys-daemon.log
import array
import fcntl
import os
import select
import struct
import subprocess
import sys
import time

EV_KEY = 0x01
KEY_POWER = 116
KEY_VOLUMEDOWN = 114
KEY_VOLUMEUP = 115
EVIOCGRAB = 0x40044590
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
TOUCH_NAMES = ("nubia_synaptics_dsx", "nx563j-touch")


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
        self.touch_fds = []

    def _grab(self, grab):
        for name in TOUCH_NAMES:
            path = find_event(name)
            if not path:
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                fcntl.ioctl(fd, EVIOCGRAB, 1 if grab else 0)
                self.touch_fds.append(fd)  # keep open: grab dies with the fd
            except OSError as e:
                log("grab %s=%s failed: %s" % (name, grab, e))

    def _ungrab(self):
        for fd in self.touch_fds:
            try:
                fcntl.ioctl(fd, EVIOCGRAB, 0)
                os.close(fd)
            except OSError:
                pass
        self.touch_fds = []

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


def brightness_step(delta):
    max_lcd = read("/sys/class/leds/lcd-backlight/max_brightness", 255)
    pct = round(read(LCD, 128) * 100 / max(1, max_lcd))
    subprocess.call(["/root/brightness-slider.py", "--set", str(pct + delta)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log("brightness %d%% -> %d%%" % (pct, pct + delta))


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
                    brightness_step(+8)
                elif code == KEY_VOLUMEDOWN and value in (1, 2):
                    brightness_step(-8)


if __name__ == "__main__":
    sys.exit(main() or 0)
