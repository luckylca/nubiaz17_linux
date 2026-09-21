# NetHunter 路线图 — NX563J (msm8998, 4.4.302 downstream)

目标：把 NX563J 做成 NetHunter 硬件能力参考平台。先 Ubuntu 24.04 用户态
验证全部能力，再上 LineageOS + 官方 Kali NetHunter 设备提交
（repo: luckylca/android_kernel_nubia_msm8998_nethunter → Kali devices.yml）。

验证纪律见 docs/NETHUNTER_CAPABILITIES.md 头部：只有真机实测才标 PASS；
硬件未到位的一律 WAITING_FOR_HARDWARE；不伪造结果。

| Phase | 内容 | 状态 | 证据/备注 |
|-------|------|------|-----------|
| 1 | 工程恢复、基线内核 CI | ✅ 完成 | build-downstream.yml, 内核 cda6a278 |
| 2 | WCN3990 帧注入 (TX) | 🟡 主机侧链路全通(含 daily2 内核回归 2026-09-15: 20/20)，待 RF 证明 | patches/downstream/0009; RF 证明方案就绪: Mac en0 作第二嗅探器 (/tmp/rf-proof.sh, 需一次 sudo); 注意 daily2 上 con_mode 4→0 回切疑似回归致整机 wedge (RESEARCH.md 2026-09-15) |
| 3 | monitor→mission 恢复 | ✅ PASS | 2026-09-12 两轮完整循环零 assert |
| 4 | USB HID 键盘/鼠标/复合 | ✅ PASS | 2026-09-14 主机实收文本+指针移动; tools/usb-hid/ |
| 5 | 外置 USB Wi-Fi (ath9k_htc/rtl8xxxu) | 🟡 内核构建中 | fragment 就绪; 补丁 0010-0012 修 in-tree 驱动编译; 实测 WAITING_FOR_HARDWARE (OTG+网卡) |
| 6 | USB Host/OTG 稳定性 | ⏳ WAITING_FOR_HARDWARE | 需 OTG 线 |
| 7 | BT RFCOMM/BNEP/raw HCI | ✅ **PASS** | raw HCI 2026-09-14 PASS；2026-09-20 以 rooted MIX Flip 为对端完成 bond、RFCOMM 双向 payload/ACK 与 PAN/BNEP 数据链实测 |
| 8 | USB BT  dongle | ⏳ 驱动已预置(BT_HCIBTUSB) | WAITING_FOR_HARDWARE |
| 9 | SocketCAN (gs_usb/vcan/slcan) | ✅ VCAN/SLCAN 软件闭环 PASS；gs_usb 待硬件 | 2026-09-20 GitHub Actions run `35484288726` future kernel 真机启动；VCAN CAN_RAW `0x563/NX563J` 回环 PASS；PTY 模拟 LAWICEL 的 SLCAN 双向 CAN↔ASCII PASS；真实 gs_usb CAN adapter 仍 WAITING_FOR_HARDWARE |
| 10 | SDR (RTL-SDR) | ⏳ 纯用户态, 依赖 Phase 6 | WAITING_FOR_HARDWARE |
| 11 | USB 以太网 (RTL815x) | ⏳ defconfig 已 =y | WAITING_FOR_HARDWARE |
| 11A | USB 串口/调试适配器 | 🟡 future kernel 已构建并真机注册 ACM/CH341/CP210X/FTDI/PL2303 | GitHub Actions run `35484288726` 全量构建 PASS；真机 `/sys/bus/usb-serial/drivers` 已见 ch341-uart/cp210x/ftdi_sio/pl2303；实际 USB 转串口收发仍 WAITING_FOR_HARDWARE，不进入首版 MR feature |
| 11B | Docker | ✅ **PASS（正式 promotion kernel）** | 2026-09-21 正式 `nethunter-22.2` / `a180aa33` CI artifact 真机完成 `run/exec/mqueue/bind/cgroup/bridge/-p/storage/cleanup`、slirp 双向 uplink/hostfwd、Android firewall 隔离、公网 IPv4/DNS/域名 HTTP 全矩阵；`Docker` 已进入首版官方 feature |
| 12 | NFS | ✅ **PASS** | 2026-09-15 实机挂载 Mac nfsd 双向读写验证; 走 usb1/en156 第二对 (usb0 对设备→Mac 单通) |
| 13 | config 片段整合 | ✅ daily fragment 机制 | CI 每次只 merge 一个 fragment |
| 14 | 回归测试 | 🟡 持续 | 每次新内核刷入后回归 BT/音频/HID |
| 15 | 能力矩阵定稿 | 🟡 持续维护 | docs/NETHUNTER_CAPABILITIES.md |

