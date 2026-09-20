# NX563J Ubuntu 24.04 刷机包

努比亚 Z17 (NX563J) 的完整 Ubuntu 24.04 系统快照。这是开发机上验证过的
稳定版:显示/触控/Wi-Fi/蓝牙/外放/USB gadget SSH/USB HID 键盘鼠标/
监听模式+注入内核补丁,全部内建。Server Watch 全屏服务器监控面板也已预装，
包含当前打包时仓库中的最新 Full Dashboard UI 与监控 agent。

## 内容

| 文件 | 说明 |
|------|------|
| `boot.img` | 签名 boot 镜像(4.4.302 downstream 内核 + initramfs),见 MANIFEST.txt 的 SHA256 |
| `userdata.img.gz` | userdata 分区完整镜像(Alpine 底层 rootfs + /ubuntu Ubuntu 24.04 + /boot-target 引导选择),gzip 压缩 |
| `flash.sh` | 一键刷机脚本 |
| `img2simg.py` | raw→sparse 转换(bootloader 拒 raw 镜像时 flash.sh 自动用) |
| `MANIFEST.txt` | 版本/哈希/来源清单 |

## 刷机

1. 手机进 fastboot:关机按【音量下+电源】,或系统里 `/root/reboot-bl`
2. 数据线连电脑,本目录执行:

   ```bash
   bash flash.sh
   ```

**警告:userdata 会被整体覆盖**,手机上现有数据全部丢失。

## 系统说明

- 无 systemd(4.4 内核无 cgroup v2),PID1 是 initramfs 自定义 init,
  服务由 /root/rc.boot.ubuntu 拉起。
- 关机/重启:`echo b > /proc/sysrq-trigger`(重启)。普通 reboot 命令无效。
- Wi-Fi/蓝牙桌面:wpagui + blueman。
- Server Watch: 默认预装并写入系统快照；进入桌面后可从 LXQt quick-launch 单击打开 Full Dashboard。
- 源码与文档:https://github.com/luckylca/nubiaz17_linux
