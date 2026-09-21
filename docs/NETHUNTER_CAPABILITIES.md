# NetHunter 能力矩阵 — NX563J (WCN3990 / qcacld-3.0, 4.4.302 downstream)

规则：**只有真机验证过的功能才能标 PASS**。每条记录带日期 / 内核 commit /
构件 SHA256 / 测试命令 / 结果 / 根因。未验证的一律标 BLOCKED 或
WAITING_FOR_HARDWARE。

## Android 平台（LineageOS 22.2 + Magisk + Kali chroot，2026-09-17 装机）

初始装机基线为 LOS 22.2-20260911-NIGHTLY-nx563j + NetHunter 内核 `a5fee84d`
（Image.gz-dtb sha256 `2038303d…`）+ Magisk 30.7 + 官方安装器 full 包；2026-09-21
正式提交/Docker 基线已升级为 `nethunter-22.2` commit `a180aa33` 的 CI artifact
（Image.gz-dtb sha256 `8f165206…e3a7`），并完成真机完整回归。Kali userspace 保持同一
2026.2 环境。详见 docs/KALI_NETHUNTER_PORT.md K5/K6 节。

| 能力 | 实测 | 结果 | 备注 |
|------|------|------|------|
| Kali chroot 运行 | 2026-09-17: `busybox chroot … bash` 内 uname=kali 4.4.302-perf+（我们的内核），Kali 2026.2，1794 包，msfconsole/aircrack-ng/wifite/bettercap/reaver 均在 | **PASS** | bootkali 由 NetHunter app 首启生成；模块 busybox 符号链坑已修（见 PORT 文档） |
| Wi-Fi 注入（5GHz） | 2026-09-17: svc wifi disable → con_mode 4 → chroot python3 inject.py wlan0 20 帧 → sent 20/20，dmesg `mon-inject: helper vdev 4 … on 5180 MHz`，无 FW assert，helper 销毁后 con_mode→0，Wi-Fi 恢复 | **PASS(host-side)** | 与 Ubuntu 侧同补丁同路径；射频证据仍待第二嗅探器；2.4GHz 勿用 |
| 蓝牙适配器 | 2026-09-17: svc bluetooth enable → state ON（"Nubia Z17"） | **PASS(点亮)** | raw HCI 深度验证见 Ubuntu 侧记录 |
| HID gadget | 2026-09-17: 枚举级——configfs hid.usb0（键盘 boot 描述符）绑定 a800000.dwc3，Mac 端实见 "HID Keyboard" VID 0x1d6b PID 0x0104 Manufacturer NetHunter，手机端 `config #1: c` configured；**按键级——mknod /dev/hidg0 后 chroot python3 hid-type.py 打 8 轮 × "NX563J HID TEST\n"（手机侧 8/8 typed 16 chars 无错误），Mac 文本框逐字实收（用户在场确认，个别丢字系用户同时编辑叠加所致）** | **PASS(主机实收)** | LOS 下须先 `setprop sys.usb.config none` 否则 UsbDeviceManager 秒抢回 UDC；/dev/hidg0 节点被 SELinux 拦 kdevtmpfs，需 mknod（NH app 正式流程会处理） |
| USB Arsenal property profiles | 2026-09-20: boot-integrated candidate rc 真实切换 `win,hid,adb` / `win,rndis,adb` / `mac,reset` / `mac,reset,adb`；Mac 分别枚举 `046d:c317` / `0525:a4a3` / `2a70:f003` / `2a70:4ee7`；RNDIS 日志出现 `RNDIS_IPA NetDev was initialized`，设备生成 `rndis0` | **PASS(主机实收)** | 修正后的 Mac RESET triggers 已端到端验证；测试 watchdog 最终使用 `mac,reset,adb` 作为可靠恢复锚点 |
| USB CD-ROM gadget | 2026-09-20: `mass_storage.0/lun.0` 设置 `cdrom=1`、`ro=1`、测试 ISO backing file；macOS `system_profiler` 实收 `File-CD Gadget`、VID/PID `0930:6545`、BSD `disk4` | **PASS(主机实收)** | 使用内核原生 configfs mass-storage CD-ROM 能力，无需额外旧式 DriveDroid patch；测试后 watchdog 恢复 `mac,reset,adb` |
| BT RFCOMM/BNEP 数据通道 | 2026-09-20: rooted Xiaomi MIX Flip 对端；双方 `BOND_STATE_BONDED`；NX RFCOMM 发 `NX563J_RFCOMM_TEST`，MIX 实收并回 `MIXFLIP_ACK:NX563J_RFCOMM_TEST`，两端 `CLIENT_PASS/SERVER_PASS`；PAN/BNEP 达 `STATE_CONNECTED`，双方 `bt-pan UP,LOWER_UP`，链路字节/包计数互为 TX/RX，临时测试 IP 下 MIX→NX ping 3/3 0% loss | **PASS(双机实收)** | NX→MIX ICMP 被 Android tether/firewall 输入策略过滤，但 ARP `REACHABLE`、镜像 link counters 和反向 ICMP 已证明 BNEP 数据链；官方 feature 使用 `BT_RFCOMM`，无单独 BNEP 标签 |
| Wi-Fi STA 日常上网（回归） | 2026-09-17: 自研内核下连接 Mac 共享热点，192.168.2.6/24，signal -33dBm，tx 866.7Mbit/s VHT-MCS9 80MHz 2SS，网关 ping 0% 丢包，generate_204=204 | **PASS** | 换内核不影响日用 Wi-Fi——MR 关键回归项 |
| Magisk root | `su -c id` → uid=0（magisk 域） | **PASS** | 授权弹窗默认 10s 超时，需在 Superuser 页手动允许 |
| Docker Engine runtime | 2026-09-21: 正式 `nethunter-22.2` promotion kernel `a180aa33`（CI run `35544472143`）+ Docker 29.1.3/containerd 1.7.35 完成完整真机 E2E；`run`/mqueue/exec/bind/cgroup/bridge/private-netns publish/cleanup、slirp4netns uplink、Android/Mac hostfwd、公网 IPv4、DNS、域名 HTTP 全部 PASS | **PASS(formal kernel, full runtime + uplink + hostfwd + Internet)** | 正式 Image SHA256=`8f165206…e3a7`，`USB_DUMMY_HCD` 明确关闭；Android `/data` 的 downstream 4.4 overlayfs 不支持 upperdir，因此使用 `vfs`。dockerd 默认显式 DNS `1.1.1.1` + `8.8.8.8`（可覆盖）。`Docker` 已进入首版官方 feature |

