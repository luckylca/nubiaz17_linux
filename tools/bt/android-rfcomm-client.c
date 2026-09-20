#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif
#ifndef BTPROTO_RFCOMM
#define BTPROTO_RFCOMM 3
#endif

typedef struct {
    uint8_t b[6];
} bdaddr_t;

struct sockaddr_rc {
    sa_family_t rc_family;
    bdaddr_t rc_bdaddr;
    uint8_t rc_channel;
};

static int parse_addr(const char *s, bdaddr_t *out) {
    unsigned v[6];
    if (sscanf(s, "%02x:%02x:%02x:%02x:%02x:%02x",
               &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6) {
        return -1;
    }
    for (int i = 0; i < 6; ++i) out->b[i] = (uint8_t)v[5 - i];
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 4) {
        fprintf(stderr, "usage: %s BDADDR [channel] [message]\n", argv[0]);
        return 2;
    }

    int channel = argc >= 3 ? atoi(argv[2]) : 3;
    if (channel < 1 || channel > 30) {
        fprintf(stderr, "invalid RFCOMM channel: %d\n", channel);
        return 2;
    }
    const char *message = argc >= 4 ? argv[3] : "NX563J_RFCOMM_TEST\n";

    struct sockaddr_rc peer;
    memset(&peer, 0, sizeof(peer));
    peer.rc_family = AF_BLUETOOTH;
    peer.rc_channel = (uint8_t)channel;
    if (parse_addr(argv[1], &peer.rc_bdaddr) != 0) {
        fprintf(stderr, "invalid Bluetooth address: %s\n", argv[1]);
        return 2;
    }

    int s = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
    if (s < 0) {
        fprintf(stderr, "socket(AF_BLUETOOTH/RFCOMM): %s\n", strerror(errno));
        return 1;
    }

    struct timeval tv = {.tv_sec = 12, .tv_usec = 0};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (connect(s, (struct sockaddr *)&peer, sizeof(peer)) < 0) {
        fprintf(stderr, "connect(%s channel=%d): %s\n", argv[1], channel, strerror(errno));
        close(s);
        return 1;
    }
    printf("CONNECTED peer=%s channel=%d\n", argv[1], channel);

    size_t len = strlen(message);
    if (write(s, message, len) != (ssize_t)len) {
        fprintf(stderr, "write: %s\n", strerror(errno));
        close(s);
        return 1;
    }
    printf("TX bytes=%zu data=%s", len, message);
    if (len == 0 || message[len - 1] != '\n') putchar('\n');
    fflush(stdout);

    char buf[2048];
    ssize_t n = read(s, buf, sizeof(buf) - 1);
    if (n <= 0) {
        fprintf(stderr, "read ACK: %s\n", n == 0 ? "EOF" : strerror(errno));
        close(s);
        return 1;
    }
    buf[n] = '\0';
    printf("RX bytes=%zd data=%s", n, buf);
    if (buf[n - 1] != '\n') putchar('\n');

    const char prefix[] = "MIXFLIP_ACK:";
    if ((size_t)n < sizeof(prefix) - 1 || memcmp(buf, prefix, sizeof(prefix) - 1) != 0) {
        fprintf(stderr, "ACK prefix mismatch\n");
        close(s);
        return 1;
    }

    puts("RFCOMM_ECHO_PASS");
    close(s);
    return 0;
}
