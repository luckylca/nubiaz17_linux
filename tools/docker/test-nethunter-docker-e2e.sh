#!/usr/bin/env bash
# NX563J NetHunter Docker E2E smoke test.
# Host-side script: run from macOS with NX563J connected by ADB.
# It NEVER flashes partitions. It expects the Docker-capable test kernel to
# already be running and uses only the test userspace under /usr/local/nx-docker-test.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
SER="${SER:-392a99df}"
CHROOT="/data/local/nhsystem/kali-arm64"
HARNESS_LOCAL="$ROOT/tools/docker/nethunter-docker-ns.sh"
HARNESS_REMOTE="/data/local/tmp/nethunter-docker-ns.sh"
IMAGE="nx563j-busybox:test"

adb() { "$ADB" -s "$SER" "$@"; }
rootsh() {
  # Transport the command as base64 so nested quotes/templates survive adb +
  # su -c unchanged. This keeps later docker --format and sh -c probes robust.
  local encoded
  encoded="$(printf '%s' "$1" | base64 | tr -d '\n')"
  adb shell "su -c 'echo $encoded | /data/adb/magisk/busybox base64 -d | /system/bin/sh'"
}

host_docker_firewall_markers() {
  # Track only Docker/uplink-specific rules. Android/netd may legitimately
  # update unrelated chains and counters while this test is running.
  adb shell 'su -c "/system/bin/iptables-save 2>/dev/null"' \
    | tr -d '\r' \
    | grep -E '(^|[^A-Za-z])(DOCKER|docker0|tap0|172\.17\.|10\.0\.2\.)' \
    || true
}

cleanup() {
  set +e
  rootsh "$HARNESS_REMOTE stop" >/dev/null 2>&1 || true
  rootsh "pkill -f '/data/adb/magisk/busybox httpd -f -p 18081' 2>/dev/null || true; rm -rf $CHROOT/tmp/nx-docker-rootfs $CHROOT/tmp/nx-busybox-rootfs.tar $CHROOT/tmp/nx-bind $CHROOT/tmp/nx-www /data/local/tmp/nx-uplink-www" >/dev/null 2>&1 || true
  set -e
}
trap cleanup EXIT
HOST_FW_MARKERS_BEFORE="$(host_docker_firewall_markers)"

printf '=== ADB / kernel ===\n'
adb get-state
adb shell uname -a

printf '\n=== required kernel config ===\n'
CFG_KEYS='CGROUP_DEVICE CGROUP_PIDS PID_NS IPC_NS USER_NS POSIX_MQUEUE DEVPTS_MULTIPLE_INSTANCES VETH BRIDGE_NETFILTER MEMCG_KMEM MEMCG_SWAP'
CONFIG="$(adb shell 'zcat /proc/config.gz 2>/dev/null' | tr -d '\r')"
for k in $CFG_KEYS; do
  if grep -Fxq "CONFIG_${k}=y" <<<"$CONFIG"; then
    echo "KCONFIG_PASS CONFIG_${k}=y"
  else
    echo "KCONFIG_FAIL CONFIG_${k}" >&2
    exit 20
  fi
done
if grep -Fxq 'CONFIG_USB_DUMMY_HCD=y' <<<"$CONFIG"; then
  echo 'KCONFIG_FAIL unsafe CONFIG_USB_DUMMY_HCD=y' >&2
  exit 21
else
  echo 'KCONFIG_PASS CONFIG_USB_DUMMY_HCD disabled'
fi

printf '\n=== install harness ===\n'
adb push "$HARNESS_LOCAL" "$HARNESS_REMOTE" >/dev/null
rootsh "chmod 755 $HARNESS_REMOTE"

