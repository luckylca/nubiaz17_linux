// setroot.c — paint the NX563J X root window with an Ubuntu-style
// aubergine gradient, no gdk-pixbuf/cairo/PNG involved.
//
// Why: pcmanfm's desktop window renders garbage (vertical stripes) on
// this fbdev X server no matter the wallpaper mode — even solid-color
// mode. So we don't run a desktop client at all; the root window itself
// carries the wallpaper. The pixmap is retained after exit
// (RetainPermanent + _XROOTPMAP_ID) so the paint survives this process.
//
// Build: gcc -O2 -o setroot setroot.c -lX11
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>

#define W 1920
#define H 1080

/* C1 dark aubergine -> C2 aubergine -> C3 ubuntu orange (same gradient
 * as gen-wallpaper.py, computed directly in X pixel space) */
static const unsigned char C1[3] = {44, 0, 30};
static const unsigned char C2[3] = {119, 33, 111};
static const unsigned char C3[3] = {233, 84, 32};

int main(int argc, char **argv)
{
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "setroot: cannot open display\n");
        return 1;
    }
    int scr = DefaultScreen(dpy);
    Window root = RootWindow(dpy, scr);
    int sw = DisplayWidth(dpy, scr), sh = DisplayHeight(dpy, scr);
    (void)argc; (void)argv;

    Pixmap pm = XCreatePixmap(dpy, root, sw, sh, DefaultDepth(dpy, scr));
    GC gc = XCreateGC(dpy, pm, 0, NULL);

    for (int y = 0; y < sh; y++) {
        for (int x0 = 0; x0 < sw; x0 += 240) { /* 240px bands: gradient is smooth enough */
            double t = (double)x0 / sw * 0.55 + (double)y / sh * 0.45;
            const unsigned char *a, *b;
            double f;
            if (t < 0.65) { f = t / 0.65;       a = C1; b = C2; }
            else          { f = (t - 0.65) / 0.35; a = C2; b = C3; }
            unsigned long px =
                ((unsigned long)(a[0] + (b[0] - a[0]) * f) << 16) |
                ((unsigned long)(a[1] + (b[1] - a[1]) * f) << 8)  |
                ((unsigned long)(a[2] + (b[2] - a[2]) * f));
            XSetForeground(dpy, gc, px);
            XFillRectangle(dpy, pm, gc, x0, y, 240, 1);
        }
    }

    XSetWindowBackgroundPixmap(dpy, root, pm);
    XClearWindow(dpy, root);

    /* keep the pixmap alive after we exit and publish it like Esetroot */
    Atom prop = XInternAtom(dpy, "_XROOTPMAP_ID", False);
    Atom prop2 = XInternAtom(dpy, "ESETROOT_PMAP_ID", False);
    XChangeProperty(dpy, root, prop, XA_PIXMAP, 32, PropModeReplace,
                    (unsigned char *)&pm, 1);
    XChangeProperty(dpy, root, prop2, XA_PIXMAP, 32, PropModeReplace,
                    (unsigned char *)&pm, 1);
    XSetCloseDownMode(dpy, RetainPermanent);
    XFlush(dpy);
    XCloseDisplay(dpy);
    printf("setroot: painted %dx%d\n", sw, sh);
    return 0;
}
