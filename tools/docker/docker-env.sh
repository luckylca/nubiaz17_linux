#!/bin/sh
# nx563j Ubuntu: Docker 运行环境（无 systemd，PID1 自定义 init 适配）
# 用法: 放 /root/docker-env.sh, 由 /root/rc.boot.ubuntu 末尾 source 或执行。
# 前提: 内核含 docker fragment 选项（CI run 35294029286 起）, docker.io 已装。
set -x
exec >> /root/docker-env.log 2>&1

# 1. cgroup v1 控制器挂载（dockerd 需要 cpu/memory/devices/pids/freezer/blkio/net_cls）
mount -t tmpfs none /sys/fs/cgroup 2>/dev/null
for ctl in cpuset cpu cpuacct memory devices pids freezer blkio net_cls perf_event; do
  mkdir -p /sys/fs/cgroup/$ctl
  mount -t cgroup -o $ctl none /sys/fs/cgroup/$ctl 2>/dev/null
done
# name=systemd 层次（docker 某些版本探测用）
mkdir -p /sys/fs/cgroup/systemd
mount -t cgroup -o none,name=systemd none /sys/fs/cgroup/systemd 2>/dev/null

# 2. iptables 后端: 4.4 内核用 legacy（nf_tables 不全）
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# 3. IP 转发（docker 桥接 NAT 需要）
echo 1 > /proc/sys/net/ipv4/ip_forward

# 4. 起 dockerd（containerd 由 dockerd 自带托管）
if ! pidof dockerd > /dev/null; then
  nohup dockerd --iptables=true --storage-driver=overlay2 >> /root/dockerd.log 2>&1 &
fi
