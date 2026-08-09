# MaidKit

<p align="center">
  <img src="assets/icons/icon-padded.png" width="120" alt="MaidKit Logo">
</p>

<p align="center">
  <b>一款跨平台 SSH 服务器管理器</b>
</p>

<p align="center">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License"></a>
  <a href="https://solsynth.dev/zh/products/maid-kit#download"><img src="https://img.shields.io/badge/download-solsynth.dev-blue" alt="Download"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文
</p>

---

MaidKit 是小羊在给服务器当女仆的时候（维护服务器）用到的工具合集。旨在提供一个非侵入式（100% 基于 SSH，不在服务器上安装任何软件，增加安全风险）更加方便的维护服务器。

基于 Flutter 构建，MaidKit 可在桌面和移动平台上运行。受 [Island](https://github.com/Solsynth/HyperNet.Surface) 项目桌面原生理念的启发，MaidKit 将同样的简洁、实用哲学带到了服务器管理领域。

---

## 目录

- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [架构](#架构)
- [技术栈](#技术栈)
- [贡献](#贡献)
- [许可证](#许可证)

---

## 功能特性

### 服务器管理

| 功能 | 说明 |
|------|------|
| 仪表盘 | 服务器卡片网格，实时显示状态、负载、内存和运行时间；可通过右键菜单排序、分组、打标签，并配置环境变量 |
| 活动监控 | 实时性能图表（CPU、内存、网络、磁盘） |
| 终端 | 支持分屏、拖拽标签页、命令面板和终端配色方案的完整 SSH 终端 |
| 文件管理 | 双窗格 SFTP 浏览器，支持拖拽传输、内置编辑器和键盘快捷键（复制/剪切/粘贴、重命名、刷新、搜索、删除） |
| 进程管理 | 查看和终止运行中的进程 |
| 服务管理 | Systemd 单元管理（启动/停止/启用/禁用） |
| Web 服务器 | nginx 和 Caddy 配置管理 |
| 定时任务 | 编辑 crontab 计划任务 |
| 软件包 | 软件包管理（apt、dnf 等） |
| 防火墙 | UFW、firewalld、nftables 和 iptables 管理 |
| 端口转发 | 本地和远程隧道配置 |
| 代理 | 通过每台服务器独立的 HTTP CONNECT 或 SOCKS5 代理连接主机 |
| Tailscale | 通过内置节点连接你的 tailnet，无需安装 Tailscale 应用 |

### 容器管理

- Docker 和 Podman 容器管理
- 启动、停止、重启、暂停、终止和删除容器
- Compose 项目分组，带详情视图（各服务状态、合并日志、生命周期操作）
- 容器镜像管理
- 运行时安装辅助

### 项目管理

- 部署项目目录
- 将 Compose 堆栈、Web 服务器和容器分组管理
- 以 TOML 格式导入和导出

### 脚本片段

- 创建和可编辑的可复用 Shell 脚本
- 在一台或多台已连接的服务器上执行
- 流式输出与进度追踪

### Agent

- 与能通过工具操作服务器的 AI Agent 聊天
- 自带 AI 提供商，或使用 Solar Network AI
- MCP 服务器和可复用技能扩展 Agent 的工具集
- 拟执行的操作需先经过批准（审查模式）
- 对话历史保存在本机，独立于凭证库

### GitHub

- 通过设备码流程登录
- 置顶仓库，跟踪工作流运行、拉取请求和发布
- GitHub 工具可供 Agent 使用

### 本地 MCP 服务器

- 通过本机的 Model Context Protocol 服务器，将 MaidKit 的 SSH 服务器、脚本片段和技能暴露给其他 Agent
- 可从 Claude Desktop 或任意 MCP 客户端连接

### 安全

- AES-GCM 256 位加密凭证库
- PBKDF2 密钥派生（310,000 次迭代）
- 生物识别解锁支持
- 可选的按凭证库云同步（Solar Network 加密数据块）
- 加密备份归档（.mkb）

### 设置

- 主题（系统/浅色/深色）、强调色和工作区背景图
- 语言（English / 简体中文）
- 终端渲染器选择（Ghostty libghostty-vt 或 xterm）、字体和配色方案
- 启动时自动连接
- 屏幕共享或录屏时隐藏服务器地址
- 指标刷新间隔
- Tailscale 登录与连接设置
- 按凭证库云同步、服务器连接的导入和导出

---

## 快速开始

### 前置条件

- 安装 [Flutter SDK](https://flutter.dev)（SDK ^3.12.2）
- Windows 开发需要安装 [NASM](https://www.nasm.us)（`webcrypto` 原生资源所需）：
  ```powershell
  winget install NASM.NASM
  ```
  此外，本地 Windows 构建还需要以下几项：

  - **Visual Studio 2022**，勾选 *使用 C++ 的桌面开发* 工作负载
    （提供 MSVC 编译器与 CMake，`flutter build windows` 会调用）。可通过
    Visual Studio Installer 安装，或：
    ```powershell
    winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    ```
  - **Go 1.26** —— Tailscale 集成在 `flutter pub get` 期间通过原生资源钩子
    从源码构建。CI 固定 `go-version: "1.26"`。
    ```powershell
    winget install GoLang.Go
    ```
  - **WebView2 运行时** —— `desktop_webview_window` 所需。Windows 11 默认已
    内置；Windows 10 需从[微软官网](https://developer.microsoft.com/microsoft-edge/webview2/)
    安装 Evergreen 引导程序。
  - **Cargokit 补丁。** Cargokit（Rust 原生资源所用）无法解析默认 `PUB_CACHE`
    所在隐藏 `AppData` 目录下的符号链接，且 Tailscale 钩子环境需要 `GOCACHE`。
    CI 的做法是把 `PUB_CACHE` 指到非隐藏路径，并在 `flutter pub get` 后运行
    补丁脚本：
    ```powershell
    $env:PUB_CACHE = "$env:LOCALAPPDATA\pub-cache"
    flutter pub get
    powershell -ExecutionPolicy Bypass -File buildtools/fix-cargokit-windows.ps1
    dart run build_runner --delete-conflicting-outputs
    flutter build windows --release
    ```
    发布安装包随后用 Inno Setup 基于 `setup.iss` 生成，需传入 pubspec 中的
    版本号与构建号（与 CI 一致）：
    ```powershell
    iscc /DAppVersion=<x.y.z> /DBuildNumber=<n> setup.iss
    ```
- Linux 开发需要安装额外依赖：
  ```bash
  sudo apt-get update -y
  sudo apt-get install -y \
    ninja-build \
    libgtk-3-dev \
    libayatana-appindicator3-dev \
    keybinder-3.0 \
    libnotify-dev
  ```

### 运行应用

```bash
# 安装依赖
flutter pub get

# 调试模式运行
flutter run

# 构建发布版本
flutter build <platform>
```

### Linux AppImage

构建发布包后，可打包为自包含的 Linux AppImage：

```bash
flutter build linux
bash buildtools/build-appimage.sh
```

该脚本会将 x64 发布包与桌面入口和运行辅助文件一起打包为 `MaidKit-x86_64.AppImage`。

### 开发

修改路由注解或 Drift 架构后需要重新生成代码：

```bash
dart run build_runner build
```

提交前运行检查：

```bash
dart format lib test
flutter analyze
flutter test
```

---

## 架构

功能模块扁平化，直接位于 `lib/<feature>/` 下。应用使用：

- **Riverpod** 进行状态管理，使用 `ConsumerWidget` 实现响应式视图
- **auto_route** 实现声明式嵌套导航
- **Drift** 用于本地 SQLite 持久化
- **dartssh2** 用于 SSH 连接
- **island_ui_foundation** 提供桌面窗口框架

完整的架构指南请参见 [docs/architecture.md](./docs/architecture.md)。

---

## 技术栈

| 层级 | 技术 |
|------|------|
| **框架** | Flutter + Material 3 |
| **状态管理** | Riverpod + flutter_hooks |
| **路由** | auto_route |
| **数据库** | Drift (SQLite) |
| **SSH** | dartssh2 |
| **加密** | Cryptography (AES-GCM, PBKDF2) |
| **终端** | libghostty-vt / xterm |
| **Tailscale** | tailscale（内置节点，macOS/Linux） |
| **MCP** | Model Context Protocol 客户端 + 本地服务器 |
| **桌面** | window_manager + island_ui_foundation |

---

## 贡献

欢迎贡献！请随时提交 Issue 或 Pull Request。

---

## 许可证

本项目基于 GNU Affero General Public License v3.0 (AGPL-3.0) 许可证发布。

如果你部署本软件的实例、分叉本项目，或重新分发本软件的修改版本，你必须遵守 AGPL-3.0 许可证条款，包括：

- 包含原始许可证的副本
- 保留现有的版权声明和署名
- 清楚地说明你所做的任何修改
- 为通过网络与服务交互的用户提供相应的源代码

在适用情况下，必须保留对 LittleSheep、Solsynth 以及本项目贡献者的原始作者身份和版权归属。

请注意，AGPL-3.0 许可证仅适用于软件源代码。某些资产、Logo、图标、品牌材料和商标可能单独许可，不自动受相同条款覆盖。

完整的许可证文本请参见 [LICENSE.txt](./LICENSE.txt)。

---

<p align="center">
  由 LittleSheep + ❤️ 打造
</p>
