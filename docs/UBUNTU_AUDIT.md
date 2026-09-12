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

## 2026-09-12 桌面 UX 大修（第二轮反馈）

### 抓屏自验管线（我的眼睛）
- xwd -root | xwdtopnm | pnmtopng → scp 回 Mac。之后所有桌面改动
  都以抓屏为验收标准。前提：X 固定在 :0（desktop.sh 已清锁并
  startx -- :0）+ xinitrc 里 xhost +local:（本机免 cookie）。

### 屏幕键盘：onboard 弃用，matchbox-keyboard 上岗
- onboard 1.4.1 在我们的触摸栈上必崩：osk.so 监听 XI2 raw 事件，
  uinput 触摸克隆的事件一来就 SIGSEGV（gdb 实锤 PyObject_Malloc in
  osk.so ← gdk event）。用户点一下键盘就消失 = 段错误。已 purge。
- matchbox-keyboard 只发 XTest 不听 XI2，稳。自身定位 bug：以为屏是
  1080 竖屏，窗口落在 (1,910) 底部 260px 在屏外——这就是"下半部分
  被挡住"。修复：kbd-toggle.sh 启动后 wmctrl 钉到 (420,520)。
- 实测打字：qterminal 里 xdotool 点击键盘 h/i/space/q/d 全部上屏。
- 面板快速启动第三个图标已换成键盘开关（kbd-toggle.desktop）。

### Wi-Fi GUI：wpa_gui（wpagui 包）
- wpa_supplicant.conf 本就带 ctrl_interface=/run/wpa_supplicant +
  update_config=1，wpa_gui 直接可用：Scan 选网 → 输密码（用屏幕
  键盘）→ 保存。已抓屏验证状态页（Completed/192.168.1.186）。

### 蓝牙 GUI：blueman
- blueman-manager 报错 "BlueZ daemon is not running" → 追出大坑：
  当前 v6 注入内核的 CI 片段 downstream-usb-diag.fragment 没带
  CONFIG_BT_HCIUART（/proc/tty/ldiscs 只有 n_tty/ppp，hciattach
  全部 TIOCSETD N_HCI EINVAL）。repo 里其实早有
  downstream-usb-diag-bt.fragment（含 HCIUART/H4/QCA），但生产镜像
  一直用无 BT 片段。v7 已用 BT 片段触发 CI（run 34694688501）。

### v7 内核（usb-diag-bt 片段）：蓝牙回来了 — 2026-09-12
- CI 34694688501（downstream-usb-diag-bt.fragment），boot 分区截断哈希
  679822e7…，/proc/tty/ldiscs 出现 n_hci，注入符号 13 个完好。
- 本次启动 supervisor attach 第一次就成功（之前的 EINVAL 纯粹是缺
  ldisc）。hci0 UP RUNNING（BD 00:A0:C6:DF:55:E4）。
- blueman-manager 实测：搜索进度条 + HCI 流量计数都在动，托盘图标
  正常。用户连接蓝牙路径：托盘蓝牙图标 / Bluetooth Devices → Search。
- 注意：downstream-usb-diag-bt 才是生产片段；无 BT 的
  downstream-usb-diag.fragment 以后只用于纯 diag 调试镜像。

### 插电关机变重启（task #24）调查结论
- abl 分区（4MB EFI 引导器）strings 无 charger/offmode/poweroff 字样：
  本机没有 LK 式 offmode charging 模式，RESTART2 "charger" 无目标可跳。
- 自动重启的机理：PMIC PON 的 charger-trigger 在关机后仍武装，VBUS
  存在即触发 PON。要"插线真关"只能在内核 do_msm_poweroff 里加 SPMI
  写，屏蔽 CHGR PON 触发——代价是插线也不再自动开机（需按电源键）。
  属于内核补丁级改动，暂记 WAITING（收益/风险不成比例，拔线关机已可用）。
