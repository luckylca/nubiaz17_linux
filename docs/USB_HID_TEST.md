# USB HID-4 验证规程（Phase 4）

目标：证明 NX563J 作为 USB 复合设备（键盘 + 鼠标 + NCM 网络 + ACM 串口）
被真实主机识别，且主机真实收到 HID report。**以主机实收为 PASS 标准。**

## 设备端（手机）

```sh
setsid sh /root/hid-gadget.sh      # 加 HID 功能并重绑定（usb0 会瞬断）
ls -l /dev/hidg*                   # 应见 hidg0(键盘) hidg1(鼠标)
python3 /root/hid-type.py          # 打默认安全 payload "NX563J HID TEST"
python3 /root/hid-type.py "hello"  # 自定义文本
sh /root/hid-gadget.sh remove      # 恢复原 gadget 布局
```

注意：重绑定会断 usb0 一秒，务必 setsid/nohup 执行；Wi-Fi ssh
(192.168.1.186) 是兜底管理通道。

## 主机端（Mac，手机通过 USB 连接的就是它）

HID 键盘打出来的字会进入**当前焦点窗口**。步骤：

1. 打开一个文本编辑器（TextEdit / 终端均可），保持焦点。
2. 手机端执行 `python3 /root/hid-type.py`。
3. 编辑器里出现 `NX563J HID TEST` → 键盘 PASS。
4. 系统层面确认枚举：`system_profiler SPUSBDataType | grep -A5 -i nubia`
   应看到复合设备含 HID interface；`ioreg -l | grep -i hidg` 可选。
5. 鼠标验证（hidg1）：手机端写 3 字节 report（buttons, dx, dy），
   Mac 上观察指针移动：
   `printf '\\x00\\x28\\x00' > /dev/hidg1`（右移 40px）

## 记录要求（按能力矩阵纪律）

- 日期 / 内核（boot 镜像哈希）/ 主机系统版本
- system_profiler 枚举截图或文本
- 主机实收文本截图
- 结果写入 docs/NETHUNTER_CAPABILITIES.md（PASS 才允许）
