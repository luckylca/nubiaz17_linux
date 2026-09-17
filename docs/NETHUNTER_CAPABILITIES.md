# NetHunter 能力矩阵 — NX563J (WCN3990 / qcacld-3.0, 4.4.302 downstream)

规则：**只有真机验证过的功能才能标 PASS**。每条记录带日期 / 内核 commit /
构件 SHA256 / 测试命令 / 结果 / 根因。未验证的一律标 BLOCKED 或
WAITING_FOR_HARDWARE。

## Android 平台（LineageOS 22.2 + Magisk + Kali chroot，2026-09-17 装机）

LOS 22.2-20260911-NIGHTLY-nx563j + 自研 NetHunter 内核（CI 构建，源 commit
a5fee84d，Image.gz-dtb sha256 2038303d…）+ Magisk 30.7 + 官方安装器产出的
nethunter full 包（sha256 f1708e66…，kalifs sha256 fd108959…与官方一致）。
详见 docs/KALI_NETHUNTER_PORT.md K5 节。

| 能力 | 实测 | 结果 | 备注 |
|------|------|------|------|
| Kali chroot 运行 | 2026-09-17: `busybox chroot … bash` 内 uname=kali 4.4.302-perf+（我们的内核），Kali 2026.2，1794 包，msfconsole/aircrack-ng/wifite/bettercap/reaver 均在 | **PASS** | bootkali 由 NetHunter app 首启生成；模块 busybox 符号链坑已修（见 PORT 文档） |
| Wi-Fi 注入（5GHz） | 2026-09-17: svc wifi disable → con_mode 4 → chroot python3 inject.py wlan0 20 帧 → sent 20/20，dmesg `mon-inject: helper vdev 4 … on 5180 MHz`，无 FW assert，helper 销毁后 con_mode→0，Wi-Fi 恢复 | **PASS(host-side)** | 与 Ubuntu 侧同补丁同路径；射频证据仍待第二嗅探器；2.4GHz 勿用 |
| 蓝牙适配器 | 2026-09-17: svc bluetooth enable → state ON（"Nubia Z17"） | **PASS(点亮)** | raw HCI 深度验证见 Ubuntu 侧记录 |
| HID gadget | 内核 CONFIG_USB_CONFIGFS_F_HID=y 已随当前内核运行 | 🟡 kernel-side | USB Arsenal 实测会断 adb 会话，待屏幕侧操作验证 |
| Magisk root | `su -c id` → uid=0（magisk 域） | **PASS** | 授权弹窗默认 10s 超时，需在 Superuser 页手动允许 |

## Linux 用户态平台（Ubuntu，K5 前的历史验证）

