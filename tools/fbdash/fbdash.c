// fbdash.c — NX563J framebuffer status dashboard + touch HMI.
//
// Long-lived fb0 holder (keeps the cmd-mode panel alive) that renders a
// status page with the kernel 8x16 font scaled 2x: hostname, kernel,
// uptime, load, memory, rootfs usage, usb0/wlan0 addresses, BT state,
// SSH listener and wall clock. Bottom bar has touch buttons read from
// the synaptics event4 (evdev MT protocol B):
//
//   [DESKTOP]  hand fb0 over to /root/desktop.sh (X session); fbdash
//              exits and is restarted by desktop.sh when X ends
//   [DIM]/[BRIGHT]  backlight -/+ (clamped so it never goes black)
//
// Build on device:  gcc -O2 -static -o fbdash fbdash.c
// Run:              setsid ./fbdash &

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <net/if.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "font8x16.h"

#define SCALE 2
#define CW (8 * SCALE)
#define CH (16 * SCALE)
#define FG 0x00e8e8e8 /* near-white */
#define ACCENT 0x0000d7ff
#define HDR 0x00ffaa00
#define BG 0x00000000
#define BTN_BG 0x00202020
#define BTN_EDGE 0x00ffaa00

#define BL_PATH "/sys/class/leds/lcd-backlight/brightness"
#define TOUCH_DEV "/dev/input/event4"

static uint32_t *fb;
static uint32_t stride, xres, yres;
static int touch_fd = -1;
static int desktop_req;
static int autolaunch_left = -1; /* secs until auto-desktop; -1 = off */

static void px(uint32_t x, uint32_t y, uint32_t c)
{
	if (x < xres && y < yres)
		fb[y * stride + x] = c;
}

static void draw_char(int cx, int cy, char ch, uint32_t color)
{
	const unsigned char *glyph = font8x16[(unsigned char)ch];
	for (int row = 0; row < 16; row++) {
		unsigned char bits = glyph[row];
		for (int col = 0; col < 8; col++) {
			if (bits & (0x80 >> col)) {
				for (int dy = 0; dy < SCALE; dy++)
					for (int dx = 0; dx < SCALE; dx++)
						px(cx * CW + col * SCALE + dx,
						   cy * CH + row * SCALE + dy, color);
			}
		}
	}
}

static void draw_text(int cx, int cy, const char *s, uint32_t color)
{
	while (*s) {
		draw_char(cx++, cy, *s++, color);
		if (cx * CW >= (int)xres - CW)
			break;
	}
}

static void clear(void)
{
	for (uint32_t y = 0; y < yres; y++)
		for (uint32_t x = 0; x < xres; x++)
			fb[y * stride + x] = BG;
}

static void hr(int cy)
{
	uint32_t y = cy * CH + CH / 2;
	for (uint32_t x = CW; x < xres - CW; x++)
		for (int t = -1; t <= 1; t++)
			px(x, y + t, HDR);
}

/* --- buttons -------------------------------------------------------------*/

struct button {
	uint32_t x, y, w, h;
	const char *label;
	enum { ACT_NONE, ACT_DESKTOP, ACT_DIM, ACT_BRIGHT } act;
};

static struct button buttons[3];

static void buttons_layout(void)
{
	uint32_t bw = 340, bh = 100, gap = 10;
	uint32_t y0 = yres - bh - 40;
	buttons[0] = (struct button){ gap, y0, bw, bh, "DESKTOP", ACT_DESKTOP };
	buttons[1] = (struct button){ gap * 2 + bw, y0, bw, bh, "DIM", ACT_DIM };
	buttons[2] = (struct button){ gap * 3 + bw * 2, y0, bw, bh, "BRIGHT", ACT_BRIGHT };
}