## Linux 用户态平台（Ubuntu，K5 前的历史验证）

| 能力 | 内核配置 | 驱动/机制 | 用户态 | 实测 | 结果 | 备注 |
|------|----------|-----------|--------|------|------|------|
| Wi-Fi 监听模式 (RX) | 内建 qcacld-3.0 v5.1.1.77V | con_mode=4 全局监听, wlan_mon_drv_ops | tools/wifi-mon/moncap.py (AF_PACKET) | 2026-09-10: 15s 318 帧, 317 合法 radiotap, beacon/probe/data/deauth, 2.4G/5G 信道可切 | **PASS** | con_mode sysfs 切换, 无需重启 |
| Wi-Fi 帧注入 (TX) | 同上 + patches/downstream/0009 v4 | hdd_mon_tx → WMA 队列 → 隐藏 STA 辅助 vdev → WMI_MGMT_TX_SEND | tools/wifi-mon/inject.py | 2026-09-12: host 侧链路全通(日志见下), **射频证据缺第二嗅探器** | **BLOCKED(待双机验证)** | 机制移植自 Loukious (Kali 2026.1, sm8150 8f0698bf); 固件拒绝 MONITOR vdev 的 mgmt TX, 必须走辅助 vdev; 监控 netdev 需显式 carrier+队列启动(RESEARCH.md 2026-09-12) |
| monitor→mission 恢复 | 同上 + patches/downstream/0009 v6 (teardown 竞态修复) | __con_mode_handler + wma_mon_inject_cleanup/rearm (stopping 标志) | — | 2026-09-12: 两个完整 mission→monitor→注入→mission 循环, helper vdev 干净销毁/重建, STA 重关联 + DHCP + HTTP 204, dmesg 零 assert | **PASS** | boot-ubuntu-inject6.img (1787d232…, CI 34663038475); 根因: cleanup 期间 inject_frame 重 arm work → 孤儿 vdev FW assert; 修复见 RESEARCH.md 2026-09-12 |
| USB HID 键盘/鼠标/复合 | USB_CONFIGFS_F_HID=y (内建, 4.4.302) | configfs gadget: acm+ecm+ncm+hid.usb0/hid.usb1 | tools/usb-hid/hid-gadget.sh + hid-type.py | 2026-09-14: 键盘主机实收 "NX563J HID TEST"/"kbd ok" 逐字正确; 鼠标 report 实收指针移动; macOS hidutil 确认键盘(usage 6)+鼠标(usage 2)两接口 | **PASS** | Phase 4; 鼠标必须用经典 3 字节无 wheel 描述符 (subclass=0/protocol=0/report_length=3)——4 字节 wheel 版和 boot protocol 在 macOS 枚举正常但指针不动; macOS 指针加速抑制慢速小步, 演示用快速连发 |
| USB CD-ROM gadget | USB_CONFIGFS_MASS_STORAGE=y | configfs `mass_storage.0/lun.0`，`cdrom=1` + 只读 ISO | USB Arsenal + macOS host | 2026-09-20: NX563J 挂载测试 ISO 后，Mac 实际枚举为 `File-CD Gadget`、VID/PID `0930:6545`、BSD `disk4`；测试结束 watchdog 自动恢复 `mac,reset,adb` | **PASS** | 已进入首版官方 `CDROM` feature；无需 DriveDroid 旧式内核补丁 |
| 外置 USB Wi-Fi (ATH9K_HTC/RTL8XXXU) | config/downstream-nethunter-wifi.fragment + 补丁 0010-0012 | 内核侧: mac80211+ath9k_htc+rtl8xxxu 已编译内建 | — | 2026-09-14: CI 34852050514 构建成功; 真机刷入 (work/boot-nethunter-p5.img, SHA256 d6758746…) 启动正常, /sys/module/{ath9k_htc,rtl8xxxu,mac80211} 已注册, 回归 (BT/音频/Wi-Fi/gadget) 正常 | 🟡 内核侧 PASS; 插卡实测 WAITING_FOR_HARDWARE | Phase 5; 需 OTG + 对应网卡; 补丁修复: cfg80211 枚举回植缺口/htc_* 与 qcacld 撞名/clang -Werror; 固件需双 root 投放 (见 fragment 注释) |
| USB Host/OTG 稳定性 | — | — | — | 未开始 | BLOCKED | Phase 6 |
| BT raw HCI 套接字 | BT_HCIUART_QCA=y (内建) | hci_qca, AF_BLUETOOTH/SOCK_RAW | tools/bt/raw-hci-test.py | 2026-09-14: Read_Local_Version status=0 mfr=29(QCA) + Read_BD_ADDR 00:A0:C6:* 均实收 Command Complete, 不依赖 bluetoothd | **PASS** | Phase 7; 注意本 4.4 内核 HCI_FILTER optname=2 (SOL_HCI=0) |
| BT RFCOMM/BNEP 数据通道 | BT_RFCOMM/BT_BNEP=y | Android Bluetooth framework + hci_qca | 双机 RFCOMM/PAN 临时测试 harness | 2026-09-20: 以 rooted Xiaomi MIX Flip 为真实对端，双方 bond 到 `BOND_STATE_BONDED`；RFCOMM NX→MIX 实发 `NX563J_RFCOMM_TEST`，对端实收并回 `MIXFLIP_ACK:NX563J_RFCOMM_TEST`，两端 `CLIENT_PASS/SERVER_PASS`；PAN/BNEP 达 `STATE_CONNECTED`，双方 `bt-pan UP,LOWER_UP`，镜像 TX/RX 计数，MIX→NX 绑定接口 ping 3/3 0% loss | **PASS** | `BT_RFCOMM` 已进入首版官方 feature；BNEP 作为附加证据，无独立 upstream feature 标签；临时 privileged 测试 APK/module 已清理 |
| USB BT dongle | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 8 |
| SocketCAN | base: CAN_RAW/CAN_BCM/GS_USB=y；future: CAN_VCAN/CAN_SLCAN=y | PF_CAN/CAN_RAW + `vcan` + N_SLCAN(17) | `tools/can/vcan-smoke.sh` + `tools/can/slcan-pty-smoke.py` | 2026-09-20 GitHub Actions run `35484288726` 构建 future kernel（Image SHA256 `f18ab1ee…`）并真机启动；VCAN `0x563/NX563J` CAN_RAW 发→收闭环 PASS；SLCAN 用 PTY 模拟 LAWICEL 适配器完成双向闭环：CAN→ASCII `t56364E583536334A`，ASCII→CAN 实收 `0x456/Z17`；`slcan` ldisc=17。CH341/CP210X/FTDI/PL2303/RNDIS-host 同核注册成功 | ✅ CAN core + VCAN + SLCAN 软件闭环 PASS；gs_usb/真实串口仍 WAITING_FOR_HARDWARE | future 能力不进入首版官方 `CAN` feature，直到真实 CAN adapter 验证；`config/downstream-nethunter-future.fragment` |
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