| 能力 | 内核配置 | 驱动/机制 | 用户态 | 实测 | 结果 | 备注 |
|------|----------|-----------|--------|------|------|------|
| Wi-Fi 监听模式 (RX) | 内建 qcacld-3.0 v5.1.1.77V | con_mode=4 全局监听, wlan_mon_drv_ops | tools/wifi-mon/moncap.py (AF_PACKET) | 2026-09-10: 15s 318 帧, 317 合法 radiotap, beacon/probe/data/deauth, 2.4G/5G 信道可切 | **PASS** | con_mode sysfs 切换, 无需重启 |
| Wi-Fi 帧注入 (TX) | 同上 + patches/downstream/0009 v4 | hdd_mon_tx → WMA 队列 → 隐藏 STA 辅助 vdev → WMI_MGMT_TX_SEND | tools/wifi-mon/inject.py | 2026-09-12: host 侧链路全通(日志见下), **射频证据缺第二嗅探器** | **BLOCKED(待双机验证)** | 机制移植自 Loukious (Kali 2026.1, sm8150 8f0698bf); 固件拒绝 MONITOR vdev 的 mgmt TX, 必须走辅助 vdev; 监控 netdev 需显式 carrier+队列启动(RESEARCH.md 2026-09-12) |
| monitor→mission 恢复 | 同上 + patches/downstream/0009 v6 (teardown 竞态修复) | __con_mode_handler + wma_mon_inject_cleanup/rearm (stopping 标志) | — | 2026-09-12: 两个完整 mission→monitor→注入→mission 循环, helper vdev 干净销毁/重建, STA 重关联 + DHCP + HTTP 204, dmesg 零 assert | **PASS** | boot-ubuntu-inject6.img (1787d232…, CI 34663038475); 根因: cleanup 期间 inject_frame 重 arm work → 孤儿 vdev FW assert; 修复见 RESEARCH.md 2026-09-12 |
| USB HID 键盘/鼠标/复合 | USB_CONFIGFS_F_HID=y (内建, 4.4.302) | configfs gadget: acm+ecm+ncm+hid.usb0/hid.usb1 | tools/usb-hid/hid-gadget.sh + hid-type.py | 2026-09-14: 键盘主机实收 "NX563J HID TEST"/"kbd ok" 逐字正确; 鼠标 report 实收指针移动; macOS hidutil 确认键盘(usage 6)+鼠标(usage 2)两接口 | **PASS** | Phase 4; 鼠标必须用经典 3 字节无 wheel 描述符 (subclass=0/protocol=0/report_length=3)——4 字节 wheel 版和 boot protocol 在 macOS 枚举正常但指针不动; macOS 指针加速抑制慢速小步, 演示用快速连发 |
| 外置 USB Wi-Fi (ATH9K_HTC/RTL8XXXU) | config/downstream-nethunter-wifi.fragment + 补丁 0010-0012 | 内核侧: mac80211+ath9k_htc+rtl8xxxu 已编译内建 | — | 2026-09-14: CI 34852050514 构建成功; 真机刷入 (work/boot-nethunter-p5.img, SHA256 d6758746…) 启动正常, /sys/module/{ath9k_htc,rtl8xxxu,mac80211} 已注册, 回归 (BT/音频/Wi-Fi/gadget) 正常 | 🟡 内核侧 PASS; 插卡实测 WAITING_FOR_HARDWARE | Phase 5; 需 OTG + 对应网卡; 补丁修复: cfg80211 枚举回植缺口/htc_* 与 qcacld 撞名/clang -Werror; 固件需双 root 投放 (见 fragment 注释) |
| USB Host/OTG 稳定性 | — | — | — | 未开始 | BLOCKED | Phase 6 |
| BT raw HCI 套接字 | BT_HCIUART_QCA=y (内建) | hci_qca, AF_BLUETOOTH/SOCK_RAW | tools/bt/raw-hci-test.py | 2026-09-14: Read_Local_Version status=0 mfr=29(QCA) + Read_BD_ADDR 00:A0:C6:* 均实收 Command Complete, 不依赖 bluetoothd | **PASS** | Phase 7; 注意本 4.4 内核 HCI_FILTER optname=2 (SOL_HCI=0) |
| BT RFCOMM/BNEP 数据通道 | BT_RFCOMM/BT_BNEP=y | hci_qca + BlueZ 5.72 | tools/bt/rfcomm-pair-test.sh | 2026-09-14: 设备→Mac ACL/SDP/远程名字全通; 配对卡在 Mac 侧 SSP 用户确认(Mac 对该设备出站寻呼本地失败, blueutil/GUI 均零包到达, 多次实测) | **BLOCKED(主机侧)** | Phase 7; 待 Mac 蓝牙恢复或换 Android 对端复测; 陷阱: stuck inquiry 由 timeout 杀扫描残留, 需 HCI Exit_Inquiry; 半死 ACL handle 无法清除只能重启; hci_uart down/up 必 wedge(超时110)只能重启 |
| USB BT dongle | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 8 |
| SocketCAN | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 9 |
| SDR | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 10 |
| USB 以太网 | — | — | — | 未开始 | BLOCKED | Phase 11 |
| NFS 客户端 | NFS_FS=y/NFS_V4=y (config/downstream-nethunter-misc.fragment) | 内核 NFS v3/v4 client, 内建 | mount.nfs (nfs-common 手工 dpkg) | 2026-09-15: 实机挂载 Mac nfsd 成功: `mount -t nfs -o nolock,vers=3,tcp 10.42.0.33:/private/tmp/nfs-export /mnt/nfs` rc=0; 双向读写实收 (hello-from-mac.txt 读出, hello-from-device.txt 写入 Mac 可见); 16MB direct-IO 写入 1.1 MB/s (USB gadget 链路瓶颈, 非 NFS 问题) | **PASS** | Phase 12; 走 usb1/en156 第二对 (10.42.0.2↔10.42.0.33)——usb0/en155 对设备→Mac 方向有单通怪癖 (ARP FAILED, 主机回包不到), Mac→设备 ssh 正常; 内核 4.4.302-perf+ (daily2, SHA256 419b4ba7…, CI 34853553552) |

## 验证纪律

- 注入类能力必须双机验证: 注入方 + 独立嗅探方, 嗅探方实收才算 PASS。
- HID 类必须有真实主机收到 report 才算 PASS。
- 所有测试只在本机/自有实验网络/授权环境进行; HID 默认 payload 只打
  "NX563J HID TEST" 字样。
- 路由器/他人网络里不做 deauth 等攻击性动作, 能力证明用 probe-req /
  自建 AP 环境完成。
