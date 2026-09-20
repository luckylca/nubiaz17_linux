# Kali NetHunter 官方适配计划 — NX563J (Nubia Z17)

> 目标：让 NX563J 成为官方 Kali NetHunter 支持设备（devices.yml 收录）。
> 起点优势：我们的 Ubuntu 内核已基于 **LineageOS 官方同源同分支**
> (LineageOS/android_kernel_nubia_msm8998 @ lineage-22.2, cda6a278) 构建，
> 全部 12 个 downstream 补丁直接落在官方内核树上。
> 状态：K1-K5 已完成并真机验证；当前剩余 K6 官方上游提交，以及可选能力扩展。2026-09-20 已完成 NetHunter Docker runtime + slirp4netns 用户态 uplink 数据面真机 E2E；真实容器 Internet 仍待宿主联网后复测。测试后设备已逐字节恢复到稳定 Android/NetHunter boot（SHA256 `3c47a780…98fe`）。

## 官方要求（调研结论，2026-09-16）

来源：Kali NetHunter 官方 kernel/device 仓库 README + devices.yml。当前官方仓库名为 `kali-nethunter-kernels`（gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernels）；早期研究时本地克隆曾使用 `/tmp/knd`。

- **设备条目**：`devices.yml` 加 `- nx563j:`，kernels 里加 `nx563j-los`
  （LineageOS ROM 后缀约定 -los），注明 android: fifteen、linux: 4.04、
  arch: arm64、devicenames: nx563j、source 指向我们的内核仓库、
  features 列表。
- **内核二进制**：编译产物 `Image.gz-dtb` + ramdisk 增补文件
  （init.nethunter.rc、keyboard/mouse 描述符 bin）放到
  `<android>/<kernel-id>/` = `fifteen/nx563j-los/`。
  安装器（kali-nethunter-installer 的 boot-patcher）解包设备当前 boot.img、
  换内核、合并 ramdisk 增补——AnyKernel 思路，不需要我们出整 boot.img。
- **内核源码仓库**：公开、可复现构建，devices.yml 的 source 字段指向它（网页展示用）。仓库已建立：`github.com/luckylca/android_kernel_nubia_msm8998_nethunter`，分支 `nethunter-22.2`。
- **构建工具**：kali-nethunter-kernel-builder（/tmp/kb2）提供 4.04 补丁集
  与 AnyKernel3 打包；我们的 CI 已有等价流水线（build-downstream.yml，
  固定 commit + defconfig + fragment + patches/downstream）。
- **参照模板**：`oneplus5-los`（同为 msm8998/4.4 内核、LineageOS 22.2，
  作者 seppzer0 的 zero-kernel；features [HID, Injection, RTL88XXAU,
  RTL8187]）——目录结构、ramdisk、yml 字段全部可对照。

## 能力盘点（我们已有 vs 官方 features 标签）

| feature 标签 | 我们的状态 | 来源 |
|---|---|---|
| HID-4 | 4.4 内核 configfs gadget + CONFIG_USB_CONFIGFS_F_HID=y 已验证（主机实收） | 官方 README：4.x+ 使用 HID-4 标签；运行中内核 zcat config.gz |
| Injection / QCACLD | 内置 WCN3990：自研 qcacld-3.0 monitor+helper-vdev 注入补丁（0009），5GHz host-side PASS | patches/downstream/0009 |
| RTL88XXAU | 未集成（out-of-tree aircrack 源码，kernel-builder 有 4.04 补丁可移植） | 待做，标 kernel-side staged |
| RTL8188EUS/RTL8XXXU | in-tree rtl8xxxu 已 =y（Phase 5 kernel-side PASS） | config fragment |
| Internal_BT | WCN3990 HCIUART 已 =y，raw HCI PASS | config fragment |
| BT_RFCOMM | RFCOMM/BNEP 已 =y；2026-09-20 以 MIX Flip 为对端完成自动配对、RFCOMM 双向 payload/ACK，BNEP/PAN 亦完成真实链路与单向 ICMP 数据验证 | config fragment + Android 双机实测 |
| Docker | Docker-test kernel + Docker 29.1.3/containerd 1.7.35 已完成真机 runtime E2E：run/exec/mqueue/bind/cgroup/bridge/private-netns port publish/cleanup PASS；并已用 slirp4netns 将私有 Docker netns 接到 Android host netns，容器→宿主 HTTP 数据面 PASS 且 Android 全局 Docker 相关 iptables 规则不变。测试时宿主无外网默认路由，因此真实容器 Internet 尚未实收 | `tools/docker/nethunter-docker-ns.sh` + `test-nethunter-docker-e2e.sh` + `install-nethunter-slirp.sh`；首版 MR 暂不声明该 feature |

