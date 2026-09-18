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

## 2026-09-12 插线关机收官（HALT 方案）+ 亮度滑块

### 插线关机 = 冻结不重启（实机 PASS）
- 结论回顾：abl EFI 分区无 charger/offmode 字串，本机不存在 offmode-charging
  模式；PMIC PON 的 charger trigger 会在 VBUS 存在时把 POWER_OFF 变成重新
  上电——这就是"菜单关机变重启"的机理（见上文 task #24 节）。
- 方案：插线时不发 PON 断电指令，改走 LINUX_REBOOT_CMD_HALT（0xcdef0123）。
  内核停机但 PMIC 未收到关机命令，charger trigger 无从触发，效果等同关机。
- 实现：
  - tools/powerctl/powerctl.s 增加 `halt` 模式；参数匹配改为**全串精确匹配**
    （原先按首字母分派，`powerctl bogus` 的首字母 b 会命中 bootloader 进
    fastboot——已实测踩过一次）。构建 435 B，sha256 4ad22677…，
    部署 /usr/sbin/powerctl。
  - tools/desktop/fake-logind.py：PowerOff() 先查
    /sys/class/power_supply/{usb,ac,mains}/online——在线则 blank fb0
    （FB_BLANK_POWERDOWN）后 `powerctl halt`，拔线则照旧 `powerctl poweroff`。
- 验证（2026-09-12 21:37，USB 插 Mac）：dbus PowerOff 触发后 5 s 内 ssh 断，
  之后连续 4 分钟 + 额外探测全程 DOWN（39×DOWN，无一次回上线）；旧路径同
  条件 60–90 s 内必回。判 **PASS**。恢复方式：长按电源键 ~10 s。
- 注意：halt 后设备对外完全死掉（USB gadget 也断），属预期。

### 面板亮度滑块（截图 + 用户实触 PASS）
- 背光双节点需同步写：/sys/class/leds/lcd-backlight（max 255）与
  /sys/class/leds/wled（max 4095），按百分比线性映射。
- tools/desktop/brightness-slider.py：GTK3 滑块窗口（5–100%，80 ms 节流），
  --set N / --restore CLI；设定值持久化 /root/.brightness，xinitrc 启动时
  --restore 恢复（开机默认值在 initramfs 里，rootfs 层只能管到 X 会话起）。
- 面板 quicklaunch 第 4 图标（mate-brightness-applet 太阳图标；hicolor 里
  没有 display-brightness-symbolic，首版 fallback 成丑占位图，已换）。
- 验证：--set 30 → lcd 76/wled 1228；--set 80 → lcd 204/wled 3276，比例正确；
  抓屏确认窗口与图标渲染；用户随后实际拖动到 50% 并移动窗口，触摸链路可用。

### 重复窗口修复（亮度/键盘单实例）
- 现象：点面板图标两次会开出两个亮度窗口、两个屏幕键盘。
- 亮度：brightness-slider.py 启动时 flock /tmp/brightness-slider.lock，
  抢不到锁则 wmctrl -a 唤起已有窗口后退出（二次点击=聚焦，不再新开）。
- 键盘：kbd-toggle.sh 全程 flock 串行化（双击竞态下两个进程都通过
  pidof 检查 → 各起一个键盘）。注意 matchbox-keyboard 启动必须 9>&-
  关掉锁 fd，否则它终身持锁，之后的切换全部死等（实测挂死一次）。

## 2026-09-13 BT 常驻看门狗 + 物理按键（#28 进行中）

### BT 自起改为永久看门狗
- 故障：halt 循环后的开机里，supervisor 三次 attach 全遇 TIOCSETD N_HCI
  EINVAL（早启瞬时态），达到 3 次上限后放弃；且旧逻辑见到 bluetoothd
  一次就退出，运行期蓝牙栈丢失无人能救。
