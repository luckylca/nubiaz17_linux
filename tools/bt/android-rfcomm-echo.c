#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
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

static void format_addr(const bdaddr_t *a, char out[18]) {
    snprintf(out, 18, "%02X:%02X:%02X:%02X:%02X:%02X",
             a->b[5], a->b[4], a->b[3], a->b[2], a->b[1], a->b[0]);
}

int main(int argc, char **argv) {
    int channel = 3;
    if (argc > 1) {
        channel = atoi(argv[1]);
        if (channel < 1 || channel > 30) {
            fprintf(stderr, "invalid RFCOMM channel: %d\n", channel);
            return 2;
        }
    }

    int s = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
    if (s < 0) {
        fprintf(stderr, "socket(AF_BLUETOOTH/RFCOMM): %s\n", strerror(errno));
        return 1;
    }

    struct sockaddr_rc local;
    memset(&local, 0, sizeof(local));
    local.rc_family = AF_BLUETOOTH;
    local.rc_channel = (uint8_t)channel;

    if (bind(s, (struct sockaddr *)&local, sizeof(local)) < 0) {
        fprintf(stderr, "bind(channel=%d): %s\n", channel, strerror(errno));
        close(s);
        return 1;
    }
    if (listen(s, 1) < 0) {
        fprintf(stderr, "listen: %s\n", strerror(errno));
        close(s);
        return 1;
    }

    printf("READY channel=%d\n", channel);
    fflush(stdout);

    struct sockaddr_rc peer;
    socklen_t peer_len = sizeof(peer);
    memset(&peer, 0, sizeof(peer));
    int c = accept(s, (struct sockaddr *)&peer, &peer_len);
    if (c < 0) {
        fprintf(stderr, "accept: %s\n", strerror(errno));
        close(s);
        return 1;
    }

    char peer_addr[18];
    format_addr(&peer.rc_bdaddr, peer_addr);
    printf("CONNECTED peer=%s channel=%u\n", peer_addr, peer.rc_channel);
    fflush(stdout);

    char buf[1024];
    for (;;) {
        ssize_t n = read(c, buf, sizeof(buf) - 1);
        if (n == 0) {
            printf("EOF\n");
            break;
        }
        if (n < 0) {
            fprintf(stderr, "read: %s\n", strerror(errno));
            close(c);
            close(s);
            return 1;
        }
        buf[n] = '\0';
        printf("RX bytes=%zd data=%s", n, buf);
        if (buf[n - 1] != '\n') putchar('\n');
        fflush(stdout);

        const char prefix[] = "MIXFLIP_ACK:";
        if (write(c, prefix, sizeof(prefix) - 1) < 0 || write(c, buf, (size_t)n) < 0) {
            fprintf(stderr, "write: %s\n", strerror(errno));
            close(c);
            close(s);
            return 1;
        }
    }

    close(c);
    close(s);
    return 0;
}
