# Flutter Run 桌面工具设计

## 目标

使用 Flutter 构建 macOS、Windows、Linux 桌面应用，让用户在一个窗口内运行和管理现有 Flutter 项目、设备、Inspector 和 Android Logcat。代码编辑由外部工具完成，不提供源码断点、单步或变量调试。

## 功能

- 选择并记住 Flutter SDK 和项目目录，检查 SDK、项目和所需工具，显示可操作的错误信息。
- 列出 Flutter 可用设备及模拟器，刷新设备并启动可用模拟器；设备能力受宿主系统和已安装工具限制。
- 选择设备启动和停止调试会话，提供热重载、热重启，展示过程和错误。首版支持一个活动会话。
- 启动 SDK 自带 DevTools，通过应用内嵌浏览器连接当前调试会话，显示官方 Flutter Inspector；不另开浏览器窗口。
- 展示 Flutter 运行日志。Android 设备提供独立 Logcat 面板，支持设备选择、日志级别和关键词过滤、暂停及清空显示；非 Android 设备说明不可用。
- 停止会话或退出时清理应用启动的进程；设备断开、进程退出和工具不可用时显示状态。

## 方案

采用 Flutter 桌面界面，调用本机 Flutter SDK 管理设备与运行会话，调用 Android SDK 的 adb 获取 Logcat，启动官方 DevTools 并在桌面 WebView 中展示。另一方案是自行实现 Inspector；这需要自行维护组件树和调试协议，功能覆盖与版本兼容成本更高。用户选择内嵌官方 DevTools。

## 约束与验证

用户需自行安装 Flutter SDK 和目标平台工具链；iOS 构建和模拟器需要 macOS 及相应工具链。热重载和热重启针对调试会话。SDK、adb 和 DevTools 路径及启动失败须可诊断。内嵌浏览器在三个桌面平台的可用性、DevTools 与 Flutter SDK 版本兼容性需在实现时验证；不以未经验证的平台声称通过。分别验证项目和设备发现、启动与停止、热重载和热重启、Inspector 连接、Android Logcat 过滤及退出清理；报告区分实际执行的平台和未验证的平台。
