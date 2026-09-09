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

```sh
ip link set wlan0 down
echo 0 > /sys/module/wlan/parameters/con_mode
# 若返回 "Resource temporarily unavailable"（EAGAIN）：有外部线程还在驱动里
# （cds_wait_for_external_threads_completion 失败）。等几秒、确认没有进程
# 在碰 wlan（wpa_supplicant / 抓包 socket / iwpriv），再重试。
# 然后重新执行 wifi-bringup4.sh 恢复 STA 连接。
```

## 已知坑

- 写非法值（如 2）会被 is_con_mode_valid() 拒掉（-EINVAL），但
  param_set_int 已先把变量改掉——cat 出来的值不代表真实模式，真实模式以
  `iw dev` 的 type 为准。
- EAGAIN 时连发重试没用，先找出占用驱动的进程。
- 监听模式下 wakelock 已自动获取（monitor_mode_wakelock），不会因休眠丢帧。
- moncap.py 用 AF_PACKET 原始终端即可抓 radiotap 帧，无需 tcpdump。