## 移植阶段

### K1. 内核仓库（luckylca/android_kernel_nubia_msm8998_nethunter） ✅ 2026-09-16
- ~~fork LineageOS/android_kernel_nubia_msm8998（fork-name 加 _nethunter 后缀）~~
  已完成：https://github.com/luckylca/android_kernel_nubia_msm8998_nethunter
- ~~推 `nethunter-22.2` 分支 = lineage-22.2 (cda6a278) + patches/downstream
  12 个补丁逐个 git am~~ 已推送（12 commit + 脚手架 commit a5fee84d +
  RNDIS 文档更正 e840cb1b），另含 NETHUNTER.md 与自包含 CI

### K2. NetHunter 内核 CI 构建 ✅ 2026-09-16（首绿）
- 内核仓库内 `.github/workflows/build.yml`（复用项目 CI 骨架，去掉补丁
  步骤——补丁已在分支上；fragment 存 nethunter/config/nethunter.fragment）
- 首跑 success（run 35050883162）：Image.gz-dtb 15,011,007 B
  sha256=2038303df80404048427a24ea24b8f3b7909914dce8a38ba48cc8bc38d7986a4
  源 commit a5fee84d；产物已存 artifacts/kali/nethunter-kernel-a5fee84d/
  （含 kernel.config/SHA256SUMS）；fragment 全部选项抽查已进 kernel.config
- 附带结论（真机验证）：**RNDIS 无需补丁**——defconfig 自带
  USB_CONFIGFS_F_GSI + RNDIS_IPA，gsi.rndis configfs 可创建（2026-09-16
  实测）；rc 的 win,rndis* 模式直接可用。kernel-builder 的
  fix-conflicts-with-rndis-configs.patch 不需要。

### K3. devices 仓库条目 + ramdisk ✅（本地备好，2026-09-16）
- 条目草稿：`kali/devices.yml.nx563j`（nx563j/nx563j-los；features 只标
  真机已验证且符合当前官方 README 命名的 [BT_RFCOMM, CDROM, HID-4, Injection, QCACLD, Internal_BT, NFS]；外置网卡类待 OTG 硬件）
- ramdisk 备好：`kali/fifteen/nx563j-los/ramdisk/`（init.nethunter.rc
  改自 oneplus5-los——同 msm8998/4.4 平台 configfs g1 路径一致；
  HID 键盘/鼠标描述符用 r8q-oui 的标准 boot 描述符，oneplus5-los 里的
  是 0 字节占位）
- boot 分区 by-name 路径已真机核实：/dev/block/bootdevice/by-name/boot
  → /dev/sde18（非 A/B 槽位设备，slot_device: 0）
- `Image.gz-dtb` 已从 K2 CI 归档产物复制到 `kali/fifteen/nx563j-los/Image.gz-dtb`，sha256=`2038303df80404048427a24ea24b8f3b7909914dce8a38ba48cc8bc38d7986a4`；与已真机安装的 kernel ZIP 内核逐字节一致

### K4. 安装器 zip 构建 ✅ 2026-09-16
- 用官方 kali-nethunter-installer build.py（用户已批准运行）+ 我们的
  devices 条目构建成功：
  - 内核包 `kernel-nethunter-20260916_115945-nx563j-los-fifteen.zip`
    (31MB, sha256 687eac5f…)
  - 完整包 `nethunter-20260916_121646-nx563j-los-fifteen-kalifs_full.zip`
    (2.02GB, sha256 f1708e66…)，含 kali-nethunter-rootfs-full-arm64
    (sha256 fd108959…与官方 SHA256SUMS 一致)
  - 均存 artifacts/kali/
- 坑：kali.download 的 https 在此网络下大文件会 SSL EOF，但 **http/80
  完全正常**——手动下 rootfs 放 data/rootfs/kalifs-full-arm64.tar.xz
  后 build.py 自动跳过下载。Mac 无 pyyaml/requests：python3 -m venv。
- build.py 读 `kernels/devices.yml`（软链到我们改过的 devices 树即可）。

