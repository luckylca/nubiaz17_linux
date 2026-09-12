# Ubuntu 基础功能审计 — 2026-09-11（内核 4.4.302-perf+ / Ubuntu 24.04.4）

触发：用户反馈「关机没用」+「待机发烫」+「看看还有什么基础功能没完善」。
逐条记录：实测命令 / 结果 / 根因 / 处置。

## 已修复

| 功能 | 实测 | 根因 | 处置 |
|------|------|------|------|
| 关机/重启 | `poweroff`/`reboot` 完全无反应（uptime 不变） | `/usr/sbin/{reboot,poweroff,halt,shutdown}` 全部是指向 systemctl 的符号链接，而本 rootfs PID1 是 `/bin/sh /init`、没有 systemd 运行时，systemctl 拒绝执行 → 静默无效 | `tools/powerctl/`：351 字节静态 ELF 直接调 `reboot(2)`；`install_powerctl.sh` 把四个命令换成 sync+exec 包装。重启已实测通过（uptime 归零）；poweroff 走同一系统调用路径，实机断电测试待用户在场（需按电源键开机） |
| 待机发热 | `cnd`（高通 connectivity daemon）从开机起 100% 占一个核（32 分钟 uptime 吃掉 34 分钟 CPU），纯用户态死循环（93 次自愿上下文切换），mission/monitor 模式都一样；pm8998 47-48C | cnd 是 Android 并发管理守护，Ubuntu 下 wpa_supplicant 直谈 nl80211，没有任何消费者 | 杀死后 Wi-Fi 连接无损、CPU 立即闲下来，pm8998 47→42C（4 分钟内继续回落）。`wifi-bringup4.sh` 已移除 `kd cnd` |
| 电池桌面指示 | sysfs 有数据（98%）但桌面无电量 | 没有 system D-Bus → upowerd 永不启动 | `rc.boot.ubuntu` 启动 `dbus-daemon --system` + `/usr/libexec/upowerd`；实测 `upower -i` 正常返回 |
| 时间/RTC | 系统时间靠 boot 时一次性 `ntpdate ntp.aliyun.com`；无守护持续校时；RTC 停在 1970 且 rootfs 无 hwclock | 只装了一次性校时 | `wifi-bringup4.sh` 在 ntpdate 成功后启动 `chronyd`（`rtcsync` 顺带维护 RTC）；时区设为 Asia/Shanghai |

## 已知差距（未修，建档）

| 功能 | 实测 | 根因 | 状态 |
|------|------|------|------|
| 音频 | `aplay -l` 无声卡；内核 SND_SOC_MSM8998/WCD934X/tas2555 配置齐全、codec 已 probe | ADSP 从未启动：`subsys-pil-tz 17300000.qcom,lpass: invalid resource / Failed to iomap base register`（DT 资源问题）→ Q6 音频不可用 → 声卡永不注册。固件 `/vendor/firmware_mnt/image/adsp.*` 在位 | 任务 #22，独立子项目（对比 LineageOS DT 修 lpass 资源） |
| 深度 CPU 怠速 | cpuidle 只有 C0(wfi) 在用；C1(ret)/C2(pc) usage=0（未禁用） | msm_idle 的深层状态需要 RPM 通信；Ubuntu 流程不起 modem/RPM → 进不去 | 记录在案，不作快速修复（乱进可能挂死） |
| 挂起 suspend | `/sys/power/state` = freeze mem，未实测 | 唤醒源/显示恢复未验证，失败需物理按键救回 | 待用户在场再测 |
| 蓝牙 | hci0 未起 | hciattach-qca 工具在仓库，属 NetHunter Phase 7 | 任务 #17 |
| 背光 | sysfs 可调（128/255），桌面滑块未验证 | — | 后续在桌面任务里顺手验证 |

## 负载注记

`load average ~3.5` 但 CPU 很闲：3 个 D 态内核线程（`mdss_dsi_event`、`mdss_fb0`、`kworker/u16:1`）拉高计数，累计 CPU 时间 0:00，不是功耗问题。

## 2026-09-12 关机链路收官 + UI 缩放再平衡

### 应用关机（LXQt Leave 菜单）— 已修
- 根因 1：lxqt.conf 的 poweroff_command 等键在 LXQt 1.4 是**死配置**，
  liblxqt 里只有 lock_command；leave 只走 logind/ConsoleKit 系统总线。
- 根因 2：powerctl 关机本身正常，但**插着 USB 时 PMIC 把 VBUS 当开机
  触发**，关机后立刻自动重启——用户视角就是"关机没用"。拔线关机实测
  真关（2026-09-12 用户在场验证）。
- 修复：tools/desktop/fake-logind.py（python3-dbus，系统总线上实现
  org.freedesktop.login1.Manager 的 Can*/PowerOff/Reboot → powerctl），
  策略文件 org.freedesktop.login1.conf → /etc/dbus-1/system.d/，
  rc.boot.ubuntu 自启动。lxqt-leave --shutdown 实测触发断电。
- 注意：插着 USB 点关机 = 关机后自动重启（PMIC 行为，非 bug）；
  想真关请拔线后关机。

### UI 缩放：4.5x → 2.25x
- 用户反馈"文字太大、图标太小"：Xft.dpi 432 把文字放大 4.5 倍，图标
  固定 96px 不随 dpi——比例崩坏。
- 改为 Xft.dpi 216（文字减半），iconSize 96 不变，panelSize 160→128，
  taskbar buttonWidth 300→240。
- 顺带修复：desktop-stop.sh 的 pkill 模式还是 LXDE/MATE 时代的
  （mate-session/lxsession），根本杀不掉 lxqt-session——之前的"重启
  桌面不生效"全是它。已加 lxqt-session。
- 顺带清理：/tmp/.X*-lock 积攒 43 个（startx 因此一路选到 :42），
  重启前清理后回到 :0。注释里不能有双引号（xrdb 过 cpp）。
