#!/usr/bin/env python3
# server-watch kiosk webview — minimal fullscreen WebKitGTK window.
# No browser chrome, no address bar; just the dashboard.
# Writes its PID to /tmp/server-watch-kiosk.pid so the agent's
# /api/ui/quit endpoint can close it on clock double-tap.
import os
import signal
import sys

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gtk, WebKit2, GLib

URL = os.environ.get("SERVER_WATCH_URL", "http://127.0.0.1:8765")
PIDFILE = "/tmp/server-watch-kiosk.pid"


def write_pid():
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass


def remove_pid():
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass


def main():
    write_pid()

    ctx = WebKit2.WebContext.get_default()
    # keep the profile tiny and private to the kiosk
    data_dir = "/tmp/server-watch-kiosk-profile"
    os.makedirs(data_dir, exist_ok=True)
    try:
        mgr = ctx.get_website_data_manager()
        mgr.set_property("base-data-directory", data_dir)
        mgr.set_property("base-cache-directory", data_dir)
    except Exception:
        pass

    settings = WebKit2.Settings(
        enable_javascript=True,
        enable_webaudio=False,
        enable_webgl=False,
        hardware_acceleration_policy=WebKit2.HardwareAccelerationPolicy.NEVER,
        enable_page_cache=False,
        enable_smooth_scrolling=False,
    )

    webview = WebKit2.WebView.new_with_context(ctx)
    webview.set_settings(settings)

    # The X session sets Xft.dpi=216, which makes WebKitGTK render with
    # devicePixelRatio=2.25: the CSS viewport shrinks to 853x480 and the
    # dashboard layout breaks. Normalize with full-page zoom so the CSS
    # viewport is always the physical panel size (1920x1080), matching what
    # the fallback browsers (devicePixelRatio=1) would give.
    def _normalize_zoom():
        def _on_dpr(_wv, res, _data=None):
            try:
                dpr = _wv.run_javascript_finish(res).get_js_value().to_double()
            except Exception:
                return
            if dpr and abs(dpr - 1.0) > 0.01:
                _wv.set_zoom_level(1.0 / dpr)
        try:
            webview.run_javascript("devicePixelRatio", None, _on_dpr)
        except Exception:
            pass
        return False

    def _on_load_changed(_wv, event):
        if event == WebKit2.LoadEvent.FINISHED:
            GLib.idle_add(_normalize_zoom)

    webview.connect("load-changed", _on_load_changed)

    win = Gtk.Window(title="Server Watch")
    win.set_default_size(1080, 1920)
    win.add(webview)
    win.fullscreen()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()

    # retry until the agent answers
    def load():
        webview.load_uri(URL)
        return False

    def on_load_failed(_wv, _event, _uri, _err):
        GLib.timeout_add_seconds(2, load)
        return True

    webview.connect("load-failed", on_load_failed)
    load()

    # clean exit on SIGTERM/SIGINT from the agent's quit endpoint
    def quit_handler(*_a):
        remove_pid()
        Gtk.main_quit()
    signal.signal(signal.SIGTERM, quit_handler)
    signal.signal(signal.SIGINT, quit_handler)

    Gtk.main()
    remove_pid()


if __name__ == "__main__":
    main()
