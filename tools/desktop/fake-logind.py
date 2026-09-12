#!/usr/bin/env python3
# fake-logind.py — minimal org.freedesktop.login1 on the system bus for
# NX563J Ubuntu (no systemd). Answers just enough of the Manager API for
# LXQt's leave dialog / lxqt-leave to power off and reboot:
#   CanPowerOff/CanReboot -> "yes"; PowerOff/Reboot -> /usr/sbin/powerctl
#   everything else capability-wise -> "na"
#
# Runs as root from rc.boot.ubuntu. Needs the companion policy file
# org.freedesktop.login1.conf in /etc/dbus-1/system.d/.
import os
import sys
import threading
import time

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

POWERCTL = "/usr/sbin/powerctl"


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
        self._later("poweroff")

    @dbus.service.method("org.freedesktop.login1.Manager",
                         in_signature="b", out_signature="")
    def Reboot(self, interactive):
        self._later("reboot")

    @staticmethod
    def _later(mode):
        # reply first, die second: run powerctl after the dbus reply flush
        def run():
            time.sleep(0.3)
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
