// touchdump.c — NX563J touch event reader with errno diagnostics.
//
// Reads /dev/input/eventN and prints decoded input events. Unlike od(1),
// it reports the actual errno when open/read fails, so we can tell a
// wedged evdev (ENODEV/ENXIO) apart from plain "no events".
//
// Build on device:  gcc -O2 -o touchdump touchdump.c
// Usage:            ./touchdump [eventN] [seconds]

#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/input/event4";
	int secs = argc > 2 ? atoi(argv[2]) : 30;

	int fd = open(dev, O_RDONLY);
	if (fd < 0) {
		printf("open %s failed: errno=%d (%s)\n", dev, errno, strerror(errno));
		return 1;
	}

	char name[256] = {0};
	if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0)
		printf("EVIOCGNAME failed: errno=%d (%s)\n", errno, strerror(errno));
	else
		printf("name: %s\n", name);

	long t_end = secs;
	printf("reading for %ds...\n", secs);
	while (t_end-- > 0) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		int pr = poll(&pfd, 1, 1000);
		if (pr < 0) {
			printf("poll failed: errno=%d (%s)\n", errno, strerror(errno));
			break;
		}
		if (pr == 0)
			continue;
		struct input_event ev[16];
		ssize_t r = read(fd, ev, sizeof(ev));
		if (r < 0) {
			printf("read failed: errno=%d (%s)\n", errno, strerror(errno));
			break;
		}
		for (int i = 0; i < r / (ssize_t)sizeof(ev[0]); i++) {
			if (ev[i].type == EV_SYN)
				continue;
			printf("type=%u code=%u value=%d\n",
			       ev[i].type, ev[i].code, ev[i].value);
		}
		fflush(stdout);
	}
	printf("done\n");
	return 0;
}
