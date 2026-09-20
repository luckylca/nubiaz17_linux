#!/system/bin/sh
# NX563J NetHunter Docker test harness.
#
# Run as Android root. All Docker-specific mounts live in a private mount
# namespace created by Magisk BusyBox unshare, so Android's global mount tree
# is not modified. The Kali root is self-bound BEFORE chroot so '/' is a real
# mount root; this avoids the CAF 4.4 MakeRSlave("/") EINVAL seen in Docker.
set -eu

BB=${BB:-/data/adb/magisk/busybox}
CHROOT=${CHROOT:-/data/local/nhsystem/kali-arm64}
MODE=${1:-probe}
PIDFILE="$CHROOT/tmp/nx563j-dockerd.pid"
CPIDFILE="$CHROOT/tmp/nx563j-containerd.pid"
SLIRP_PIDFILE="$CHROOT/tmp/nx563j-slirp4netns.pid"
SLIRP_LOG=${SLIRP_LOG:-/data/local/tmp/nx563j-slirp4netns.log}
SLIRP_TAP=${NX_DOCKER_SLIRP_TAP:-tap0}
SLIRP_MTU=${NX_DOCKER_SLIRP_MTU:-65520}
SLIRP_API_REL=/tmp/nx563j-slirp4netns.sock
SLIRP_API="$CHROOT$SLIRP_API_REL"

[ "$(id -u)" = 0 ] || { echo "FAIL: root required" >&2; exit 1; }
[ -x "$BB" ] || { echo "FAIL: Magisk BusyBox missing: $BB" >&2; exit 1; }
[ -x "$CHROOT/bin/sh" ] || { echo "FAIL: Kali chroot missing: $CHROOT" >&2; exit 1; }

inside_ns() {
    mode="$1"

    # Make the chroot directory itself a mount root before chroot(2).
    "$BB" mount -o bind "$CHROOT" "$CHROOT"

    # Populate the device-facing pseudo filesystems only in this namespace.
    "$BB" mkdir -p "$CHROOT/proc" "$CHROOT/sys" "$CHROOT/dev" "$CHROOT/run"
    "$BB" mount -o bind /proc "$CHROOT/proc"
    "$BB" mount -o bind /sys "$CHROOT/sys"
    "$BB" mount -o rbind /dev "$CHROOT/dev"

    if [ "$mode" = probe ]; then
        echo "NS_PROBE_BEGIN"
        echo "host_ns=$($BB readlink /proc/self/ns/mnt 2>/dev/null || true)"
        "$BB" mountpoint "$CHROOT" && echo "chroot_root_mountpoint=YES"
        chroot "$CHROOT" /bin/sh -c '
            PATH=/usr/local/nx-docker-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            export PATH
            echo "inside_root=$(stat -c "dev=%d ino=%i" / 2>/dev/null || true)"
            grep " / " /proc/self/mountinfo 2>/dev/null | head -3 || true
            mount --make-rslave / >/dev/null 2>&1 && echo "make_rslave_root=PASS" || echo "make_rslave_root=FAIL"
        '
        echo "NS_PROBE_END"
        exit 0
    fi

    # Docker setup is performed inside Kali so its tools and paths are used.
    chroot "$CHROOT" /bin/sh -s <<'KALI'
set -eu
PATH=/usr/local/nx-docker-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
TMPDIR=/tmp
export PATH TMPDIR

# Docker/runc expect '/' to have controllable propagation.
mount --make-rslave /

# cgroup v1 hierarchy. This tmpfs and all child cgroup mounts are private to
# the unshared mount namespace and cannot replace Android's global cgroups.
mkdir -p /sys/fs/cgroup
mount -t tmpfs -o mode=755 none /sys/fs/cgroup
for ctl in cpuset cpu cpuacct memory devices pids freezer blkio net_cls perf_event; do
    mkdir -p "/sys/fs/cgroup/$ctl"
    if mount -t cgroup -o "$ctl" none "/sys/fs/cgroup/$ctl" 2>/dev/null; then
        echo "CGROUP_MOUNT_PASS controller=$ctl"
    else
        case "$ctl" in
            cpu|memory|devices|pids|freezer|blkio)
                echo "FAIL: required cgroup v1 controller unavailable: $ctl" >&2
                exit 10
                ;;
            *)
                echo "CGROUP_MOUNT_SKIP controller=$ctl"
                ;;
        esac
    fi
done
mkdir -p /sys/fs/cgroup/systemd
mount -t cgroup -o none,name=systemd none /sys/fs/cgroup/systemd 2>/dev/null || true

