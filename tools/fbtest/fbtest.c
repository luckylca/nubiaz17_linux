// fbtest.c — NX563J mdss framebuffer bring-up test.
//
// Opens /dev/fb0 (holding it open so the cmd-mode panel does not
// re-suspend), unblanks, mmaps the framebuffer, draws full-screen color
// bands, and commits the frame with FBIOPAN_DISPLAY (the path that makes
// the mdss driver kick off a DSI command-mode panel update).
//
// Build on device:  gcc -O2 -static -o fbtest fbtest.c
// Usage:            ./fbtest [hold_seconds]

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int hold = argc > 1 ? atoi(argv[1]) : 30;
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
	printf("res %ux%u virt %ux%u bpp %u stride %u smem %zu\n",
	       var.xres, var.yres, var.xres_virtual, var.yres_virtual,
	       var.bits_per_pixel, fix.line_length, (size_t)fix.smem_len);

	if (ioctl(fd, FBIOBLANK, 0) < 0) /* FB_BLANK_UNBLANK */
		perror("FBIOBLANK unblank");

	uint32_t *fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE,
	                    MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}

	/* Four landscape bands: red, green, blue, white (portrait panel). */
	static const uint32_t band[4] = {
		0x00ff0000, 0x0000ff00, 0x000000ff, 0x00ffffff
	};
	uint32_t stride = fix.line_length / 4;
	for (uint32_t y = 0; y < var.yres; y++) {
		uint32_t c = band[y * 4 / var.yres];
		uint32_t *row = fb + y * stride;
		for (uint32_t x = 0; x < var.xres; x++)
			row[x] = c;
	}
	printf("frame drawn, committing\n");

	var.yoffset = 0;
	var.activate = FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE;
	if (ioctl(fd, FBIOPUT_VSCREENINFO, &var) < 0)
		perror("FBIOPUT_VSCREENINFO");
	if (ioctl(fd, FBIOPAN_DISPLAY, &var) < 0)
		perror("FBIOPAN_DISPLAY");

	printf("holding %ds with panel alive\n", hold);
	sleep(hold);
	return 0;
}
