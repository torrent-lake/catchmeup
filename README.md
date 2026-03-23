# AllTimeRecorded

极简常驻状态栏的 macOS 录音留存应用。

## 目标行为

- 开盖状态下持续录音。
- 屏幕熄灭不影响录音。
- 30 分钟分段存储 AAC。
- 强制睡眠（如合盖/手动睡眠）后自动续录，并写入 gap 事件。
- 仅状态栏右键菜单可退出。

## 关键边界（系统级）

- 应用可通过电源断言阻止 **idle sleep**（闲置睡眠），不能阻止 **forced sleep**（合盖、手动 sleep、热/低电保护）。
- 参考：
  - [Apple QA1340 - Assertions to Prevent System Sleep](https://developer.apple.com/library/archive/qa/qa1340/_index.html)
  - [caffeinate(8)](https://ss64.com/mac/caffeinate.html)
  - [pmset(1)](https://ss64.com/mac/pmset.html)

## 编码与存储规格

- 容器：`m4a`
- 编码：AAC-LC (`kAudioFormatMPEG4AAC`)
- 声道：1（mono）
- 采样率：22050 Hz
- 码率：24 kbps
- 分段：1800 秒（30 分钟）
- 路径：
  - 音频：`~/Library/Application Support/AllTimeRecorded/audio/YYYY-MM-DD/*.m4a`
  - 事件：`~/Library/Application Support/AllTimeRecorded/meta/events.jsonl`

## 项目结构

- `Sources/AllTimeRecorded/App`：生命周期、权限、退出闸门、入口
- `Sources/AllTimeRecorded/Audio`：录音主引擎与输入设备监听
- `Sources/AllTimeRecorded/Power`：电源断言、睡眠/唤醒监听、磁盘守护
- `Sources/AllTimeRecorded/Storage`：路径、事件落盘、异常片段修复
- `Sources/AllTimeRecorded/Timeline`：15 分钟 bin 映射
- `Sources/AllTimeRecorded/UI`：状态栏细条和 liquid glass popover

## 本地运行

1. 打开终端进入项目目录。
2. 执行：

```bash
swift build
swift test
swift run
```

## 打包为正式 App 前注意

- 当前以 Swift Package 形式实现，便于快速开发和测试。
- 若要分发为正式 `.app`：
  - 在 Xcode 建立 macOS App target 并引入 `Sources/AllTimeRecorded` 代码。
  - 参考模板 `AppTemplate/Info.plist` 配置 target 的 `Info.plist`。
  - 配置签名后再启用 `SMAppService.mainApp` 的登录项能力。
