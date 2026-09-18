#!/bin/sh
# nx563j Ubuntu: Docker 运行环境（无 systemd，PID1 自定义 init + chroot 架构适配）
# 用法: 放 /root/docker-env.sh, 由 /root/rc.boot.ubuntu 末尾执行。
# 前提: 内核含 docker fragment（CI run 35294029286 起）, docker.io 已装,
#       containerd 必须 1.7.x（2.x 需要 4.4 没有的 pidfd, apt-mark hold）。
set -x
exec >> /root/docker-env.log 2>&1

# 0. lo 必须 up（containerd CRI streaming / docker 都绑 127.0.0.1）
ip link set lo up 2>/dev/null

# 1. chroot 根传播: 已由 rc.boot.ubuntu 的 mntmove 修复(2026-09-19)——
#    ubuntu 自绑被 move 到 PID1 的 /, dockerd unshare 副本的 / 即是挂载根,
#    MS_SLAVE|MS_REC 不再 EINVAL; 同时修了 docker exec 落 initramfs 的
#    mntns_install 问题(详见 UBUNTU_AUDIT 2026-09-19 晚)。
#    此前的 nsenter -t1 bind+rslave 方案与 mntmove 叠加语义不明, 移除。

# 2. cgroup v1 控制器挂载（dockerd 需要 cpu/memory/devices/pids/freezer/blkio）
mount -t tmpfs none /sys/fs/cgroup 2>/dev/null
for ctl in cpuset cpu cpuacct memory devices pids freezer blkio net_cls perf_event; do
  mkdir -p /sys/fs/cgroup/$ctl
  mountpoint -q /sys/fs/cgroup/$ctl || mount -t cgroup -o $ctl none /sys/fs/cgroup/$ctl 2>/dev/null
done
mkdir -p /sys/fs/cgroup/systemd
mountpoint -q /sys/fs/cgroup/systemd || mount -t cgroup -o none,name=systemd none /sys/fs/cgroup/systemd 2>/dev/null

# 3. iptables 后端: 4.4 内核用 legacy（nf_tables 不全）
update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null

# 4. IP 转发（docker 桥接 NAT 需要）
echo 1 > /proc/sys/net/ipv4/ip_forward

# 5. 先 containerd 后 dockerd（顺序错了 dockerd 连不上 leases 服务）
if ! pidof containerd > /dev/null; then
  nohup containerd >> /root/containerd.log 2>&1 &
  sleep 3
fi
if ! pidof dockerd > /dev/null; then
  nohup dockerd >> /root/dockerd.log 2>&1 &
fi