static void draw_button(const struct button *b)
{
	for (uint32_t y = b->y; y < b->y + b->h; y++)
		for (uint32_t x = b->x; x < b->x + b->w; x++)
			px(x, y, BTN_BG);
	for (uint32_t x = b->x; x < b->x + b->w; x++)
		for (int t = 0; t < 3; t++) {
			px(x, b->y + t, BTN_EDGE);
			px(x, b->y + b->h - 1 - t, BTN_EDGE);
		}
	for (uint32_t y = b->y; y < b->y + b->h; y++)
		for (int t = 0; t < 3; t++) {
			px(b->x + t, y, BTN_EDGE);
			px(b->x + b->w - 1 - t, y, BTN_EDGE);
		}
	int len = strlen(b->label);
	int cx = (int)(b->x + (b->w - (uint32_t)len * CW) / 2) / CW;
	int cy = (int)(b->y + (b->h - CH) / 2) / CH;
	draw_text(cx, cy, b->label, HDR);
}

static void draw_buttons(void)
{
	for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++)
		draw_button(&buttons[i]);
}

/* --- backlight ------------------------------------------------------------*/

static int bl_get(void)
{
	char buf[16];
	int fd = open(BL_PATH, O_RDONLY);
	ssize_t r = fd >= 0 ? read(fd, buf, sizeof(buf) - 1) : -1;
	if (fd >= 0)
		close(fd);
	if (r <= 0)
		return -1;
	buf[r] = 0;
	return atoi(buf);
}

static void bl_set(int v)
{
	if (v < 16)
		v = 16; /* never go black: the user could not find BRIGHT again */
	if (v > 4095)
		v = 4095;
	char buf[16];
	int n = snprintf(buf, sizeof(buf), "%d", v);
	int fd = open(BL_PATH, O_WRONLY);
	if (fd >= 0) {
		write(fd, buf, n);
		close(fd);
	}
}

/* --- touch (evdev MT protocol B) ------------------------------------------*/

static void touch_open(void)
{
	touch_fd = open(TOUCH_DEV, O_RDONLY | O_NONBLOCK);
}

/* Poll pending touch events; sets desktop_req when DESKTOP is tapped. */
static void touch_poll(void)
{
	if (touch_fd < 0)
		return;
	static int tx = -1, ty = -1; /* last reported position */
	struct input_event ev[16];
	for (;;) {
		ssize_t r = read(touch_fd, ev, sizeof(ev));
		if (r <= 0)
			return;
		int n = r / (int)sizeof(ev[0]);
		for (int i = 0; i < n; i++) {
			if (ev[i].type == EV_ABS &&
			    ev[i].code == ABS_MT_POSITION_X)
				tx = ev[i].value;
			else if (ev[i].type == EV_ABS &&
				 ev[i].code == ABS_MT_POSITION_Y)
				ty = ev[i].value;
			else if (ev[i].type == EV_ABS &&
				 ev[i].code == ABS_MT_TRACKING_ID &&
				 ev[i].value == -1 && tx >= 0 && ty >= 0) {
				/* finger up: tap at (tx, ty) */
				for (size_t k = 0; k < sizeof(buttons) / sizeof(buttons[0]); k++) {
					struct button *b = &buttons[k];
					if ((uint32_t)tx >= b->x && (uint32_t)tx < b->x + b->w &&
					    (uint32_t)ty >= b->y && (uint32_t)ty < b->y + b->h) {
						int bl;
						autolaunch_left = -1; /* user took over; cancel auto-desktop */
						switch (b->act) {
						case ACT_DESKTOP:
							desktop_req = 1;
							break;
						case ACT_DIM:
							bl = bl_get();
							if (bl >= 0)
								bl_set(bl - 256);
							break;
						case ACT_BRIGHT:
							bl = bl_get();
							if (bl >= 0)
								bl_set(bl + 256);
							break;
						default:
							break;
						}
					}
				}
				tx = ty = -1;
			}
		}
		if (r < (ssize_t)sizeof(ev))
			return;
	}
}

/* Spawn /root/desktop.sh (which opens fb0 to keep the panel alive) and
 * wait for its ready flag; the caller then exits and releases fb0. */
static void start_desktop(void)
{
	pid_t p = fork();
	if (p == 0) {
		setsid();
		execl("/bin/sh", "sh", "/root/desktop.sh", (char *)NULL);
		_exit(0);
	}
	for (int i = 0; i < 50; i++) {
		if (access("/tmp/desk-ready", F_OK) == 0)
			return; /* desktop.sh holds fb0 now */
		if (waitpid(p, NULL, WNOHANG) == p)
			break; /* desktop.sh died before ready */
		usleep(100000);
	}
	/* 5 s and no ready flag: keep the dashboard rather than risk a
	 * suspended panel with no fb holder. */
	desktop_req = 0;
}

