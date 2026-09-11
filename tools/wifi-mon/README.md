# Wi-Fi 监听模式（qcacld-3.0 / WCN3990）— 已验证可行

2026-09-10 在 NX563J（下游内核 4.4.302-perf+，qcacld-3.0 v5.1.1.77V 内建驱动）实测通过：
15 秒抓到 318 帧、317 帧带合法 radiotap 头，beacon / probe / data / deauth 齐全，
2.4GHz/5GHz 信道均可切换。

## 关键事实

- 驱动 **内建**（/proc/modules 为空，CONFIG_MODULES 关闭），不能 rmmod/modprobe。
- nl80211 路径无效：`iw dev wlan0 set type monitor` 返回 -22（hdd 的
  change_virtual_intf 不支持），即使 `iw phy` 宣称支持 monitor。
- 正确入口是驱动内置的 **con_mode 运行时切换器**：
  `/sys/module/wlan/parameters/con_mode`，枚举见
  `qca-wifi-host-cmn/qdf/inc/qdf_types.h`：`MISSION=0, MONITOR=4, FTM=5`。
  写 sysfs 会触发 `__con_mode_handler()`：停模块→清理→按新模式重启栈，
  **不用重启手机**。

## 切到监听模式

```sh
pkill wpa_supplicant; pkill dhclient     # 断开 STA（ssh 走 usb0，不受影响）
ip link set wlan0 down
echo 4 > /sys/module/wlan/parameters/con_mode
sleep 4
iw dev          # wlan0 type monitor
ip link set wlan0 up
iw dev wlan0 set channel 36      # 或 iwpriv wlan0 setMonChan 6 0（2.4G）
python3 /root/moncap.py wlan0 15 # 抓包验证（radiotap + 帧类型直方图）
```

## 切回正常模式

**⚠️ 2026-09-11 更新：monitor→mission 运行时切换当前不可靠（Phase 3 目标）。**
一次注入测试后 `echo 0` 先 EAGAIN、约 60 秒内整机挂死（usb0 ping 都死，
无看门狗复位）。在 Phase 3 修复前，**监听/注入测试做完直接重启恢复**
（`/root/reboot-bl` 进 fastboot 或 `echo b > /proc/sysrq-trigger`），
不要运行时切回。

```sh
ip link set wlan0 down
echo 0 > /sys/module/wlan/parameters/con_mode
# 若返回 "Resource temporarily unavailable"（EAGAIN）：有外部线程还在驱动里
# （cds_wait_for_external_threads_completion 失败）。不要再重试，直接重启。
```

## 帧注入（patch 0009-qcacld-monitor-injection，移植自 Loukious / Kali 2026.1）

机制：监听 netdev 增加 `ndo_start_xmit = hdd_mon_tx`（剥 radiotap → 原始
802.11 帧 → WMA 队列 → 工作队列提交）。固件的 mgmt-TX 处理**拒绝 MONITOR
vdev**（落到 beacon-only 路径直接丢弃），因此驱动先创建一个隐藏的
**STA 类型辅助 vdev**（VDEV_CREATE→VDEV_START→PEER_CREATE 自 peer，故意不做
VDEV_UP——STA vdev_up 在没有 BSS peer 时会 FW assert），再用
`WMI_MGMT_TX_SEND_CMDID` 以辅助 vdev 名义把帧发出去。辅助 vdev 在监听
vdev 拆除前销毁（`__hdd_stop` / `hdd_stop_present_mode`），顺序
PEER_DELETE→VDEV_STOP→VDEV_DELETE，每步间隔 100ms，避免固件
dispatch_wlan_pdev_cmds assert。

注入测试（host 侧）：

```sh
# 已在监听模式、信道已设好（例如 channel 36）
ip link set wlan0 up
python3 /root/inject.py wlan0 10 100
# 期望输出 sent 10/10；dmesg 出现：
#   "mon-inject: helper vdev N (STA, mac ...) on 5180 MHz for monitor vdev M"
#   "mon-inject: first frame submitted, desc_id=... "
```

**PASS 标准（未达标前不许标记完成）**：第二台独立监听设备在同一信道抓到
SSID=`NX563J-INJ-TEST`、SA=`02:4e:58:35:36:33` 的 probe request。
host 侧 sent 10/10 只说明驱动收下了帧，不证明空口发出。

若 dmesg 出现 "mon-inject: WMI mgmt TX failed" 或 drop 计数持续上涨，
说明本固件（WCN3990 ROM 固件）不走这条路径——查 `tx_fail/tx_drop` 计数。

## 已知坑

- 写非法值（如 2）会被 is_con_mode_valid() 拒掉（-EINVAL），但
  param_set_int 已先把变量改掉——cat 出来的值不代表真实模式，真实模式以
  `iw dev` 的 type 为准。
- EAGAIN 时连发重试没用，先找出占用驱动的进程。
- 监听模式下 wakelock 已自动获取（monitor_mode_wakelock），不会因休眠丢帧。
- moncap.py 用 AF_PACKET 原始终端即可抓 radiotap 帧，无需 tcpdump。
