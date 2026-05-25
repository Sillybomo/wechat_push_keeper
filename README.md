# 微信保推送杀主进程 (wechat_push_keeper)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Magisk](https://img.shields.io/badge/Magisk-20.4+-green.svg)](https://github.com/topjohnwu/Magisk)
[![KernelSU](https://img.shields.io/badge/KernelSU-supported-orange.svg)](https://kernelsu.org)
[![Android](https://img.shields.io/badge/Android-10+-brightgreen.svg)](https://www.android.com)

Magisk / KernelSU / APatch 模块，通过监听系统事件精准杀灭微信非必要进程，仅保留 `:push` 推送进程，大幅降低微信后台功耗。

## 📌 功能特性

- **事件驱动杀进程** — 监听 `am_proc_start` 事件，微信非 `:push` 进程启动后等待 5 秒自动杀灭
- **灭屏杀进程** — 监听屏幕熄灭事件，灭屏时立即杀灭非推送进程
- **VoIP 通话保护** — 检测到微信语音/视频通话时延迟杀进程，通话结束后再清理
- **前台保护** — 微信在前台时不杀进程，不影响正常使用
- **零功耗延迟** — 事件驱动机制，无轮询无耗电
- **日志轮转** — 超过 100 行自动截断保留最新 50 行

## 📱 兼容性

- Magisk 20.4+ / KernelSU / APatch
- Android 10+
- 仅处理 `com.tencent.mm` 包名，不依赖微信版本号

## 📥 安装方式

### 方法一：Magisk/KernelSU 管理器

1. 下载最新 Release 中的 `wechat_push_keeper.zip`
2. 打开 Magisk / KernelSU 管理器
3. 点击 **模块** → **从本地安装**
4. 选择下载的 zip 文件
5. 重启设备

### 方法二：手动安装

```bash
# 解压模块到 Magisk 模块目录
unzip wechat_push_keeper.zip -d /data/adb/modules/wechat_push_keeper

# 设置权限
chmod 755 /data/adb/modules/wechat_push_keeper/service.sh

# 重启设备
reboot
```

## 📝 查看日志

```bash
# 查看运行日志
cat /data/local/tmp/wechat_push_keeper.log

# 实时跟踪日志
tail -f /data/local/tmp/wechat_push_keeper.log
```

### 日志示例

```
[2024-01-01 12:00:00] ========== service.sh 启动 ==========
[2024-01-01 12:00:05] 等待系统启动完成...
[2024-01-01 12:00:20] 系统启动完成，等待15秒...
[2024-01-01 12:00:35] 开始监听...
[2024-01-01 12:01:00] 事件: am_proc_start: com.tencent.mm:push
[2024-01-01 12:01:00] 进程: [com.tencent.mm:push]
[2024-01-01 12:01:00] 跳过 :push
[2024-01-01 12:02:00] 事件: am_proc_start: com.tencent.mm
[2024-01-01 12:02:00] 进程: [com.tencent.mm]
[2024-01-01 12:02:00] 非push进程 [com.tencent.mm]，等5秒...
[2024-01-01 12:02:05] 杀 PID=12345
```

## ⚙️ 手动控制

```bash
# 临时停用模块
kill $(cat /data/local/tmp/wechat_push_keeper.pid)

# 重新启用模块
sh /data/adb/modules/wechat_push_keeper/service.sh &
```

## 🗑️ 卸载

在 Magisk / KernelSU 管理器中移除模块即可。

`uninstall.sh` 会自动清理：
- 所有 PID 文件
- 日志文件
- 锁文件
- 运行中的进程（精确定位，不误杀其他模块）

## 🔧 工作原理

微信在后台维持消息推送时实际只需要 `com.tencent.mm:push` 进程。其余进程（主进程、工具进程等）均为非必要消耗。

本模块通过以下机制实现精准控制：

1. **Logcat 事件监听** — 监听 `am_proc_start` 事件，检测微信进程启动
2. **进程过滤** — 排除 `:push` 进程，仅处理非必要进程
3. **延迟杀灭** — 等待 5 秒确保进程完全启动后再杀灭
4. **前台保护** — 检测微信是否在前台，避免误杀
5. **VoIP 保护** — 检测语音/视频通话服务，延迟杀灭
6. **灭屏清理** — 屏幕熄灭时立即清理非必要进程

## 📊 功耗对比

| 场景 | 未安装模块 | 安装模块 |
|------|-----------|---------|
| 后台待机 8 小时 | ~3-5% | ~1-2% |
| 灭屏待机 | 频繁唤醒 | 仅 :push 运行 |
| 语音通话 | 正常 | 正常（保护） |

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交 Bug

请提供以下信息：
- 设备型号
- Android 版本
- Magisk/KernelSU 版本
- 日志文件 (`/data/local/tmp/wechat_push_keeper.log`)

### 功能建议

- 描述你想要的功能
- 说明使用场景
- 如有可能，提供实现思路

## 📄 开源协议

本项目采用 MIT 协议 - 查看 [LICENSE](LICENSE) 文件了解详情

## ⚠️ 免责声明

- 本模块仅供学习和研究使用
- 使用本模块可能导致微信推送延迟或其他异常
- 作者不对使用本模块造成的任何后果负责
- 请在了解风险后自行决定是否使用

## 🙏 鸣谢

- [topjohnwu](https://github.com/topjohnwu) - Magisk
- [rifsxd](https://github.com/rifsxd) - KernelSU
- 所有贡献者和测试用户