/* --- status providers ------------------------------------------------------*/

static void read_first_line(const char *path, char *out, size_t n)
{
	int fd = open(path, O_RDONLY);
	ssize_t r = fd >= 0 ? read(fd, out, n - 1) : -1;
	if (fd >= 0)
		close(fd);
	if (r <= 0) {
		snprintf(out, n, "?");
		return;
	}
	out[r] = 0;
	char *nl = strchr(out, '\n');
	if (nl)
		*nl = 0;
}

static void iface_addr(const char *ifname, char *out, size_t n)
{
	int s = socket(AF_INET, SOCK_DGRAM, 0);
	struct ifreq ifr;
	snprintf(ifr.ifr_name, IFNAMSIZ, "%s", ifname);
	if (s < 0 || ioctl(s, SIOCGIFADDR, &ifr) < 0) {
		snprintf(out, n, "%s: down", ifname);
		if (s >= 0)
			close(s);
		return;
	}
	struct sockaddr_in *sa = (struct sockaddr_in *)&ifr.ifr_addr;
	snprintf(out, n, "%s: %s", ifname, inet_ntoa(sa->sin_addr));
	close(s);
}

static void bt_status(char *out, size_t n)
{
	/* hciconfig output: "BD Address: XX:..  ACL MTU ..." and a line
	 * that is "UP RUNNING" when the adapter is up. */
	FILE *p = popen("hciconfig hci0 2>/dev/null", "r");
	char buf[256], addr[64] = "";
	int up = 0;
	if (!p) {
		snprintf(out, n, "bt     unknown");
		return;
	}
	while (fgets(buf, sizeof(buf), p)) {
		char *a;
		if (strstr(buf, "UP RUNNING"))
			up = 1;
		if ((a = strstr(buf, "BD Address:")))
			sscanf(a + 11, "%63s", addr);
	}
	pclose(p);
	if (!addr[0])
		snprintf(out, n, "bt     no hci0");
	else
		snprintf(out, n, "bt     %s %s", up ? "UP" : "down", addr);
}

static int port22_listening(void)
{
	/* Good enough: /proc/net/tcp shows 0.0.0.0:22 (0016) listeners as 0A. */
	FILE *f = fopen("/proc/net/tcp", "r");
	char line[256];
	int found = 0;
	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f)) {
		unsigned int laddr, lport;
		char state[4];
		if (sscanf(line, " %*d: %x:%x %*s %s", &laddr, &lport, state) == 3 &&
		    lport == 22 && strcmp(state, "0A") == 0) {
			found = 1;
			break;
		}
	}
	fclose(f);
	return found;
}

