#!/usr/bin/env python3
# brightness-slider.py — NX563J panel backlight control (Ubuntu target).
#
# The JDI panel backlight is driven through TWO led-class nodes that must
# move together (boot writes both in rc.boot.ubuntu):
#   /sys/class/leds/lcd-backlight/brightness   max 255
#   /sys/class/leds/wled/brightness            max 4095
#
# Modes:
#   (no args)   show a small GTK slider window (launched from the panel)
#   --set PCT   set brightness to PCT (5..100) and persist it
#   --restore   re-apply the persisted value (called from .xinitrc, since
#               the boot default lives in the initramfs and only the X
#               session start is rootfs-writable without a reflash)
import os
import sys

LCD = "/sys/class/leds/lcd-backlight"
WLED = "/sys/class/leds/wled"
STATE = "/root/.brightness"
MIN_PCT = 5  # below ~5% the wled flickers/turns off; keep the panel usable


def _read(path, default):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return default


def get_pct():
    return max(MIN_PCT, min(100, round(_read(LCD + "/brightness", 128) * 100
                                       / max(1, _read(LCD + "/max_brightness", 255)))))


def set_pct(pct):
    pct = max(MIN_PCT, min(100, int(pct)))
    lcd = round(_read(LCD + "/max_brightness", 255) * pct / 100)
    wled = round(_read(WLED + "/max_brightness", 4095) * pct / 100)
    for node, val in ((LCD + "/brightness", lcd), (WLED + "/brightness", wled)):
        try:
            with open(node, "w") as f:
                f.write("%d\n" % val)
        except OSError:
            pass
    try:
        with open(STATE, "w") as f:
            f.write("%d\n" % pct)
    except OSError:
        pass
    return pct


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--set":
        set_pct(int(sys.argv[2]))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "--restore":
        if os.path.exists(STATE):
            try:
                with open(STATE) as f:
                    set_pct(int(f.read().strip()))
            except (OSError, ValueError):
                pass
        return

    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, GLib

    win = Gtk.Window(title="Brightness")
    win.set_default_size(420, 90)
    win.set_keep_above(True)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.connect("destroy", Gtk.main_quit)

    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    box.set_border_width(16)
    label = Gtk.Label()
    adj = Gtk.Adjustment(value=get_pct(), lower=MIN_PCT, upper=100,
                         step_increment=5, page_increment=20)
    scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
    scale.set_hexpand(True)
    scale.set_digits(0)

    def update_text():
        label.set_text("%d %%" % adj.get_value())

    def on_change(widget):
        set_pct(adj.get_value())
        update_text()

    # write at most every 80 ms while dragging (wled i2c writes are cheap
    # but dragging generates hundreds of events)
    pending = [None]

    def throttled(widget):
        if pending[0] is None:
            pending[0] = GLib.timeout_add(80, apply)

    def apply():
        on_change(None)
        pending[0] = None
        return False

    scale.connect("value-changed", throttled)
    update_text()
    box.pack_start(scale, True, True, 0)
    box.pack_start(label, False, False, 0)
    win.add(box)
    win.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
