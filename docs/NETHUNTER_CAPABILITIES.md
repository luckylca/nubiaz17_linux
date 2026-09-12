# NetHunter 能力矩阵 — NX563J (WCN3990 / qcacld-3.0, 4.4.302 downstream)

规则：**只有真机验证过的功能才能标 PASS**。每条记录带日期 / 内核 commit /
构件 SHA256 / 测试命令 / 结果 / 根因。未验证的一律标 BLOCKED 或
WAITING_FOR_HARDWARE。

| 能力 | 内核配置 | 驱动/机制 | 用户态 | 实测 | 结果 | 备注 |
|------|----------|-----------|--------|------|------|------|
| Wi-Fi 监听模式 (RX) | 内建 qcacld-3.0 v5.1.1.77V | con_mode=4 全局监听, wlan_mon_drv_ops | tools/wifi-mon/moncap.py (AF_PACKET) | 2026-09-10: 15s 318 帧, 317 合法 radiotap, beacon/probe/data/deauth, 2.4G/5G 信道可切 | **PASS** | con_mode sysfs 切换, 无需重启 |
| Wi-Fi 帧注入 (TX) | 同上 + patches/downstream/0009 v4 | hdd_mon_tx → WMA 队列 → 隐藏 STA 辅助 vdev → WMI_MGMT_TX_SEND | tools/wifi-mon/inject.py | 2026-09-12: host 侧链路全通(日志见下), **射频证据缺第二嗅探器** | **BLOCKED(待双机验证)** | 机制移植自 Loukious (Kali 2026.1, sm8150 8f0698bf); 固件拒绝 MONITOR vdev 的 mgmt TX, 必须走辅助 vdev; 监控 netdev 需显式 carrier+队列启动(RESEARCH.md 2026-09-12) |
| monitor→mission 恢复 | 同上 | __con_mode_handler | — | 已知偶发 EAGAIN (cds_wait_for_external_threads_completion) | **BLOCKED(已知 bug)** | Phase 3 处理 |
| USB HID 键盘/鼠标/复合 | 待加 config fragment | configfs gadget | tools/usb-hid/ | 未开始 | BLOCKED | Phase 4 |
| 外置 USB Wi-Fi (ATH9K_HTC/RTL88XXAU/RTL8188EUS) | config/downstream-nethunter-wifi.fragment 待建 | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 5, 需要 OTG + 对应网卡 |
| USB Host/OTG 稳定性 | — | — | — | 未开始 | BLOCKED | Phase 6 |
| BT RFCOMM/BNEP/raw HCI | — | hci_qca | — | 未开始 | BLOCKED | Phase 7 |
| USB BT dongle | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 8 |
| SocketCAN | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 9 |
| SDR | — | — | — | 未开始 | WAITING_FOR_HARDWARE | Phase 10 |
| USB 以太网 | — | — | — | 未开始 | BLOCKED | Phase 11 |
| NFS | — | — | — | 未开始 | BLOCKED | Phase 12 |

## 验证纪律

- 注入类能力必须双机验证: 注入方 + 独立嗅探方, 嗅探方实收才算 PASS。
- HID 类必须有真实主机收到 report 才算 PASS。
- 所有测试只在本机/自有实验网络/授权环境进行; HID 默认 payload 只打
  "NX563J HID TEST" 字样。
- 路由器/他人网络里不做 deauth 等攻击性动作, 能力证明用 probe-req /
  自建 AP 环境完成。