# 4.4 uses the legacy xtables backend.
if [ -x /usr/sbin/iptables-legacy ]; then
    update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
fi
if [ -x /usr/sbin/ip6tables-legacy ]; then
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
fi

echo 1 > /proc/sys/net/ipv4/ip_forward
ip link set lo up 2>/dev/null || true
mkdir -p /run /var/lib/docker

for x in containerd dockerd docker runc; do
    command -v "$x" >/dev/null 2>&1 || { echo "FAIL: missing $x" >&2; exit 3; }
done

# containerd 2.x requires pidfd support unavailable on this 4.4 kernel. Keep
# the validated 1.7.x userspace when installing packages.
containerd --version
dockerd --version
runc --version | head -1

# The Kali chroot lives on Android /data. On this downstream 4.4 kernel,
# overlayfs is present but rejects /data-backed directories as an upperdir.
# Default to Docker's portable vfs graphdriver; this can be overridden later
# if a future kernel/filesystem combination supports overlay2 correctly.
STORAGE_DRIVER="${NX_DOCKER_STORAGE_DRIVER:-vfs}"

rm -f /run/containerd/containerd.sock /run/docker.sock /var/run/docker.sock 2>/dev/null || true
mkdir -p /run/containerd
containerd >/tmp/nx563j-containerd.log 2>&1 &
CPID=$!
sleep 3
kill -0 "$CPID" 2>/dev/null || { tail -80 /tmp/nx563j-containerd.log; exit 4; }

echo "DOCKER_STORAGE_DRIVER=$STORAGE_DRIVER"
dockerd --host=unix:///run/docker.sock --containerd=/run/containerd/containerd.sock --storage-driver="$STORAGE_DRIVER" >/tmp/nx563j-dockerd.log 2>&1 &
DPID=$!
for i in $(seq 1 30); do
    [ -S /run/docker.sock ] && break
    kill -0 "$DPID" 2>/dev/null || { tail -120 /tmp/nx563j-dockerd.log; exit 5; }
    sleep 1
done
[ -S /run/docker.sock ] || { echo "FAIL: docker socket timeout"; tail -120 /tmp/nx563j-dockerd.log; exit 6; }

echo "$CPID" > /tmp/nx563j-containerd.pid
echo "$DPID" > /tmp/nx563j-dockerd.pid
sync

echo "DOCKER_NS_READY containerd=$CPID dockerd=$DPID"
# Keep the chroot shell alive for exactly as long as dockerd. This shell is the
# mount-namespace keeper; when dockerd exits, the namespace disappears and all
# private bind/cgroup mounts are automatically cleaned up.
set +e
wait "$DPID"
DRC=$?
kill "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true
exit "$DRC"
KALI
}

get_dpid() {
    [ -f "$PIDFILE" ] || { echo "FAIL: Docker namespace is not running (no $PIDFILE)" >&2; exit 7; }
    DPID=$(cat "$PIDFILE" 2>/dev/null || true)
    case "$DPID" in *[!0-9]*|'') echo "FAIL: invalid dockerd pid: $DPID" >&2; exit 7;; esac
    [ -d "/proc/$DPID" ] || { echo "FAIL: stale dockerd pid $DPID" >&2; exit 7; }
}

run_in_docker_ns() {
    get_dpid
    # Join both the daemon's private mount and network namespaces. Keeping
    # Docker out of Android's global netns avoids parsing/modifying Android's
    # vendor iptables chains (notably the quota2 match unavailable in Kali).
    exec "$BB" nsenter -t "$DPID" -m -n chroot "$CHROOT" /bin/sh -c \
        'PATH=/usr/local/nx-docker-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; TMPDIR=/tmp; export PATH TMPDIR; exec "$@"' sh "$@"
}

inside_uplink() {
    dpid="$1"
    [ -d "/proc/$dpid/ns" ] || { echo "FAIL: target docker pid missing: $dpid" >&2; exit 11; }

    # slirp4netns must stay in Android's host network namespace so its user-mode
    # sockets use the phone's normal uplink. Give the Kali binary a private
    # mount view of host /proc + /dev only; nothing propagates to Android PID1.
    "$BB" mount -o bind "$CHROOT" "$CHROOT"
    "$BB" mkdir -p "$CHROOT/proc" "$CHROOT/dev"
    "$BB" mount -o bind /proc "$CHROOT/proc"
    "$BB" mount -o rbind /dev "$CHROOT/dev"
    rm -f "$SLIRP_API"
    exec "$BB" chroot "$CHROOT" /usr/bin/slirp4netns \
        --configure --mtu="$SLIRP_MTU" --api-socket="$SLIRP_API_REL" \
        "$dpid" "$SLIRP_TAP"
}