# Refuse to kill unrelated processes. Remove only stale processes whose exe is
# our isolated test binary.
printf '\n=== clean stale test daemons ===\n'
for name in dockerd containerd; do
  for p in $(adb shell "su -c 'pidof $name 2>/dev/null || true'" | tr -d '\r'); do
    exe="$(adb shell "su -c 'readlink /proc/$p/exe 2>/dev/null || true'" | tr -d '\r')"
    case "$exe" in
      "$CHROOT/usr/local/nx-docker-test/bin/$name")
        echo "KILL_STALE_TEST_PROCESS name=$name pid=$p"
        rootsh "kill $p 2>/dev/null || true"
        ;;
      *)
        echo "KEEP_NONTEST_PROCESS name=$name pid=$p exe=$exe"
        ;;
    esac
  done
done
rootsh "rm -f $CHROOT/tmp/nx563j-dockerd.pid $CHROOT/tmp/nx563j-containerd.pid"

printf '\n=== start isolated Docker namespace ===\n'
rootsh "$HARNESS_REMOTE start"
sleep 2
rootsh "$HARNESS_REMOTE status" | sed -n '1,120p'

printf '\n=== slirp4netns user-mode uplink ===\n'
if rootsh "test -x $CHROOT/usr/bin/slirp4netns" >/dev/null 2>&1; then
  # A host-local HTTP endpoint lets us prove the complete container -> docker0
  # -> slirp TAP -> Android host path even when the phone itself is offline.
  rootsh "mkdir -p /data/local/tmp/nx-uplink-www; echo NX563J_UPLINK_HOST_OK > /data/local/tmp/nx-uplink-www/index.html; pkill -f '/data/adb/magisk/busybox httpd -f -p 18081' 2>/dev/null || true; /data/adb/magisk/busybox httpd -f -p 18081 -h /data/local/tmp/nx-uplink-www >/data/local/tmp/nx-uplink-http.log 2>&1 &"
  rootsh "$HARNESS_REMOTE uplink-start"
  rootsh "$HARNESS_REMOTE uplink-status" | sed -n '1,80p'
else
  echo UPLINK_SKIP_SLIRP4NETNS_NOT_INSTALLED
fi

printf '\n=== create offline ARM64 BusyBox image ===\n'
rootsh "rm -rf $CHROOT/tmp/nx-docker-rootfs; mkdir -p $CHROOT/tmp/nx-docker-rootfs/bin $CHROOT/tmp/nx-docker-rootfs/tmp $CHROOT/tmp/nx-docker-rootfs/etc; cp /data/adb/magisk/busybox $CHROOT/tmp/nx-docker-rootfs/bin/busybox; chmod 755 $CHROOT/tmp/nx-docker-rootfs/bin/busybox; ln -sf busybox $CHROOT/tmp/nx-docker-rootfs/bin/sh; cd $CHROOT/tmp/nx-docker-rootfs && /data/adb/magisk/busybox tar -cf $CHROOT/tmp/nx-busybox-rootfs.tar ."
rootsh "$HARNESS_REMOTE docker image rm -f $IMAGE >/dev/null 2>&1 || true"
rootsh "$HARNESS_REMOTE docker import /tmp/nx-busybox-rootfs.tar $IMAGE"
rootsh "$HARNESS_REMOTE docker image inspect $IMAGE --format 'IMAGE_PASS id={{.Id}} arch={{.Architecture}} os={{.Os}}'"

printf '\n=== docker run / default IPC+mqueue ===\n'
RUN_OUT="$(rootsh "$HARNESS_REMOTE docker run --rm $IMAGE /bin/busybox sh -c 'echo CONTAINER_RUN_PASS; /bin/busybox uname -m; /bin/busybox id; test -d /dev/mqueue && echo MQUEUE_PATH_PASS || true'" | tr -d '\r')"
printf '%s\n' "$RUN_OUT"
printf '%s\n' "$RUN_OUT" | grep -q CONTAINER_RUN_PASS