### K5. 真机验证 ✅ 完成（2026-09-17）

**最终状态：LOS 22.2 + 自研 NetHunter 内核 + Magisk 30.7 + Kali 2026.2
full chroot 全部真机运行。** 全部证据如下。

#### 安装路径（实际走通的标准流程）
1. LOS recovery 刷入 + Factory Reset/Format data（recovery 菜单，用户点）
2. `adb sideload lineage-22.2-20260911-nightly-nx563j-signed.zip`
   —— **成功**。传输显示停在 47% + `Total xfer: 1.00x` 是 LOS 官方文档
   记载的正常现象（zip 内签名块占流尾部），不是失败。
3. 进系统 → `adb install Magisk-v30.7.apk` → app 内 "Select and Patch a
   File" 打补丁官方 boot.img（uiautomator+input tap 自动化驱动 UI）→
   fastboot 刷 `magisk_patched-30700_OLX8M.img`
   (sha256 fd59d0f2…) → root ✓（`su -c id` → uid=0）
4. `adb push` 完整包 + `su -c magisk --install-module nethunter.zip` →
   输出 "Kali NetHunter is now installed!"（AnyKernel 内核注入 +
   kalifs-full-arm64 解包约 10 分钟）
5. 重启后内核 = 我们的 CI 产物：`4.4.302-perf+ #1 SMP PREEMPT Wed Sep 16
   03:11:48 UTC 2026`（commit a5fee84d 构建），Magisk root 保留 ✓

#### 能力实测（2026-09-17，真机，内核 a5fee84d CI 构建）
| 项 | 结果 | 证据 |
|---|---|---|
| chroot | ✅ | Kali 2026.2 Rolling, 1794 包；msfconsole/aircrack-ng/wifite/bettercap/reaver 在 |
| NetHunter app 套件 | ✅ | com.offsec.nethunter + nhterm + kex + store ×2 已装，bootkali 由 app 首启生成 |
| Wi-Fi 注入（5GHz ch36） | ✅ host-side | con_mode 0→4，python3(chroot) 发 20/20 probe-req，dmesg `mon-inject: helper vdev 4 ... on 5180 MHz`/`first frame submitted`，无 FW assert；恢复等 helper vdev destroyed 后 con_mode→0，Wi-Fi 服务回启用，全周期干净 |
| HID | ✅ 主机实收 | 枚举：Mac 实见 "HID Keyboard" 0x1d6b:0x0104（须先 setprop sys.usb.config none 防 UsbDeviceManager 抢回 UDC）；按键：mknod /dev/hidg0 后 chroot hid-type.py 打 8 轮 "NX563J HID TEST"，Mac 文本框逐字实收（2026-09-17，用户在场确认） |
| 蓝牙 | ✅ | svc bluetooth enable → adapter ON（"Nubia Z17"） |
| USB Arsenal profiles | ✅ 主机实收（2026-09-20） | boot-integrated `init.nethunter.rc`：`win,hid,adb`→macOS `046d:c317` 且 `hid.0+hid.1+ffs.adb`；`win,rndis,adb`→`0525:a4a3`、`rndis0`、`RNDIS_IPA NetDev was initialized`；修正后的 `mac,reset`→`2a70:f003`；`mac,reset,adb`→`2a70:4ee7` 且 ADB 恢复 |
| BT RFCOMM/BNEP | ✅ 双机实收（2026-09-20） | 对端 Xiaomi MIX Flip：双方自动确认配对到 `BOND_STATE_BONDED`；RFCOMM 实发 `NX563J_RFCOMM_TEST`，对端实收并回 `MIXFLIP_ACK:NX563J_RFCOMM_TEST`，两端 `CLIENT_PASS/SERVER_PASS`；PAN/BNEP 双方 `bt-pan UP,LOWER_UP`，TX/RX 计数严格互相对应，临时测试 IP 下 MIX→NX ping 3/3、0% loss（反向 ICMP 被 Android tether/firewall 策略过滤） |
| Wi-Fi STA 回归 | ✅ | 自研内核下日常上网正常：-33dBm / 866.7Mbit/s / generate_204 通过（2026-09-17） |