start_uplink() {
    get_dpid
    [ -x "$CHROOT/usr/bin/slirp4netns" ] || {
        echo "FAIL: slirp4netns missing in Kali chroot" >&2
        exit 12
    }

    # Do not inherit a stale helper from an earlier test.
    if [ -f "$SLIRP_PIDFILE" ]; then
        old="$(cat "$SLIRP_PIDFILE" 2>/dev/null || true)"
        case "$old" in *[!0-9]*|'') : ;; *) kill "$old" 2>/dev/null || true ;; esac
    fi
    rm -f "$SLIRP_PIDFILE" "$SLIRP_LOG" "$SLIRP_API"

    # Mount namespace only: network namespace intentionally remains Android's
    # host netns. slirp4netns then opens the target Docker netns by dockerd PID.
    "$BB" unshare -m --propagation private "$BB" sh "$0" inside-uplink "$DPID" >"$SLIRP_LOG" 2>&1 &
    SPID=$!
    echo "$SPID" > "$SLIRP_PIDFILE"

    for i in $(seq 1 25); do
        if ! kill -0 "$SPID" 2>/dev/null; then
            cat "$SLIRP_LOG" >&2 || true
            rm -f "$SLIRP_PIDFILE"
            echo "FAIL: slirp4netns exited during startup" >&2
            exit 13
        fi
        if [ -S "$SLIRP_API" ] && "$BB" nsenter -t "$DPID" -n /system/bin/ip -4 addr show "$SLIRP_TAP" 2>/dev/null | "$BB" grep -q '10\.0\.2\.'; then
            echo "DOCKER_UPLINK_STARTED slirp_pid=$SPID tap=$SLIRP_TAP api=$SLIRP_API_REL"
            "$BB" nsenter -t "$DPID" -n /system/bin/ip -4 addr show "$SLIRP_TAP" 2>/dev/null || true
            "$BB" nsenter -t "$DPID" -n /system/bin/ip -4 route 2>/dev/null || true
            return 0
        fi
        sleep 1
    done

    cat "$SLIRP_LOG" >&2 || true
    kill "$SPID" 2>/dev/null || true
    rm -f "$SLIRP_PIDFILE"
    echo "FAIL: slirp4netns uplink timeout" >&2
    exit 14
}

stop_uplink() {
    if [ ! -f "$SLIRP_PIDFILE" ]; then
        echo "DOCKER_UPLINK_STOPPED already-stopped"
        return 0
    fi
    SPID="$(cat "$SLIRP_PIDFILE" 2>/dev/null || true)"
    case "$SPID" in
        *[!0-9]*|'') : ;;
        *) kill "$SPID" 2>/dev/null || true ;;
    esac
    rm -f "$SLIRP_PIDFILE" "$SLIRP_API"
    echo "DOCKER_UPLINK_STOPPED"
}

slirp_api_request() {
    [ -S "$SLIRP_API" ] || { echo "FAIL: slirp4netns API socket missing: $SLIRP_API" >&2; exit 15; }
    req="$1"
    "$BB" chroot "$CHROOT" /bin/sh -c \
        'printf "%s" "$1" | /usr/bin/socat - UNIX-CONNECT:/tmp/nx563j-slirp4netns.sock' sh "$req"
}

add_hostfwd() {
    host_port="${1:-18082}"
    guest_port="${2:-18080}"
    case "$host_port:$guest_port" in *[!0-9:]*|'') echo "FAIL: host/guest ports must be numeric" >&2; exit 2;; esac
    req="{\"execute\":\"add_hostfwd\",\"arguments\":{\"proto\":\"tcp\",\"host_addr\":\"127.0.0.1\",\"host_port\":$host_port,\"guest_addr\":\"10.0.2.100\",\"guest_port\":$guest_port}}"
    resp="$(slirp_api_request "$req")"
    echo "$resp"
    echo "$resp" | "$BB" grep -q '"id"' || { echo "FAIL: slirp add_hostfwd returned no id" >&2; exit 16; }
    echo "DOCKER_HOSTFWD_ADDED host=127.0.0.1:$host_port guest=10.0.2.100:$guest_port"
}