if rootsh "test -x $CHROOT/usr/bin/slirp4netns" >/dev/null 2>&1; then
  UPLINK_OUT="$(rootsh "$HARNESS_REMOTE docker run --rm $IMAGE /bin/busybox wget -qO- http://10.0.2.2:18081/" | tr -d '\r')"
  echo "$UPLINK_OUT"
  [ "$UPLINK_OUT" = 'NX563J_UPLINK_HOST_OK' ]
  echo USERMODE_UPLINK_DATAPATH_PASS

  # Internet is a separate proof. Do not fail the Docker runtime E2E merely
  # because Android currently has no Wi-Fi/mobile uplink.
  HOST_ROUTE="$(rootsh "/system/bin/ip -4 route 2>/dev/null | /data/adb/magisk/busybox grep '^default ' | /data/adb/magisk/busybox head -1 || true" | tr -d '\r')"
  if [ -n "$HOST_ROUTE" ]; then
    if rootsh "$HARNESS_REMOTE docker run --rm $IMAGE /bin/busybox wget -q -T 12 -O /dev/null http://connectivitycheck.gstatic.com/generate_204" >/dev/null 2>&1; then
      echo CONTAINER_INTERNET_PASS
    else
      echo CONTAINER_INTERNET_WARN_HOST_HAS_ROUTE_BUT_PROBE_FAILED
    fi
  else
    echo CONTAINER_INTERNET_SKIP_HOST_OFFLINE
  fi
fi

printf '\n=== docker exec ===\n'
rootsh "$HARNESS_REMOTE docker rm -f nxexec >/dev/null 2>&1 || true"
rootsh "$HARNESS_REMOTE docker run -d --name nxexec $IMAGE /bin/busybox sleep 120" >/dev/null
EXEC_OUT="$(rootsh "$HARNESS_REMOTE docker exec nxexec /bin/sh -c 'echo CONTAINER_EXEC_PASS'" | tr -d '\r')"
printf '%s\n' "$EXEC_OUT"
printf '%s\n' "$EXEC_OUT" | grep -q CONTAINER_EXEC_PASS
rootsh "$HARNESS_REMOTE docker rm -f nxexec" >/dev/null

printf '\n=== bind mount ===\n'
rootsh "mkdir -p $CHROOT/tmp/nx-bind; echo NX563J_BIND_OK > $CHROOT/tmp/nx-bind/marker.txt"
BIND_OUT="$(rootsh "$HARNESS_REMOTE docker run --rm -v /tmp/nx-bind:/mnt:ro $IMAGE /bin/busybox cat /mnt/marker.txt" | tr -d '\r')"
echo "$BIND_OUT"
[ "$BIND_OUT" = 'NX563J_BIND_OK' ]
echo BIND_MOUNT_PASS

printf '\n=== memory / cpu cgroup options ===\n'
rootsh "$HARNESS_REMOTE docker rm -f nxcg >/dev/null 2>&1 || true"
rootsh "$HARNESS_REMOTE docker run -d --name nxcg --memory=67108864 --cpu-shares=512 $IMAGE /bin/busybox sleep 120" >/dev/null
CG_OUT="$(rootsh "$HARNESS_REMOTE docker inspect nxcg --format 'MEM={{.HostConfig.Memory}} CPU={{.HostConfig.CpuShares}}'" | tr -d '\r')"
echo "$CG_OUT"
echo "$CG_OUT" | grep -q 'MEM=67108864 CPU=512'
echo CGROUP_LIMIT_CONFIG_PASS
rootsh "$HARNESS_REMOTE docker rm -f nxcg" >/dev/null

printf '\n=== bridge networking ===\n'
rootsh "mkdir -p $CHROOT/tmp/nx-www; echo NX563J_HTTP_OK > $CHROOT/tmp/nx-www/index.html"
rootsh "$HARNESS_REMOTE docker rm -f nxhttp >/dev/null 2>&1 || true"
rootsh "$HARNESS_REMOTE docker run -d --name nxhttp -p 18080:8080 -v /tmp/nx-www:/www:ro $IMAGE /bin/busybox httpd -f -p 8080 -h /www" >/dev/null
CIP="$(rootsh "$HARNESS_REMOTE docker inspect nxhttp --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'" | tr -d '\r')"
echo "container_ip=$CIP"
[ -n "$CIP" ]
HTTP_OUT="$(rootsh "$HARNESS_REMOTE shell /usr/bin/curl -fsS http://$CIP:8080/" | tr -d '\r')"
echo "$HTTP_OUT"
[ "$HTTP_OUT" = 'NX563J_HTTP_OK' ]
echo BRIDGE_DATA_PASS

