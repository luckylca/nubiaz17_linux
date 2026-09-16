# Kali NetHunter 官方适配计划 — NX563J (Nubia Z17)

> 目标：让 NX563J 成为官方 Kali NetHunter 支持设备（devices.yml 收录）。
> 起点优势：我们的 Ubuntu 内核已基于 **LineageOS 官方同源同分支**
> (LineageOS/android_kernel_nubia_msm8998 @ lineage-22.2, cda6a278) 构建，
> 全部 12 个 downstream 补丁直接落在官方内核树上。
> 状态：2026-09-16 立项（用户拍板：Ubuntu 侧研究收尾，正式转 Kali 适配）。

## 官方要求（调研结论，2026-09-16）

来源：kali-nethunter-devices README + devices.yml（gitlab.com/kalilinux/
nethunter/build-scripts/kali-nethunter-devices，本地克隆 /tmp/knd）。

- **设备条目**：`devices.yml` 加 `- nx563j:`，kernels 里加 `nx563j-los`
  （LineageOS ROM 后缀约定 -los），注明 android: fifteen、linux: 4.04、
  arch: arm64、devicenames: nx563j、source 指向我们的内核仓库、
  features 列表。
- **内核二进制**：编译产物 `Image.gz-dtb` + ramdisk 增补文件
  （init.nethunter.rc、keyboard/mouse 描述符 bin）放到
  `<android>/<kernel-id>/` = `fifteen/nx563j-los/`。
  安装器（kali-nethunter-installer 的 boot-patcher）解包设备当前 boot.img、
  换内核、合并 ramdisk 增补——AnyKernel 思路，不需要我们出整 boot.img。
- **内核源码仓库**：公开、可复现构建，devices.yml 的 source 字段指向它
  （网页展示用）。目标仓库：
  `github.com/luckylca/android_kernel_nubia_msm8998_nethunter`（待建）。
- **构建工具**：kali-nethunter-kernel-builder（/tmp/kb2）提供 4.04 补丁集
  与 AnyKernel3 打包；我们的 CI 已有等价流水线（build-downstream.yml，
  固定 commit + defconfig + fragment + patches/downstream）。
- **参照模板**：`oneplus5-los`（同为 msm8998/4.4 内核、LineageOS 22.2，
  作者 seppzer0 的 zero-kernel；features [HID, Injection, RTL88XXAU,
  RTL8187]）——目录结构、ramdisk、yml 字段全部可对照。

## 能力盘点（我们已有 vs 官方 features 标签）

| feature 标签 | 我们的状态 | 来源 |
|---|---|---|
| HID | 内核 CONFIG_USB_CONFIGFS_F_HID=y 已验证（Phase 4 PASS，主机实收） | 运行中内核 zcat config.gz |
| Injection | 内置 WCN3990：自研 qcacld-3.0 monitor+helper-vdev 注入补丁（0009），host-side PASS | patches/downstream/0009 |
| RTL88XXAU | 未集成（out-of-tree aircrack 源码，kernel-builder 有 4.04 补丁可移植） | 待做，标 kernel-side staged |
| RTL8188EUS/RTL8XXXU | in-tree rtl8xxxu 已 =y（Phase 5 kernel-side PASS） | config fragment |
| Internal_BT | WCN3990 HCIUART 已 =y，raw HCI PASS | config fragment |
| BT_RFCOMM | RFCOMM/BNEP 已 =y（host 侧 Mac 待重启复测） | config fragment |

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
  真机已验证的 [HID, Injection, Internal_BT]，BT_RFCOMM 待 Mac 重启复测、
  外置网卡类待 OTG 硬件）
- ramdisk 备好：`kali/fifteen/nx563j-los/ramdisk/`（init.nethunter.rc
  改自 oneplus5-los——同 msm8998/4.4 平台 configfs g1 路径一致；
  HID 键盘/鼠标描述符用 r8q-oui 的标准 boot 描述符，oneplus5-los 里的
  是 0 字节占位）
- boot 分区 by-name 路径已真机核实：/dev/block/bootdevice/by-name/boot
  → /dev/sde18（非 A/B 槽位设备，slot_device: 0）
- Image.gz-dtb 用 K2 CI 产物；提交官方需 GitLab 账号 + MR（待用户确认）

### K4. 安装器 zip 构建
- 克隆 kali-nethunter-installer，bootstrap.sh 拉 devices 仓库（指到我们的
  fork/本地），build.py 出 Magisk 风格 NetHunter zip

### K5. 真机验证（需要用户在场的节点会明确标注）
- 刷官方 LineageOS 22.2 nightly（download.lineageos.org/devices/nx563j）
  —— **会替换 Ubuntu 系统**；回退路径 = 现成的一键刷机包
  （work/dist/nx563j-ubuntu-20260915，自测 PASS）
- Magisk root → 刷 NetHunter zip → 逐项能力验证（HID/注入/BT/OTG…），
  结果回写 docs/NETHUNTER_CAPABILITIES.md 与 devices.yml features
- 每次验证记录：日期/内核 commit/产物 SHA256/测试命令/PASS-FAIL（既定规则）

### K6. 上游提交
- GitLab MR 到 kali-nethunter-devices（devices.yml + fifteen/nx563j-los/）
- 维护者义务：跟随 LineageOS 22.2 nightly 内核更新重建

## 风险与注意

- **数据线/OTG 硬件未到**：RTL88XXAU 等外置网卡只做到 kernel-side
  staged，不标进 features。
- 2.4GHz 内置注入固件 bug（ratectrl_11ac assert）未解：NetHunter 内核
  继承同一补丁，文档里必须写明「注入仅用 5GHz」的限制。
- LineageOS 22.2 的 SELinux=enforcing：NetHunter chroot 有现成适配
  （官方安装器处理），但我们自研注入路径在 Android 下要重新验证
  （qcacld con_mode 在 Android wlan 服务下的行为可能不同）。
- 不破坏 Ubuntu 日用机：K5 之前所有工作都不碰手机。
