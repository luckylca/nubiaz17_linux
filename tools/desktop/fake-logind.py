#!/usr/bin/env python3
# fake-logind.py — minimal org.freedesktop.login1 on the system bus for
# NX563J Ubuntu (no systemd). Answers just enough of the Manager API for
# LXQt's leave dialog / lxqt-leave to power off and reboot:
#   CanPowerOff/CanReboot -> "yes"; PowerOff/Reboot -> /usr/sbin/powerctl
#   everything else capability-wise -> "na"
#
# Runs as root from rc.boot.ubuntu. Needs the companion policy file
# org.freedesktop.login1.conf in /etc/dbus-1/system.d/.
#
# 2026-09-12 charger quirk: this PMIC (PM8998 PON) has no offmode-charging
# mode (the abl EFI partition carries no charger/offmode strings at all),
# so a real POWER_OFF with USB attached is immediately turned back into a
# boot by the PMIC charger trigger -> "menu shutdown just reboots". Fix:
# when a charger is online we HALT instead (no PON command is issued, so
# nothing re-boots us). The screen is blanked first; the device looks and
# behaves powered off, and a 10 s power-button hold resets it as usual.
import os
import sys
import threading
import time

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

POWERCTL = "/usr/sbin/powerctl"
FB_BLANK = "/sys/class/graphics/fb0/blank"
# any of these being "1" means a charger is attached
PSU_ONLINE = ("/sys/class/power_supply/usb/online",
              "/sys/class/power_supply/ac/online",
              "/sys/class/power_supply/mains/online")


def charger_online():
    for path in PSU_ONLINE:
        try:
            with open(path) as f:
                if f.read().strip() == "1":
                    return True
        except OSError:
            continue
    return False


class Login1Manager(dbus.service.Object):
    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanPowerOff(self):
        return "yes"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanReboot(self):
        return "yes"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanSuspend(self):
        return "na"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanHibernate(self):
        return "na"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanHybridSleep(self):
        return "na"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="", out_signature="s")
    def CanSuspendThenHibernate(self):
        return "na"

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="b", out_signature="")
    def PowerOff(self, interactive):
        if charger_online():
            # HALT freezes the kernel without any PON power-off command,
            # so the PMIC charger trigger cannot turn it into a reboot.
            self._later("halt", blank=True)
        else:
            self._later("poweroff")

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="b", out_signature="")
    def Reboot(self, interactive):
        self._later("reboot")

    @staticmethod
    def _later(mode, blank=False):
        # reply first, die second: run powerctl after the dbus reply flush
        def run():
            time.sleep(0.3)
            if blank:
                try:
                    with open(FB_BLANK, "w") as f:
                        f.write("4\n")  # FB_BLANK_POWERDOWN
                except OSError:
                    pass
            os.system("sync; %s %s" % (POWERCTL, mode))
        threading.Thread(target=run, daemon=True).start()


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    name = dbus.service.BusName("org.freedesktop.login1", bus,
                                allow_replacement=False, replace_existing=False,
                                do_not_queue=True)
    Login1Manager(bus, "/org/freedesktop/login1")
    print("fake-logind: org.freedesktop.login1 ready", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
