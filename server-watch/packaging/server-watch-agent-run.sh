#!/bin/sh
# server-watch-agent start wrapper with respawn supervision.
# The Ubuntu rootfs has no systemd (4.4 kernel, PID1=/bin/sh /init), so
# services are hand-started from rc.boot.ubuntu exactly like dockerd.
PATH=/bin:/sbin:/usr/bin:/usr/sbin

mkdir -p /etc/server-watch /var/log
export SERVER_WATCH_CONFIG=/etc/server-watch/config.yaml

while true; do
  /usr/local/bin/server-watch-agent >>/var/log/server-watch-agent.log 2>&1
  echo "$(date '+%F %T') server-watch-agent exited rc=$? — respawning in 3s" >>/var/log/server-watch-agent.log
  sleep 3
done
