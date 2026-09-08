/* logcatd.c — minimal fake logd for NX563J bionic daemons.
 * Binds /dev/socket/logdw (SOCK_DGRAM), reads liblog records:
 *   iovec[0] = android_log_header_t {id,tid,sec,nsec,uid,pid} (6x u32)
 *   iovec[1] = payload: for LOG_ID_MAIN: [prio][tag\0][msg\0]
 * Prints "<id> <pid> <prio> <tag>: <msg>" to stdout (append to file).
 */
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

int main(int argc, char **argv)
{
	const char *path = "/dev/socket/logdw";
	int fd;
	struct sockaddr_un sa;
	char buf[4096];

	mkdir("/dev/socket", 0755);
	unlink(path);
	fd = socket(PF_UNIX, SOCK_DGRAM, 0);
	if (fd < 0) { perror("socket"); return 1; }
	memset(&sa, 0, sizeof(sa));
	sa.sun_family = AF_UNIX;
	strncpy(sa.sun_path, path, sizeof(sa.sun_path) - 1);
	if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
		perror("bind"); return 1;
	}
	chmod(path, 0666);
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("logcatd: listening on %s\n", path);

	for (;;) {
		ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
		if (n < 0) { if (errno == EINTR) continue; perror("recv"); return 1; }
		buf[n] = 0;
		if (n < 25) continue;		/* header(24) + prio(1) min */
		unsigned *h = (unsigned *)buf;
		unsigned id = h[0], pid = h[5];
		char *p = buf + 24;		/* skip header */
		int plen = n - 24;
		int prio = (unsigned char)p[0];
		char *tag = p + 1;
		char *msg = memchr(tag, 0, plen - 1);
		if (!msg) continue;
		msg++;
		/* sanitize: make sure printable */
		for (int i = 0; i < plen - (int)(tag - p); i++)
			if (tag[i] && (tag[i] < 32 || tag[i] > 126)) tag[i] = '.';
		for (int i = 0; i < plen - (int)(msg - p); i++)
			if (msg[i] && (msg[i] < 32 || msg[i] > 126)) msg[i] = '.';
		printf("%u %u %c %s: %s\n", id, pid,
		       prio >= 2 && prio <= 7 ? "VDIWEF?"[prio - 2] : '?', tag, msg);
	}
	return 0;
}
