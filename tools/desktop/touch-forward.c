// touch-forward.c — NX563J touch translator: rmi4 MT device -> uinput
// single-touch device that Xorg's evdev driver classifies as a TOUCHSCREEN.
//
// Why this exists:
// The synaptics_dsx driver advertises BTN_TOOL_FINGER, so xf86-input-evdev
// classifies the panel as an "absolute touchpad". In evdev.c
// EvdevProcessKeyEvent(), BTN_TOUCH is only translated to BTN_LEFT (a click)
// when the device is EVDEV_TOUCHSCREEN|EVDEV_TABLET *and* has no MT slots —
// our device fails both tests, so taps move the pointer but NEVER click.
// There is no xorg.conf option to override the classification, and without
// systemd there is no libinput/udev path either.
//
// This daemon grabs the real event node, and re-emits a minimal type-A
// single-touch stream (ABS_X/ABS_Y + BTN_TOUCH, INPUT_PROP_DIRECT, no
// BTN_TOOL_FINGER, no ABS_MT_*) on a uinput clone. evdev sees a plain
// touchscreen: tap position = pointer position, tap = button 1.
//
// Run only while the X desktop owns the screen (started/stopped by
// desktop.sh): the grab would otherwise starve fbdash of its button taps.
//
// Creates symlink /dev/input/nx563j-touch -> the virtual event node.
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define SRC_NODE "/dev/input/event4"   /* nubia_synaptics_dsx */
#define LINK_PATH "/dev/input/nx563j-touch"

static int ufd = -1;
static volatile sig_atomic_t stop;

static void on_term(int sig) { (void)sig; stop = 1; }

static void emit(int type, int code, int value)
{
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type;
    ev.code = code;
    ev.value = value;
    if (write(ufd, &ev, sizeof(ev)) < 0)
        perror("write uinput");
}

/* locate the event node uinput just created (match by device name) */
static int find_and_link(void)
{
    char path[64], name[256];
    for (int i = 0; i < 32; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY);
        if (f < 0)
            continue;
        name[0] = 0;
        ioctl(f, EVIOCGNAME(sizeof(name)), name);
        close(f);
        if (strcmp(name, "nx563j-touch") == 0) {
            unlink(LINK_PATH);
            if (symlink(path, LINK_PATH) < 0) {
                perror("symlink");
                return -1;
            }
            fprintf(stderr, "touch-forward: %s -> %s\n", LINK_PATH, path);
            return 0;
        }
    }
    fprintf(stderr, "touch-forward: virtual node not found\n");
    return -1;
}

int main(void)
{
    signal(SIGTERM, on_term);
    signal(SIGINT, on_term);

    int fd = open(SRC_NODE, O_RDONLY);
    if (fd < 0) {
        perror("open " SRC_NODE);
        return 1;
    }

    /* panel geometry from the real device */
    struct input_absinfo ai;
    int xmax = 1079, ymax = 1919;
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ai) == 0)
        xmax = ai.maximum;
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ai) == 0)
        ymax = ai.maximum;

    ufd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (ufd < 0) {
        perror("open /dev/uinput");
        return 1;
    }
    ioctl(ufd, UI_SET_EVBIT, EV_SYN);
    ioctl(ufd, UI_SET_EVBIT, EV_KEY);
    ioctl(ufd, UI_SET_EVBIT, EV_ABS);
    ioctl(ufd, UI_SET_KEYBIT, BTN_TOUCH);
    ioctl(ufd, UI_SET_ABSBIT, ABS_X);
    ioctl(ufd, UI_SET_ABSBIT, ABS_Y);
    ioctl(ufd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);

    struct uinput_user_dev uud;
    memset(&uud, 0, sizeof(uud));
    snprintf(uud.name, UINPUT_MAX_NAME_SIZE, "nx563j-touch");
    uud.absmin[ABS_X] = 0;
    uud.absmax[ABS_X] = xmax;
    uud.absmin[ABS_Y] = 0;
    uud.absmax[ABS_Y] = ymax;
    if (write(ufd, &uud, sizeof(uud)) != sizeof(uud)) {
        perror("uinput_user_dev");
        return 1;
    }
    if (ioctl(ufd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        return 1;
    }
    sleep(1); /* let the event node appear */
    if (find_and_link() < 0)
        return 1;

    if (ioctl(fd, EVIOCGRAB, 1) < 0) {
        perror("EVIOCGRAB (is Xorg still holding " SRC_NODE "?)");
        return 1;
    }
    fprintf(stderr, "touch-forward: grabbed %s, panel %dx%d\n",
            SRC_NODE, xmax + 1, ymax + 1);

    int down = 0, x = 0, y = 0, dirty = 0, btn = -1;
    while (!stop) {
        struct input_event ev;
        ssize_t n = read(fd, &ev, sizeof(ev));
        if (n < 0) {
            if (errno == EINTR)
                continue;
            perror("read");
            break;
        }
        if (n != sizeof(ev))
            continue;

        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_POSITION_X || ev.code == ABS_X) {
                x = ev.value;
                dirty = 1;
            } else if (ev.code == ABS_MT_POSITION_Y || ev.code == ABS_Y) {
                y = ev.value;
                dirty = 1;
            }
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            btn = ev.value;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            /* flush one translated frame */
            if (btn == 1) {
                emit(EV_ABS, ABS_X, x);
                emit(EV_ABS, ABS_Y, y);
                emit(EV_KEY, BTN_TOUCH, 1);
                emit(EV_SYN, SYN_REPORT, 0);
                down = 1;
            } else if (btn == 0) {
                emit(EV_KEY, BTN_TOUCH, 0);
                emit(EV_SYN, SYN_REPORT, 0);
                down = 0;
            } else if (down && dirty) {
                emit(EV_ABS, ABS_X, x);
                emit(EV_ABS, ABS_Y, y);
                emit(EV_SYN, SYN_REPORT, 0);
            }
            btn = -1;
            dirty = 0;
        }
    }

    ioctl(fd, EVIOCGRAB, 0);
    ioctl(ufd, UI_DEV_DESTROY);
    unlink(LINK_PATH);
    return 0;
}