## 2026-09-20 future-support 真机验证

- 临时 kernel 分支 `nethunter-future-test-20260920` 仅用于实验，不替代首版官方 MR 的 `nethunter-22.2` 分支。GitHub Actions run `35484288726` 全绿；future `Image.gz-dtb` SHA256=`f18ab1eeffa4632a5f19fa70ab9051af86a8030541bb57f13fd43567693be02a`，最终 `kernel.config` SHA256=`1c2a1edcfb9f8b5f1dc277cd0de58a09823c174891e56ae719181ac51e11004f`。
- 以刷测前 boot 精确 dump 为 ramdisk/boot geometry 基线，只替换 future kernel 并重新签名；测试 boot SHA256=`21097d61ad038eec794210a5389987f3a80797158552b07ada20486845fea663`。真机启动到 `4.4.302-perf+ #1 SMP PREEMPT Sun Sep 20 02:33:14 UTC 2026`，Magisk root、Kali chroot、wlan0、Bluetooth ON、USB configfs functions 均回归正常。
- VCAN：`tools/can/vcan-smoke.sh` 创建 `vcan0`，CAN_RAW 发送并实收 CAN ID `0x563` / payload `NX563J`，输出 `VCAN_LOOPBACK_PASS`。
- SLCAN：`tools/can/slcan-pty-smoke.py` 用 PTY 模拟 LAWICEL 串口适配器；CAN→TTY 实收 `t56364E583536334A`，TTY→CAN 实收 ID `0x456` / `Z17`，输出 `SLCAN_PTY_PASS`。整个测试不依赖外部 CAN/串口硬件。
- 同一 future kernel 的 `ch341-uart`、`cp210x`、`ftdi_sio`、`pl2303` 与 `rndis_host` 均在运行态 sysfs 注册；实际 USB 外设收发仍保持 WAITING_FOR_HARDWARE。
- 测试结束后已刷回 `work/future-test/boot-stable-before-future.img`；从 boot 分区重新读回 SHA256=`3c47a780c1c72d0cd6a1ad7f647daebec3f88ffd4ff662a10716f4ecf77298fe`，与刷测前逐字节一致。当前日用 boot 因而仍是原基线，`CONFIG_CAN_VCAN/SLCAN` 再次为未启用状态。

## 2026-09-20 USB_DUMMY_HCD virtual-USB 实验：禁止启用

- 为在没有 OTG/USB 串口硬件的情况下验证 `cdc_acm`，曾单独构建 test-only kernel，额外启用 `CONFIG_USB_DUMMY_HCD=y`；GitHub Actions 构建成功，artifact 保留在 `artifacts/kali/nethunter-virtual-usb-21ff0081-gh/` 仅作失败证据。
- 真机刷入后，Android 无法建立正常的物理 DWC3 USB gadget：Mac 侧 NX563J 完全不出现 ADB/普通 USB 枚举，重启 Android 也不会恢复 USB 调试授权弹窗。该配置因此在 NX563J downstream 4.4 + DWC3/Android gadget 栈上判定为 **UNSAFE / DO NOT ENABLE**。
- 恢复路径已实测：进入 fastboot 后重新执行 `fastboot oem nubia_unlock NUBIA_NX563J`，立即刷回 `work/future-test/boot-stable-before-future.img`；64 MiB boot 写入成功后 ADB 恢复。恢复后 boot SHA256 再次为 `3c47a780c1c72d0cd6a1ad7f647daebec3f88ffd4ff662a10716f4ecf77298fe`，运行内核回到 `Wed Sep 16 03:11:48 UTC 2026`，`CONFIG_USB_DUMMY_HCD`/`CAN_VCAN`/`CAN_SLCAN` 均为 not set。
- 结论：后续没有实体 OTG/USB 串口设备时，不再使用 dummy_hcd 模拟 host/gadget；USB Host/ACM 的数据面验证保持 WAITING_FOR_HARDWARE。