# Even when the Docker daemon intentionally has no external uplink, -p must
# still publish inside its private network namespace. This validates Docker's
# own DNAT/port-publish path without touching Android's global firewall.
PORT_LOOPBACK_OUT="$(rootsh "$HARNESS_REMOTE shell /usr/bin/curl -fsS http://127.0.0.1:18080/" | tr -d '\r')"
echo "$PORT_LOOPBACK_OUT"
[ "$PORT_LOOPBACK_OUT" = 'NX563J_HTTP_OK' ]
echo PORT_MAPPING_PRIVATE_NS_PASS

# Port publishing is considered a hard PASS if reachable through any non-loopback
# host address. If the phone currently has no global address, record a SKIP and
# leave the direct bridge datapath as the networking proof.
HOST_IP="$(rootsh "$HARNESS_REMOTE shell /bin/sh -c \"ip -4 -o addr show scope global 2>/dev/null | awk '\\\$2 != \\\"docker0\\\" && \\\$4 !~ /^172\\.17\\./ {sub(/\\/.*/,\\\"\\\",\\\$4); print \\\$4; exit}'\"" | tr -d '\r')"
  case "$HOST_IP" in 10.0.2.*|172.17.*) HOST_IP="" ;; esac
if [ -n "$HOST_IP" ]; then
  echo "host_ip=$HOST_IP"
  PORT_OUT="$(rootsh "$HARNESS_REMOTE shell /usr/bin/curl -fsS http://$HOST_IP:18080/" | tr -d '\r' || true)"
  if [ "$PORT_OUT" = 'NX563J_HTTP_OK' ]; then
    echo PORT_MAPPING_PASS
  else
    echo "PORT_MAPPING_WARN host_ip=$HOST_IP response=$PORT_OUT"
  fi
else
  echo PORT_MAPPING_SKIP_NO_GLOBAL_HOST_IP
fi
rootsh "$HARNESS_REMOTE docker rm -f nxhttp" >/dev/null

printf '\n=== daemon/storage summary ===\n'
rootsh "$HARNESS_REMOTE docker info --format 'DOCKER_INFO_PASS server={{.ServerVersion}} driver={{.Driver}} cgroup={{.CgroupDriver}} containers={{.Containers}} images={{.Images}}'"

printf '\n=== stop / host mount leak check ===\n'
rootsh "$HARNESS_REMOTE stop"
trap - EXIT
LEAK="$(rootsh "grep -E 'kali-arm64|/sys/fs/cgroup/(devices|pids|memory)|nx-docker' /proc/1/mountinfo || true" | tr -d '\r')"
if [ -n "$LEAK" ]; then
  echo "$LEAK"
  echo HOST_MOUNT_LEAK_FAIL >&2
  exit 30
fi
HOST_FW_MARKERS_AFTER="$(host_docker_firewall_markers)"
if [ "$HOST_FW_MARKERS_BEFORE" != "$HOST_FW_MARKERS_AFTER" ]; then
  echo 'Android host Docker-specific iptables markers changed:' >&2
  printf '%s\n' "$HOST_FW_MARKERS_AFTER" >&2
  echo HOST_DOCKER_FIREWALL_POLLUTION_FAIL >&2
  exit 31
fi
echo ANDROID_DOCKER_FIREWALL_UNCHANGED_PASS
echo HOST_MOUNT_LEAK_PASS

echo 'NX563J_NETHUNTER_DOCKER_E2E_PASS'