#### 踩坑实录（重要教训）
- **固件门假设被推翻**：首刷 LOS 失败时怀疑 `nubia.verify_modem
  ("2019-10-15 22:18:21")` 断言（要求 NubiaUI ≥6.25）。用 diag 系统直接
  grep modem 分区（/dev/sde10）按 recovery_updater.cpp 的 bm_search 模式
  `Time_Stamp": "` 取到 **2020-11-07 12:30:27**——机器早已是 6.28 固件，
  断言本就能过。真正首败原因大概率是 47% 传输假象被误判为失败后中断。
  **教训：sideload 失败后第一时间拉 /tmp/recovery.log，不要猜。**
- **NH 完整包是 Magisk 模块**（updater-script 以 `#MAGISK` 开头），LOS
  recovery sideload 必败（~6% 即断，Total xfer 0.13x）。**Magisk v26+
  删除了 recovery 安装路径**，"unable to unpack boot image" 是正常现象。
  正确路径就是上面的 3-4 步。
- **触摸卡死**：LOS 首启后触摸完全无响应——冷启动（长按电源 15s 全关再开）
  后恢复。疑为 Goodix 触摸 IC 被多次热重启 wedge 住，属硬件状态问题。
- **busybox 检查失败**（NetHunter app 报 "No busybox is detected"）：
  模块 post-fs-data.sh 生成的 `busybox_nh` 符号链指向
  `/data/adb/modules/...` 绝对路径，而 `/data/adb` 是 `drwx------ root`——
  非 root 的 app/shell 域无法穿透，exec 报 "inaccessible"。修复：模块内
  改相对链接（`busybox_nh -> busybox_nh-1.38.0`）+ 修补 post-fs-data.sh
  使其重启后仍生成相对链接 + live overlay `mount -o remount,rw
  /system/bin` 改链接。**这是官方安装器在 Magisk+Android 15 上的真实
  bug，值得回报上游。**
- **Magisk su 授权**：`su` 默认弹窗 10s 超时即拒 → shell 显示
  "Permission denied"。需在 Magisk Superuser 页给 Shell/NetHunter 开允许
  （本次用 uiautomator 自动点）。
- Mac 端 `fastboot` 在刷机命令被中途杀掉后会**挂在等数据的设备侧状态**：
  设备能枚举但所有命令无响应——只能硬重启手机解决（LOS wiki 也记载了
  此类 bootloader USB 怪癖，建议 USB 2.0 口/Hub）。

#### 回退路径
- 回 Ubuntu：`work/dist/nx563j-ubuntu-20260919.tar.gz` 一键包（已内置 Server Watch；解压后运行 `bash flash.sh`）。
- 回 Kali（刷走之前已做状态备份，2026-09-18）：
  `work/kali-state-backup-20260918/`——含 boot 分区整盘 dump
  （Magisk+NH 内核精确状态，sha256 a25ad3c1…）、已修复 busybox 的
  nethunter 模块包、nh_files、全部验证脚本、magisk.db；README 里有
  快速路（10 分钟）/完整路（五步法）两种恢复流程。

