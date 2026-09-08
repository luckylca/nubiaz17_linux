// fbdash.c — NX563J framebuffer status dashboard.
//
// Long-lived fb0 holder (keeps the cmd-mode panel alive) that renders a
// status page with the kernel 8x16 font scaled 2x: hostname, kernel,
// uptime, load, memory, rootfs usage, usb0 address and SSH listener.
// Refreshes every few seconds and re-commits via FBIOPAN_DISPLAY.
//
// Build on device:  gcc -O2 -static -o fbdash fbdash.c
// Run:              nohup ./fbdash &

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <net/if.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "font8x16.h"

#define SCALE 2
#define CW (8 * SCALE)
#define CH (16 * SCALE)
#define FG 0x00e8e8e8 /* near-white */
#define ACCENT 0x0000d7ff /* orange-ish: b,g,r byte order below is little-endian 0x00RRGGBB */
#define HDR 0x00ffaa00
#define BG 0x00000000

static uint32_t *fb;
static uint32_t stride, xres, yres;

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

static void usb0_addr(char *out, size_t n)
{
	int s = socket(AF_INET, SOCK_DGRAM, 0);
	struct ifreq ifr;
	snprintf(ifr.ifr_name, IFNAMSIZ, "usb0");
	if (s < 0 || ioctl(s, SIOCGIFADDR, &ifr) < 0) {
		snprintf(out, n, "usb0: down");
		if (s >= 0)
			close(s);
		return;
	}
	struct sockaddr_in *sa = (struct sockaddr_in *)&ifr.ifr_addr;
	snprintf(out, n, "usb0: %s", inet_ntoa(sa->sin_addr));
	close(s);
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

	for (;;) {
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

		usb0_addr(tmp, sizeof(tmp));
		draw_text(1, row++, tmp, FG);
		snprintf(buf, sizeof(buf), "ssh    %s :22",
			 port22_listening() ? "listening" : "DOWN");
		draw_text(1, row++, buf, port22_listening() ? FG : 0x000000ff);

		hr(row);
		row += 1;
		draw_text(1, row++, "display: JDI R63452 cmd", FG);
		draw_text(1, row++, "touch:   synaptics rmi4", FG);
		draw_text(1, row++, "telnet fallback :23", FG);

		var.yoffset = 0;
		var.activate = FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE;
		ioctl(fd, FBIOPUT_VSCREENINFO, &var);
		ioctl(fd, FBIOPAN_DISPLAY, &var);

		sleep(5);
	}
}