int main(void)
{
	int fd = open("/dev/fb0", O_RDWR);
	if (fd < 0) {
		perror("open /dev/fb0");
		return 1;
	}

	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0 ||
	    ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0) {
		perror("FBIOGET");
		return 1;
	}
	xres = var.xres;
	yres = var.yres;
	stride = fix.line_length / 4;

	ioctl(fd, FBIOBLANK, 0);

	fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	struct utsname uts;
	uname(&uts);

	buttons_layout();
	touch_open();

	/* Boot straight into the desktop after a short idle countdown; any
	 * button tap cancels it so the dashboard stays up on demand. Only the
	 * boot-time fbdash auto-launches: desktop.sh re-runs us with
	 * FBDASH_NOAUTOLAUNCH=1 when an X session ends, so a desktop that
	 * fails to start cannot trap us in a launch/fail/relaunch loop. */
	if (getenv("FBDASH_NOAUTOLAUNCH") == NULL)
		autolaunch_left = 8;

	struct pollfd pfd = { .fd = touch_fd, .events = POLLIN };
	int tick = 0;

	for (;;) {
		/* 1 s tick: poll wakes early on touch input; the status
		 * page itself refreshes every 5 s */
		if (touch_fd >= 0) {
			if (poll(&pfd, 1, 1000) > 0)
				touch_poll();
		} else {
			sleep(1);
		}
		if (autolaunch_left > 0 && --autolaunch_left == 0)
			desktop_req = 1;
		if (desktop_req) {
			start_desktop();
			if (desktop_req) /* handover confirmed */
				break;
			continue;
		}
		if ((tick++ % 5) != 0)
			continue;

		char buf[256], tmp[128];
		int row = 1;

		clear();

		draw_text(1, row, "NX563J LINUX", HDR);
		row += 1;
		hr(row);
		row += 1;

		snprintf(buf, sizeof(buf), "host   %s", uts.nodename);
		draw_text(1, row++, buf, FG);
		snprintf(buf, sizeof(buf), "kernel %s", uts.release);
		draw_text(1, row++, buf, FG);

		read_first_line("/proc/uptime", tmp, sizeof(tmp));
		double up = strtod(tmp, NULL);
		snprintf(buf, sizeof(buf), "uptime %dd %02ld:%02ld",
			 (int)(up / 86400), ((long)up % 86400) / 3600,
			 ((long)up % 3600) / 60);
		draw_text(1, row++, buf, FG);

		read_first_line("/proc/loadavg", tmp, sizeof(tmp));
		snprintf(buf, sizeof(buf), "load   %.15s", tmp);
		draw_text(1, row++, buf, FG);

		FILE *m = fopen("/proc/meminfo", "r");
		long total = 0, avail = 0;
		char k[32], unit[16];
		long v;
		while (m && fscanf(m, "%31s %ld %15s", k, &v, unit) == 3) {
			if (!strcmp(k, "MemTotal:"))
				total = v;
			if (!strcmp(k, "MemAvailable:"))
				avail = v;
			if (total && avail)
				break;
		}
		if (m)
			fclose(m);
		snprintf(buf, sizeof(buf), "mem    %ld/%ld MB free",
			 avail / 1024, total / 1024);
		draw_text(1, row++, buf, FG);

		struct statvfs sv;
		if (statvfs("/", &sv) == 0) {
			unsigned long long freeb = (unsigned long long)sv.f_bavail * sv.f_frsize;
			unsigned long long totb = (unsigned long long)sv.f_blocks * sv.f_frsize;
			snprintf(buf, sizeof(buf), "rootfs %llu/%llu GB free",
				 freeb >> 30, totb >> 30);
			draw_text(1, row++, buf, FG);
		}

		iface_addr("usb0", tmp, sizeof(tmp));
		draw_text(1, row++, tmp, FG);
		iface_addr("wlan0", tmp, sizeof(tmp));
		draw_text(1, row++, tmp, FG);
		bt_status(tmp, sizeof(tmp));
		draw_text(1, row++, tmp, FG);
		snprintf(buf, sizeof(buf), "ssh    %s :22",
			 port22_listening() ? "listening" : "DOWN");
		draw_text(1, row++, buf, port22_listening() ? FG : 0x000000ff);

		int bl = bl_get();
		if (bl >= 0) {
			snprintf(buf, sizeof(buf), "bl     %d/4095", bl);
			draw_text(1, row++, buf, FG);
		}

		time_t now = time(NULL);
		struct tm *lt = localtime(&now);
		strftime(tmp, sizeof(tmp), "date   %Y-%m-%d %H:%M", lt);
		draw_text(1, row++, tmp, FG);

		hr(row);
		row += 1;
		draw_text(1, row++, "display: JDI R63452 cmd", FG);
		draw_text(1, row++, "touch:   synaptics rmi4 OK", FG);

		if (autolaunch_left > 0) {
			snprintf(buf, sizeof(buf),
				 "entering desktop in %ds", autolaunch_left);
			draw_text(1, row++, buf, HDR);
			draw_text(1, row++, "(tap a button to stay here)", FG);
		}

		draw_buttons();

		var.yoffset = 0;
		var.activate = FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE;
		ioctl(fd, FBIOPUT_VSCREENINFO, &var);
		ioctl(fd, FBIOPAN_DISPLAY, &var);
	}

	/* DESKTOP handover: desktop.sh already holds fb0 (fd 9 there),
	 * so releasing ours never blanks the panel. */
	munmap(fb, fix.smem_len);
	close(fd);
	if (touch_fd >= 0)
		close(touch_fd);
	return 0;
}