case "$MODE" in
    probe)
        # --propagation private prevents any bind/cgroup mount from propagating
        # back into Android's mount namespace.
        exec "$BB" unshare -m --propagation private "$BB" sh "$0" inside-probe
        ;;
    start)
        rm -f "$PIDFILE" "$CPIDFILE" "$SLIRP_PIDFILE" "$SLIRP_API"
        LOG=/data/local/tmp/nx563j-docker-ns-start.log
        rm -f "$LOG"
        # Keep Docker in private mount + network namespaces. The private netns
        # prevents Docker's iptables chains from colliding with Android's own
        # vendor firewall while the inside-start shell keeps both namespaces
        # addressable through /proc/<dockerd-pid>/ns/{mnt,net}.
        "$BB" unshare -m -n --propagation private "$BB" sh "$0" inside-start >"$LOG" 2>&1 &
        KEEPER=$!
        for i in $(seq 1 40); do
            if [ -f "$PIDFILE" ]; then
                DPID=$(cat "$PIDFILE" 2>/dev/null || true)
                case "$DPID" in *[!0-9]*|'') : ;; *)
                    if [ -d "/proc/$DPID" ]; then
                        echo "DOCKER_NS_STARTED keeper=$KEEPER dockerd=$DPID"
                        exit 0
                    fi
                    ;;
                esac
            fi
            if ! kill -0 "$KEEPER" 2>/dev/null; then
                cat "$LOG" >&2 || true
                echo "FAIL: Docker namespace keeper exited during startup" >&2
                exit 8
            fi
            sleep 1
        done
        cat "$LOG" >&2 || true
        echo "FAIL: Docker namespace startup timeout" >&2
        exit 9
        ;;
    inside-probe)
        inside_ns probe
        ;;
    inside-start)
        inside_ns start
        ;;
    inside-uplink)
        [ "$#" -ge 2 ] || { echo "FAIL: inside-uplink requires dockerd pid" >&2; exit 2; }
        inside_uplink "$2"
        ;;
    uplink-start)
        start_uplink
        ;;
    uplink-status)
        get_dpid
        SPID="$(cat "$SLIRP_PIDFILE" 2>/dev/null || true)"
        echo "slirp_pid=$SPID"
        "$BB" nsenter -t "$DPID" -n /system/bin/ip -4 addr show "$SLIRP_TAP" 2>/dev/null || true
        "$BB" nsenter -t "$DPID" -n /system/bin/ip -4 route 2>/dev/null || true
        ;;
    uplink-stop)
        stop_uplink
        ;;
    hostfwd-add)
        shift
        add_hostfwd "${1:-18082}" "${2:-18080}"
        ;;
    hostfwd-list)
        slirp_api_request '{"execute":"list_hostfwd"}'
        ;;
    status)
        get_dpid
        CPID="$(cat "$CPIDFILE" 2>/dev/null || true)"
        echo "dockerd_pid=$DPID mount_ns=$($BB readlink /proc/$DPID/ns/mnt 2>/dev/null || true) net_ns=$($BB readlink /proc/$DPID/ns/net 2>/dev/null || true)"
        echo "containerd_pid=$CPID"
        run_in_docker_ns docker --host=unix:///run/docker.sock info
        ;;
    docker)
        shift
        run_in_docker_ns docker --host=unix:///run/docker.sock "$@"
        ;;
    shell)
        shift
        [ "$#" -gt 0 ] || { echo "FAIL: shell requires a command" >&2; exit 2; }
        run_in_docker_ns "$@"
        ;;
    stop)
        get_dpid
        CPID="$(cat "$CPIDFILE" 2>/dev/null || true)"
        # Stop user-mode uplink first while the target network namespace exists.
        stop_uplink >/dev/null 2>&1 || true
        # Remove test containers while the daemon namespace is still alive.
        "$BB" nsenter -t "$DPID" -m -n chroot "$CHROOT" /bin/sh -c \
            'PATH=/usr/local/nx-docker-test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; TMPDIR=/tmp; export PATH TMPDIR; docker --host=unix:///run/docker.sock ps -aq 2>/dev/null | xargs -r docker --host=unix:///run/docker.sock rm -f >/dev/null 2>&1 || true' || true
        kill "$DPID" 2>/dev/null || true
        case "$CPID" in *[!0-9]*|'') : ;; *) kill "$CPID" 2>/dev/null || true ;; esac
        rm -f "$PIDFILE" "$CPIDFILE" "$SLIRP_PIDFILE"
        echo "DOCKER_NS_STOPPED"
        ;;
    *)
        echo "Usage: $0 [probe|start|status|uplink-start|uplink-status|uplink-stop|hostfwd-add [host_port guest_port]|hostfwd-list|docker <args...>|shell|stop]" >&2
        exit 2
        ;;
esac