- 修复（tools/wifi-bringup/wifi-bringup4.sh）：supervisor 改 while-true
  永久看门狗，attach 每轮 12 次、耗尽后重新 hci_qcomm_init 初始化芯片
  再来一轮；bluetoothd 消失会重启。部署 /root/wifi-bringup4.sh，下次
  开机生效。当次已手动 attach + bluetoothd 恢复（hci0 UP RUNNING）。

### 物理按键（keys-daemon.py）
- 设备：qpnp_pon(event0)=电源键 116 + 音量下 114;gpio-keys(event5)=
  音量上 115。按名字解析 /dev/input/event*,evdev 直读。
- 电源键短按 = 息屏/亮屏：息屏时保存并清零 lcd-backlight+wled、
  FB_BLANK_POWERDOWN,EVIOCGRAB 两个触摸设备防误触；亮屏按 desktop.sh
  验证过的顺序：unblank → 重臂 msm_cmd_autorefresh_en → fb-kick.py
  单次 pan(严禁循环）→ 恢复亮度 → 释放触摸。ssh 手动全序列实测 PASS。
- 音量键 = 亮度 ±8%（声卡不存在，#22 修好后再改回音量）。
- 自启：/root/.xinitrc(桌面会话范围）。

### #28 按键实测收尾（PASS）
- 电源键：两次完整息屏/亮屏循环（10:52、11:05 日志），第二次循环
  touch-forward SIGSTOP/CONT 屏蔽触摸生效，无 EBUSY。
- 音量键：音量下 49%→9% 连降、音量上回升，方向正确；亮度下限由
  滑块的 MIN_PCT=5 兜住（设 1% 被钳到 5%）。
- 触摸屏蔽从 EVIOCGRAB 改为 SIGSTOP touch-forward：真实触摸设备被
  forwarder 常抓、uinput 克隆被 X 持有，GRAB 必 EBUSY。
- 外放仍阻塞于 #22(ADSP PIL invalid resource),音量键暂映射亮度。

## 2026-09-14 #22 外放攻破（PASS,用户实测听到声音）

### 完整根因链（四层）
1. **ADSP 不启动**:内核 request_firmware("adsp.mdt") 运行在 PID1 的
   mount namespace(initramfs ramfs /fwimage,只放了 wlan 固件),chroot
   里 staging 的 /fwimage 对它不可见 → PIL 60s uevent 超时 -EAGAIN →
   ADSP 永不启动 → 无 QMI SLIM 服务 → tasha codec 不枚举 → 声卡永远
   EPROBE_DEFER。修复:staging 同时写 /proc/1/root/fwimage/ 再
   echo 1 > /sys/kernel/boot_adsp/boot(已入 wifi-bringup4.sh,
   开机自动)。
2. **tas2555 功放固件竞态**:驱动 ~1.6s request_firmware_nowait 早于
   staging → 60s 超时。且**功放掉电即丢固件**,下次流启动 setup_clocks
   报 "Firmware not loaded",enable 时不跑 startup/unmute 程序 → 静音。
   固件 block CRC 校验还需要 I2S 时钟在跑 → 必须在流打开时重载
   (TAS_FWLoad kcontrol)。
3. **QUAT_MI2S 路由是死的**:声卡 DT 节点(NX563J/audio.dtsi &snd_9335)
   没有 quat-mi2s-active/sleep pinctrl 状态 → msm_get_pinctrl 失败
   (dmesg "MI2S TLMM pinctrl set failed with -22"),gpio57-60 永不复用;
   且 gpio59/60 被 nubia_hw_gpio_ctrl 以 GPIO 名义占走。stock 其实用
   **PRI_MI2S**(mixer_paths "speaker" 路径 = SLIMBUS_0_RX +
   PRI_MI2S_RX),prim DAI 驱动自带 pinctrl,零 DT 改动。
4. **mixer_paths 误导**:"speaker-mono-2" 路径引用的 SpkrRight 控件在
   本机不存在(WSA max-devs=0,DAPM 路由建立失败日志可证),tasha 内部
   SPKR 通路不适用于 nx563j。

### 工作链路(实测 PASS)
MultiMedia1 → 'PRI_MI2S_RX Audio Mixer MultiMedia1'=1,1 →
AFE PRI_MI2S_RX(0x1000) → TLMM gpio65-68(pri_mi2s 复用) →
tas2555(i2c 6-004c,"Enable: load startup sequence"+"load unmute
sequence") → 扬声器。gpio69(spkr_i2s/MCLK)由 audio_ext_clk 持有。

### 落地文件
- tools/audio/audio-setup.sh:声卡出现后铺静态 mixer 路径(PRI 路由 +
  关 QUAT + Playback 0 Volume=0 即 0dB)。
- tools/audio/audio-fw-watchdog.sh:监听 pcm0p/sub0/status 的
  **owner_pid**(注意:q6asm 播放全程报 DRAINING,永不报 RUNNING),
  关闭→打开跳变时 amixer TAS_FWLoad 1 → 时钟在跑,固件加载
  "YChkSum match" → unmute。每次流启动自动完成。
- 两者已挂入 wifi-bringup4.sh 音频 staging 之后,开机自起。
- keys-daemon.py:音量键改调 'Playback 0 Volume'(±400≈4dB,0-8192,
  0=0dB 单位增益),不再当亮度用。

### 验证记录
- 手动全序列(PRI 路由 + 播放中 TAS_FWLoad):880/660Hz 音阶,
  **用户确认听到**(2026-09-14)。
- 看门狗自动触发:日志 "playback opened -> TAS_FWLoad poked",
  dmesg Enable:1 + startup + unmute sequence。
- 重启全链路(开机自起 ADSP→声卡→路径→看门狗→首放音)见下节结果。

## 2026-09-14 #29 PulseAudio 桌面音频（PASS,用户实测）

### 动机
'Playback 0 Volume'(FE 软音量)范围 0..8192 = 0..+82dB **只能增益**,
且流关闭即复位 → 音量键"音量- 没反应"(已在 0dB 下限)。需要真正的
衰减与持久音量。

### 落地
- pulseaudio 16.1(system 模式,--exit-idle-time=-1),配置
  tools/audio/system.pa:sink "speaker" = hw:0,0 tsched=0 **rate=48000**
  (tas2555 加载的配置是 48k,驱动对采样率不匹配直接拒绝)、
  native socket /var/run/pulse/native 免认证、suspend-on-idle 闲时释放
  设备(省电,重新打开由 FW 看门狗兜底)。
- /dev/snd/* 0600 root:root → pulse 用户打不开,报误导性
  "No such file or directory":audio-setup.sh 里 chmod 0666。
- **启动顺序坑**:pulse 必须在声卡注册之后启动,否则 alsa-sink 加载
  失败、server 起来零 sink(第一次冷启动踩中)。pulse 启动移到
  audio-setup.sh 末尾。
- **mixer 回读验证**:声卡刚注册时路由服务可能静默吞掉 cset(第二次
  冷启动:路由没铺上,首次播放零 AFE/tas2555 活动)。audio-setup.sh
  改为 cset + cget 回读,失败重试 10 次。
- keys-daemon.py:音量键 → pactl ±5%(0-100%,带 pulse 不在时的
  amixer 兜底)。日志 "volume 80% -> 75%" 双向验证。

### 验证(全部用户实测)
- paplay 660Hz:出声;看门狗在流打开时自动 TAS_FWLoad
  ("playback opened -> TAS_FWLoad poked" → YChkSum match → unmute)。
- 30% vs 100% 两遍对比:第二遍明显更响(软衰减生效)。
- 音量键双向可调。
- 冷启动 ×3 持久化:第三次起开机零干预首放即出声(路由回读 +
  pulse 后置启动修复后)。

### 附带:USB 代理应急通道
Wi-Fi 未关联时,设备经 USB gadget 走 Mac 上网:/tmp/usbproxy.py
(Mac 侧 CONNECT 代理 10.42.0.32:8080,免 sudo NAT)+ 设备
ip route add default via 10.42.0.32 + apt -o Acquire::https::Proxy。
设备时钟 1970 导致 TLS "certificate is not yet valid" 时需先 date -s。

---

## 2026-09-19 Wi-Fi 守护死循环根因 + Docker 全链路

### Wi-Fi: LOS 覆盖 sda9 引发的 ABI 错位(随机死机头号嫌疑)

- 现象: cnss-daemon/pm-service/pm-proxy/wcnss_filter 各 100% CPU 纯用户态
  死循环(wchan=0, strace 无 syscall), 20+ 分钟; wlan0 不出现。
- gdb 栈: `WaitForProperty("servicemanager.ready")` ← `defaultServiceManager()`
  ← `pm_register_connect`。LOS A15 libbinder 新增 servicemanager.ready 等待,
  Ubuntu 无 Android init/property service → 永远等不到 → 死循环。
- vendor (sde41) 是 stock SDK29 没被 LOS 动过; /system-min 却用 LOS A15
  ramdisk 库拼装 → A10 vendor 二进制 + A15 libbinder 错位。
- 修: /system-min 换成 GitHub Jiovanni-dump/nubia_nx563j_dump 的 A9 stock
  lib64+bin (partial clone+sparse checkout, 314MB); A9 libselinux 缺 A10 符号
  `selinux_vendor_log_callback` → gcc -nostdlib 编 LD_PRELOAD shim 补符号
  (/system-min/system/lib64/libselinux_shim.so, wifi-bringup4.sh 里 export)。
- pm-service 在 A9 库下 SIGABRT(invalid free, "old property service protocol"
  之后)且非必需 → 参照 cnd 先例从 keepalive 移除, wlan0 实测无损。
- 结果: 守护 CPU 100%→0-5%; wlan0/wlan1/p2p0 出现; 扫到并连上 Mac 热点
  5GHz(WPA2), DHCP 192.168.2.7; Wi-Fi 直连互联网 OK; Wi-Fi SSH 第二控制
  通道 OK。路由: wlan0 metric 100 主, usb0 metric 200 备。

### Docker: 三个真坑, 全部根因实锤

1. **dockerd NewDaemon panic**: 表象 nil deref (daemon.go:1080 cleanup),
   真因被 panic 吞掉 —— devices cgroup 没挂上(getSysInfo CgroupDevicesEnabled
   检查)。docker-env.sh 此前从未被 rc.boot.ubuntu 调用(日志是手动跑的旧
   记录)。已把 `sh /root/docker-env.sh` 写进 rc.boot.ubuntu。
2. **docker import "remount /, flags: 0x84000: EINVAL"**: go-archive
   goInChroot 在 unshare(CLONE_FS|CLONE_NEWNS) 后 MakeRSlave("/"); 内核 4.4
   do_change_type 要求 `path->dentry == path->mnt->mnt_root`, 而 chroot 根
   是普通目录、且 chroot 发生时钉住的 vfsmount 是 sda10 整盘挂载(mnt_root
   是盘根 ≠ ubuntu 目录)→ 永远 EINVAL。chroot 之后再自绑无效(根引用不变)。
   **修: initramfs init 在 chroot 前先 `mount -o bind $TARGET $TARGET`**
   (boot-rslave2-signed.img)。注意必须在 dev/proc/sys bind 之前, 否则
   非递归自绑遮蔽子挂载 → Ubuntu 没 /proc(第一次踩中, rslave2 修正顺序)。
   刷入后实测 `mount --make-rslave /` OK, docker import 立刻成功。
3. **runc 挂 mqueue EBUSY**: kretprobe 实锤 sget_userns 返回 -EBUSY
   (arg1=0xfffffffffffffff0)。根因: CAF 4.4 回填了 4.9 的 user_ns 感知
   mqueue_mount/mount_ns, 但 create_ipc_ns 仍按 4.4 顺序**先 mq_init_ns
   后设 user_ns** —— kern-mount mqueue 时 sb->s_user_ns 是 kmalloc 垃圾,
   之后容器内挂 mqueue 在 user_ns 比对处必 -EBUSY。vanilla 4.9+ 顺序相反。
   修: patches/downstream/0013-ipcns-user-ns-before-mqueue.patch (CI 构建中)。
   补丁落地前的临时绕行: `docker run --ipc=host`(同 ns 重复挂 mqueue 合法)。

### Docker 实测矩阵(2026-09-19, 内核 e395ffb7+rslave2 ramdisk)

| 项 | 结果 |
|---|---|
| docker import 本地 rootfs tar | PASS |
| run/exec/exit | PASS(--ipc=host) |
| 桥接 NAT 出网 (容器→aliyun) | PASS |
| 端口映射 Mac→容器 (Wi-Fi 192.168.2.7:8080 与 USB 10.42.0.1:8080) | PASS |
| --memory=128m 回读 | PASS (134217728) |
| --cpu-shares=512 回读 | PASS |
| -v /root:/mnt:ro | PASS |
| docker pull alpine:3.20 (dockerproxy.net 镜像) | PASS |
| docker build (RUN 步默认 ipc ns) | 等 0013 内核补丁 |
| 默认 ipc ns 容器 | 等 0013 内核补丁 |
| 手机本机 127.0.0.1 访问映射端口 | 超时(route_localnet=1 后仍不通, 低优先级) |

---

## 2026-09-19(晚) Docker 收官 + 电池托盘图标 + Wi-Fi 竞争修复

内核: boot-0013-final-signed.img (sha256
2c05d6cdc619aa9212a39fd0c82b668a8ff8b21971a2132f48435e6145b8a35c, sde18),
含 0013 ipcns 补丁 + docker fragment, ramdisk-rslave2。

### docker exec 落到 initramfs —— 4.4 mntns_install 根因(最后一个docker坑)

- 表象: `docker exec` 进容器看到的不是容器 rootfs, 而是 initramfs
  (busybox, /fwimage, logdisk.img); 容器 mountinfo 里
  resolv.conf/hostname/hosts 挂在 `/mnt/rootfs/ubuntu/etc/...`。
- 根因(源码实锤, fs/namespace.c @ cda6a278):
  1. 4.4 `mntns_install()`(line ~3484) 把 setns 进程的 fs root/pwd 重置为
     `mnt_ns->root`(follow_down 之后);
  2. `pivot_root` **从不更新** `ns->root`(全文件仅 2933/2977/3027 三处
     赋值, 都在 ns 创建/复制路径);
  3. 容器 mount ns 复制自 dockerd 的 ns, 其 root 是 initramfs rootfs;
     runc pivot_root 之后 ns->root 仍指 initramfs → dockerd exec 进程
     setns 时被内核拉回 initramfs。
- 修(rc.boot.ubuntu, 必须在 dockerd 启动前):
  `/proc/1/root/bin/busybox mount -o move /proc/1/root/mnt/rootfs/ubuntu /proc/1/root`
  把 ubuntu 自绑叠到 rootfs `/` 之上; follow_down 从 ns->root 依次穿过
  rootfs→ubuntu→(runc pivot_root 后)容器 overlay。
- **失败变体**: 在 initramfs init 里 chroot 之前做 move → PID1 root 停留
  在 rootfs, rc.boot.ubuntu 找不到, 掉 diag shell(boot-0013-rslave3,
  勿刷)。从 chroot 内经 /proc/1/root 操作才正确。
- 实测: exec 读到 alpine-release 3.20.10、/etc/resolv.conf、DNS 解析 OK。

### Docker 最终矩阵(全部硬件实测 PASS, 2026-09-19)

| 项 | 结果 |
|---|---|
| dockerd 29.1.3 启动 | PASS |
| 默认 ipc ns `docker run`(0013 补丁) | PASS |
| `docker build`(RUN 步) | PASS (nx563j/buildtest:v2) |
| `docker exec` 进正确 rootfs | PASS(见上) |
| 桥接 NAT 出网 + DNS | PASS (ping 223.5.5.5 0% loss) |
| 端口映射 Wi-Fi 192.168.2.7:8080 / USB 10.42.0.1:8080 | PASS (busybox nc HTTP 服务) |
| --memory=128m / --cpu-shares=512 | PASS (134217728 / 512) |
| -v bind | PASS |
| 已知限制 | 手机本机 127.0.0.1 访问映射端口不通(低优先级) |

### 电池托盘图标(LXQt)修复

- 表象: 面板托盘无电池图标; SNI 已注册、tooltip "Fully charged (100%)"
  正确, 但 IconName 为空、IconPixmap 是 256×256 **全零**(全透明)。
- 根因(lxqt-powermanagement 1.4.0 源码): `useThemeIcons` 配置键默认
  **false** → 走 `generatedIcon()` 用 QSvgRenderer 把内嵌 SVG 画到
  256×256 透明 pixmap 上 —— 本机这个渲染路径产出全透明(QtSvg 渲染
  失败, 未深追)。与图标主题无关(最初误判 breeze 未安装, 实际
  /usr/share/icons/breeze 齐全)。
- 修: `/root/.config/lxqt/lxqt-powermanagement.conf` [General] 加
  `useThemeIcons=true`, lxqt.conf `icon_theme=breeze`(freedesktop 命名
  battery-full-charging 等齐全; Adwaita 只有 -symbolic 变体, 不可用)。
  killall lxqt-powermanagement 由 lxqt-session 自动 respawn。
- 实测: SNI IconName="battery-full-charging", 托盘渲染绿色插头图标;
  **重启后保持**(配置在持久 rootfs)。

### Wi-Fi 启动竞争修复(本次重启 wlan0 不出现的根因)

- 表象: 重启后 wlan0 不出现, cnss-daemon 崩溃循环 "libnl.so not found"
  约 2 分钟; 一次性 `echo ON > /dev/wlan` 已在坏窗口消耗, 之后所有 ON
  写都超时 EINVAL("Invalid value received from framework" 驱动源码实锤
  等待 wlan_start_comp 超时), wlan 链整靴报废。
- 竞争: rc.boot.ubuntu 旧顺序先后台启动 wb4、后 bind /system-min→/system;
  wb4 自己也 `mountpoint -q /system || mount --bind /tmp/system/system
  /system` —— 若 wb4 抢先且 sda9 已失效(LOS 覆盖, 挂载失败),
  /tmp/system/system 是空目录 → /system 被空绑, rc.boot 的 mountpoint
  检查跳过 → vendor 守护全体找不到 bionic 库。
- 修(双侧防御):
  1. rc.boot.ubuntu: /system-min bind 移到 wb4 启动**之前**;
  2. wb4: 只在源目录确有 linker64 时才 bind(真 sda9 优先, 否则
     /system-min, 绝不绑空目录); cnss-daemon 启动前有界等待
     linker64+libnl.so 可见并打日志; ON 写改为每 10s 重试直至 wlan0
     出现(上限 15 次)。
- **诊断假象**: wb4 诊断里 "/system is not a mountpoint" 是 toybox
  mountpoint 对同设备子目录 bind 的误报(PATH 里 /system/bin 优先),
  不是真问题。同一文件 toybox ls 显示 UTC 日期、GNU ls 显示 CST,
  差 8 小时, 对比 mtime 时注意。
- 实测(修后重启): wlan0 UP + DHCP 192.168.2.7, hci0 UP, docker run/exec
  PASS, 电池图标在。
