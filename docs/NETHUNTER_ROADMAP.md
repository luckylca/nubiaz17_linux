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
| 7 | BT RFCOMM/BNEP/raw HCI | 🟡 raw HCI **PASS**; RFCOMM/BNEP BLOCKED(主机侧) | 2026-09-14; Mac 蓝牙出站寻呼损坏, 待 Mac 重启或换 Android 对端 |
| 8 | USB BT  dongle | ⏳ 驱动已预置(BT_HCIBTUSB) | WAITING_FOR_HARDWARE |
| 9 | SocketCAN (gs_usb) | ⏳ 驱动已预置 | WAITING_FOR_HARDWARE |
| 10 | SDR (RTL-SDR) | ⏳ 纯用户态, 依赖 Phase 6 | WAITING_FOR_HARDWARE |
| 11 | USB 以太网 (RTL815x) | ⏳ defconfig 已 =y | WAITING_FOR_HARDWARE |
| 12 | NFS | ✅ **PASS** | 2026-09-15 实机挂载 Mac nfsd 双向读写验证; 走 usb1/en156 第二对 (usb0 对设备→Mac 单通) |
| 13 | config 片段整合 | ✅ daily fragment 机制 | CI 每次只 merge 一个 fragment |
| 14 | 回归测试 | 🟡 持续 | 每次新内核刷入后回归 BT/音频/HID |
| 15 | 能力矩阵定稿 | 🟡 持续维护 | docs/NETHUNTER_CAPABILITIES.md |

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