## 2026-09-20～21 Docker / NetHunter chroot 适配（完整 Internet E2E 已完成）

- Kali NetHunter 上游 `devices.yml` 存在正式 `Docker` feature；NX563J Ubuntu 阶段已于 2026-09-19 完成 `dockerd/run/build/exec/NAT/port mapping/cgroup/bind mount` 真机矩阵，因此当前目标是把已验证内核能力迁移到 LineageOS/NetHunter kernel，而不是新增一个非标准标签。
- 临时 Docker-test kernel 基于正式 `nethunter-22.2` / `e840cb1b`，移植已验证的 IPC namespace/mqueue 修复并合并 Docker fragment。GitHub Actions run `35510570898` 全绿；CI `Image.gz-dtb` SHA256=`9518a09be44af6512f0b36df212765a3f8767a4b5f8dd19a6feabaa3d15496f6`。最终 config 已含 `CGROUP_DEVICE/PIDS`、`PID_NS/IPC_NS/USER_NS`、`POSIX_MQUEUE`、`DEVPTS_MULTIPLE_INSTANCES`、`VETH`、`BRIDGE_NETFILTER`、`MACVLAN/IPVLAN/VXLAN` 等；并明确 `# CONFIG_USB_DUMMY_HCD is not set`。
- 以稳定 64 MiB boot dump（SHA256=`3c47a780c1c72d0cd6a1ad7f647daebec3f88ffd4ff662a10716f4ecf77298fe`）仅替换 kernel 并重新签名得到 `work/docker-test/boot-nethunter-docker-test.img`，SHA256=`1c176aa44bd88485220a792c9fc30b2c575236d30eb33232c63a138fff0e59ba`。2026-09-20 已通过 Android/Magisk root 直接写 boot 分区真机启动，运行内核时间戳为 `Sun Sep 20 12:25:13 UTC 2026`；`CGROUP_DEVICE/PIDS`、`PID_NS/IPC_NS/USER_NS`、`POSIX_MQUEUE`、`DEVPTS_MULTIPLE_INSTANCES`、`VETH`、`BRIDGE_NETFILTER`、`MEMCG_KMEM/SWAP` 均在运行态确认，且 `USB_DUMMY_HCD` 未启用。
- 用户态采用 Docker official ARM64 29.1.3 + containerd 1.7.35（避免 Kali Rolling containerd 2.x 对 4.4 的新内核依赖），安装于 Kali test-only `/usr/local/nx-docker-test/bin`。Docker daemon 真机启动成功，报告 `Storage Driver: vfs`、`Cgroup Driver: cgroupfs` / v1、aarch64、6 CPUs。
- Android `/data` 虽为 ext4 且内核有 `CONFIG_OVERLAY_FS=y`，但该 downstream 4.4 真机 dmesg 明确报 `filesystem ... not supported as upperdir`，因此 `overlay2` 不可用；harness 默认改用 `vfs`，可通过 `NX_DOCKER_STORAGE_DRIVER` 为未来内核覆盖。
- Android 全局 netns 的 legacy iptables 含 vendor `quota2` 等规则，Kali iptables 在该全局表中连创建无害测试链都会失败；Docker 因而用 Magisk BusyBox `unshare -m -n --propagation private` 同时隔离 mount + network namespace。这样 Docker 自己的 bridge/iptables 正常工作，也不修改 Android PID1 mount tree 或全局防火墙。
- `docker exec` 另发现 Android 继承的 `TMPDIR=/data/local/tmp` 会让 runc 在 Kali chroot 外生成 `runc-process*` 临时文件；harness 固定 `TMPDIR=/tmp` 后，`docker exec ... /bin/sh` 真机 PASS。
- `tools/docker/test-nethunter-docker-e2e.sh` 最终真机输出 `NX563J_NETHUNTER_DOCKER_E2E_PASS`：离线 ARM64 BusyBox image import、默认 IPC/mqueue `docker run`、`docker exec`、bind mount、64 MiB memory + cpu-shares、bridge 容器 HTTP 数据面、`-p 18080:8080` 在 Docker 私有 netns 的 loopback 发布、daemon/storage summary、停止后的 Android host mount leak 检查全部 PASS。稳定内核负对照仍按预期在 `CONFIG_CGROUP_DEVICE` 处 rc=20 退出。
- 2026-09-20 继续加入 `slirp4netns` 用户态 uplink：Kali chroot 安装 `slirp4netns 1.3.3` + `libslirp 4.9.4`，harness 新增 `uplink-start/status/stop`。slirp 进程保留在 Android host netns，只在自己的私有 mount namespace 暴露 Kali `/proc`/`/dev`，并把 Docker 私有 netns 配成 `tap0=10.0.2.100/24`、默认路由 `10.0.2.2`。真机容器从 `172.17.0.2` 经 docker0/NAT/tap0/slirp 成功访问 Android 宿主 HTTP，输出 `USERMODE_UPLINK_DATAPATH_PASS`；测试前后 Android 全局 iptables 中无新增 `DOCKER/docker0/tap0/172.17/10.0.2` 规则，输出 `ANDROID_DOCKER_FIREWALL_UNCHANGED_PASS`。2026-09-21 又启用 slirp API socket，`add_hostfwd` 将 Android loopback `127.0.0.1:18082` 映射到 Docker 私有 netns `10.0.2.100:18080`；Android 本机 curl 与 Mac 经 `adb forward tcp:18083 tcp:18082` 均实收 `NX563J_HTTP_OK`，输出 `SLIRP_HOSTFWD_ANDROID_LOOPBACK_PASS` / `SLIRP_HOSTFWD_ADB_BRIDGE_PASS`。
- 2026-09-21 已补齐真实外网验证：NX563J 连接 Mac Internet Sharing 后宿主获得 `192.168.2.8/24`。测试中 Mac 热点 DNS `192.168.2.1` 一度进入 partial-connectivity，但公网 IPv4 仍可达；同时发现 Kali chroot 遗留 resolver `213.186.33.99`。harness 因此将宿主在线判定拆为 literal public IPv4，并给 dockerd 默认显式 `--dns 1.1.1.1 --dns 8.8.8.8`（支持 `NX_DOCKER_DNS1/2` 覆盖）。容器实收 `CONTAINER_INTERNET_IPV4_PASS`、`CONTAINER_DNS_PASS`、`CONTAINER_DOMAIN_HTTP_PASS` 与 `CONTAINER_INTERNET_PASS`。随后同一完整矩阵在正式 promotion kernel 上再次 PASS，因此 Internet 与正式内核回归两个 blocker 均已关闭。
- 2026-09-21 hostfwd E2E 结束后再次通过项目既有 fastboot 恢复路径完整刷回 64 MiB `work/docker-test/boot-before-docker.img`；fastboot 报 `Sending 'boot' (65536 KB)` / `Writing 'boot' OKAY`，重启后 boot 分区 SHA256 再次为 `3c47a780c1c72d0cd6a1ad7f647daebec3f88ffd4ff662a10716f4ecf77298fe`，运行内核恢复为 `Wed Sep 16 03:11:48 UTC 2026`。
- 正式 promotion：公开内核仓库 `nethunter-22.2` commit `a180aa33` 将 IPC/mqueue 初始化修复与 Docker config 正式合并，并在 CI 加入关键 Docker Kconfig 与 `USB_DUMMY_HCD` 禁用门禁。GitHub Actions run `35544472143` SUCCESS，正式 `Image.gz-dtb` SHA256=`8f1652062fa052fff6d1f3fc2ddf9d1f1b9ed5fbd4afeec5157210bef44fe3a7`；基于稳定 boot 重打的签名测试 boot SHA256=`dce6db0c276440f338122d8e5019e6b3a5c42dff99aea6c99da34ae9efbd9970`。真机启动后 Magisk/Kali/Bluetooth/Wi-Fi/USB configfs smoke 全部正常，完整 Docker E2E 最终输出 `NX563J_NETHUNTER_DOCKER_E2E_PASS`。