### K6. 上游提交 ⏳ 预提交完善中
- GitLab MR 目标为当前官方 `kali-nethunter-kernels`：合并 `kali/devices.yml.nx563j` 到上游 `devices.yml`，并提交完整 `fifteen/nx563j-los/`（`Image.gz-dtb` + `ak_patches/01-nx563j-magisk-sar-ramdisk.sh` + ramdisk）
- MR 候选树已完整；`kali/validate_submission.sh` 会校验 kernel SHA、已测试 ZIP 一致性、HID descriptors、ramdisk 功能内容、YAML 与公开 source branch
- 2026-09-20 重新核对当前 GitLab upstream `main`：remote HEAD=`e5991aa941188697e56c526c1dbc9979afa2db28`，与本地 upstream metadata cache 一致。把最终候选（含 `BT_RFCOMM`）合并进完整 upstream `devices.yml` 后，官方 `.yamllint.yml` PASS；按 upstream Git tree 精确 materialize 目录骨架后运行官方 `bin/devices-integrity.py` PASS（`Kernels in directories: 271` / `Kernels in YAML kernels: 271`）。
- 已用 2026-09-19 当前官方 `kali-nethunter-installer` main 对候选树重新执行 kernel-only `--installer` 构建。当前 devices feature 标签经 2026-09-20 真机补测、CDROM 主机实收与既有 NFS 真机验证更新为 `[BT_RFCOMM, CDROM, HID-4, Injection, QCACLD, Internal_BT, NFS]`；feature 元数据不进入 kernel-only ZIP，因此当前 pre-MR 验证包仍为 `artifacts/kali/kernel-nethunter-20260919_205420-nx563j-los-fifteen-pre-mr.zip`，sha256=`4f9b33dc87ca3080d0c30f4ebbc2ee9f37154fa009998b5742950de3f1400c23`；该包中的 kernel、rc 与两个 HID descriptor 均与当前 MR 候选逐字节一致。此包目前属于 pre-MR 构建验证件，真机验证基线仍是 2026-09-16 包
- 2026-09-19 校验：候选 `Image.gz-dtb` 与 CI 归档及已真机安装的 kernel ZIP 均为 sha256 `2038303d…`; source branch `nethunter-22.2` 当前头 `e840cb1b`，相对构建 commit `a5fee84d` 仅修改 `NETHUNTER.md`，无 kernel/config 变化
- 预提交审计发现并修正 ramdisk 模板中的 3 个重复 USB trigger：Mac RESET / RESET+ADB 段误写成 `win,reset*`，现已改为 `mac,reset*`；validator 只允许这 3 个已审阅功能差异，其余可执行 rc 必须与真机测试 ZIP 一致
- 2026-09-20 两个原阻塞项均完成真机闭环：运行中 boot 已确认加载候选 `overlay.d/init.nethunter.rc`，USB Arsenal 的 HID+ADB、RNDIS+ADB、`mac,reset`、`mac,reset,adb` 均在 Mac 主机实际枚举通过；蓝牙以 rooted Xiaomi MIX Flip 为第二对端完成自动 bond、RFCOMM 双向 payload/ACK，进一步完成 PAN/BNEP `STATE_CONNECTED`、双方 `bt-pan LOWER_UP`、镜像 TX/RX 计数及 MIX→NX 3/3 ICMP。临时 privileged 测试模块/APK 已从两台设备清理并重启回归，基础蓝牙仍为 ON。`BT_RFCOMM` 因此正式进入 devices feature 列表；BNEP 作为补充证据记录，不新增上游不存在的 feature 标签。
- 2026-09-20 `CDROM` 也完成真机闭环：当前 configfs `mass_storage.0/lun.0` 写入 `cdrom=1`、`ro=1` 并挂载测试 ISO 后，macOS 实际枚举为 `File-CD Gadget`（VID/PID `0930:6545`，BSD `disk4`）；watchdog 随后自动恢复到 `mac,reset,adb`，ADB/设备状态正常。因此 `CDROM` 正式进入 devices feature 列表。
- 另有**独立 future-support 实验**，不混入首版官方 MR：`config/downstream-nethunter-future.fragment` 新增 VCAN/SLCAN、CDC ACM、CH341/CP210X/FTDI/PL2303 与 RNDIS-host。GitHub Actions run `35484288726` 全量 kernel 构建 PASS（future Image SHA256=`f18ab1ee…`）并完成真机刷测：VCAN CAN_RAW `0x563/NX563J` 回环 PASS；SLCAN 用 PTY 模拟 LAWICEL 适配器完成 CAN↔ASCII 双向 PASS；USB 串口四类 driver 与 `rndis_host` 均在 sysfs 注册。测试后 boot 分区已精确恢复到刷测前 SHA256=`3c47a780…`；真实 gs_usb/USB 串口硬件仍未声明官方 feature。
- 维护者义务：跟随 LineageOS 22.2 nightly 内核更新重建

## 风险与注意

- **数据线/OTG 硬件未到**：RTL88XXAU 等外置网卡只做到 kernel-side
  staged，不标进 features。
- 2.4GHz 内置注入固件 bug（ratectrl_11ac assert）未解：NetHunter 内核
  继承同一补丁，文档里必须写明「注入仅用 5GHz」的限制（Android 侧
  2026-09-17 实测 ch36 注入 20/20 无 assert）。
- ~~LineageOS 22.2 的 SELinux=enforcing：NetHunter chroot 有现成适配~~
  已实测 chroot 正常工作（2026-09-17）；唯一 SELinux 相关坑是模块
  busybox 符号链穿透 /data/adb 权限问题（见 K5 踩坑实录，已修）。
- ~~不破坏 Ubuntu 日用机~~ K5 已执行：Ubuntu 已被 LOS 替换，回退用
  work/dist 一键包。
