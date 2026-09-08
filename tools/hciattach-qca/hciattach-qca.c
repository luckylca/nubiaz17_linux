/* hciattach-qca.c — attach the kernel hci_uart QCA line discipline on
 * /dev/ttyHS0 for the NX563J WCN3990 (Cherokee) Bluetooth block.
 *
 * Use AFTER /vendor/bin/hci_qcomm_init -e -N (which downloads the TLV
 * rampatch+NVM and leaves the chip at 3000000 baud). This tool only
 * does the kernel-side attach that BlueZ's hciattach cannot express
 * on this kernel: raw termios @3M + CRTSCTS, N_HCI line discipline,
 * HCI_UART_QCA protocol id (8, see drivers/bluetooth/hci_uart.h).
 *
 * Then: hciconfig hci0 up / bluetoothd.
 *
 * Build on device (musl): gcc -O2 -o hciattach-qca hciattach-qca.c
 * (musl lacks termios2, so the kernel ABI is defined locally.)
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

/* kernel asm-generic termios2 ABI (arm64) */
#define K_NCCS 19
struct termios2 {
	tcflag_t c_iflag;
	tcflag_t c_oflag;
	tcflag_t c_cflag;
	tcflag_t c_lflag;
	cc_t c_line;
	cc_t c_cc[K_NCCS];
	speed_t c_ispeed;
	speed_t c_ospeed;
};
#define K_TCGETS2	_IOR('T', 0x2A, struct termios2)
#define K_TCSETS2	_IOW('T', 0x2B, struct termios2)
#define K_BOTHER	0010000
#define K_CBAUD		0010017
#ifndef CRTSCTS
#define CRTSCTS		020000000000
#endif

#define N_HCI		15
#define HCIUARTSETPROTO	_IOW('U', 200, int)
#define HCI_UART_QCA	8

static int set_speed(int fd, int baud)
{
	struct termios2 tio;

	memset(&tio, 0, sizeof(tio));
	if (ioctl(fd, K_TCGETS2, &tio) < 0) {
		perror("TCGETS2");
		return -1;
	}
	tio.c_cflag &= ~(K_CBAUD | CSTOPB | PARENB | PARODD | CSIZE);
	tio.c_cflag |= K_BOTHER | CS8 | CREAD | CLOCAL | CRTSCTS;
	tio.c_iflag = 0;
	tio.c_oflag = 0;
	tio.c_lflag = 0;
	tio.c_ispeed = baud;
	tio.c_ospeed = baud;
	if (ioctl(fd, K_TCSETS2, &tio) < 0) {
		perror("TCSETS2");
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/ttyHS0";
	int baud = argc > 2 ? atoi(argv[2]) : 3000000;
	int fd, ldisc, proto;

	fd = open(dev, O_RDWR | O_NOCTTY);
	if (fd < 0) {
		perror(dev);
		return 1;
	}
	if (set_speed(fd, baud) < 0)
		return 1;

	ldisc = N_HCI;
	if (ioctl(fd, TIOCSETD, &ldisc) < 0) {
		perror("TIOCSETD N_HCI");
		return 1;
	}
	proto = HCI_UART_QCA;
	if (ioctl(fd, HCIUARTSETPROTO, proto) < 0) {
		perror("HCIUARTSETPROTO QCA");
		return 1;
	}
	printf("hci_uart QCA attached on %s @%d - hci0 should exist now\n",
	       dev, baud);

	/* Detach into background like hciattach: the ldisc dies with us. */
	if (daemon(0, 0) < 0) {
		perror("daemon");
		return 1;
	}
	for (;;)
		pause();
	return 0;
}