## 2026-09-14 备注

- Phase 7 踩坑记录（全部写进 CAPABILITIES 矩阵 BT 行）：
  - 用 timeout 杀蓝牙扫描会把控制器留在 inquiry 态 → 后续寻呼/被发现
    全废；必须 HCI Exit_Inquiry (hcitool cmd 0x01 0x0002)。
  - 半死 ACL handle（对端掉线但 Disconnect Complete 丢失）无任何手段
    清除，只能重启。
  - hci_uart 一旦 down 再 up 必 wedge（超时 110），只能重启——
    所以绝不动 hciconfig，也不重启 bluetoothd（它退出会 down 适配器）。
  - Wi-Fi 卡死在 SCANNING 会饿死 BT 射频共存窗口 → BT 全哑；
    测 BT 前先杀 wpa_supplicant。
  - blueman-applet 占着 BlueZ agent；CLI 配对前先杀它。
- Mac (macOS 26?) 蓝牙对该设备出站寻呼本地失败：blueutil --pair 秒报
  0x02 No Connection，GUI 配对一直转圈，btmon 证实零包到达。
  设备→Mac 方向完全正常（ACL/SDP/远程名字都通）。判 Mac 蓝牙栈损坏，
  需重启 Mac 恢复。

## 2026-09-15 备注

- luckyy_5G 已不存在（用户换住处），wpa 配置已清除；之前「扫不到」
  非驱动问题。
- USB gadget 第一对（usb0↔en155, 10.42.0.1↔.32）设备→Mac 方向单通
  （ARP FAILED）；第二对（usb1↔en156, .2↔.33）双向正常。设备发起的
  连接（NFS/apt 代理）一律走 10.42.0.33。
- NFS Phase 12 真机 PASS（详见 CAPABILITIES 矩阵）。
- mixer 'PRI_MI2S_RX Audio Mixer MultiMedia1' 永远 on,off 是内核 get
  handler 只填 value[0] 的显示伪影，非 bug（RESEARCH.md 2026-09-15）。
- offmode charging 根因假说 + 验证路径成型（RESEARCH.md 2026-09-15）：
  PON_USB_CHG/CBLPWR_N 触发源默认使能，掉电瞬间线缆仍在 → PMIC 立刻
  重新上电。验证看重启后 dmesg 的 "Power-on reason"。

## 2026-09-16 备注

- **ch36 (5GHz) 注入稳定性对照**：注入 200/200 帧后设备全程无 FW assert
  （对照 2026-09-15 2.4GHz ch6 注入后 ~31s FW 自炸 ratectrl_11ac_）。
  进一步支持「2.4GHz helper STA vdev 触发 11ac 速率控制 assert」假说。
  5GHz 注入视为安全；2.4GHz 注入在对照实验前仍列为高危。
- **本次 helper vdev 150s 未自动销毁**（restore-mission.sh 正确拒绝回切，
  规则起效）。恢复路径 = 直接 sysrq 重启，重启后 con_mode=0 / wlan1
  managed，功能正常。待查：之前（9-12 inject6）vdev 是由什么路径销毁的，
  为何这次没有。
- **Mac 端嗅探器失守**：macOS 15.7.7 上 `airport en0 sniff` 已彻底失效
  （打印 deprecation 警告后直接退出，不生成 /tmp/airportSniff*.cap，
  两次复现）；Apple tcpdump 148 无 -I 监视模式标志。RF 旁证需要新方案：
  Wireless Diagnostics.app GUI Sniffer（可选信道，cap 落 /var/tmp）或
  第三方工具。Phase 2 状态不变：host-side 注入 PASS，RF 旁证
  BLOCKED_ON_SNIFFER（非手机端问题）。
- usb1 对地址已从 10.42.0.x 迁到 **10.42.1.x**（修 usb0/usb1 同在
  10.42.0.0/24 导致设备把 10.42.0.33 从 usb0 ARP 出去的路由歧义）：
  设备 usb1=10.42.1.2/24 ↔ Mac en161=10.42.1.33/24，代理恢复监听
  10.42.1.33:8080。注意 gadget 每次重绑 enNN 编号都会变。
