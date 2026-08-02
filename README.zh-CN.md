<div align="center">

# ⬇️ MacDL

**一个常驻菜单栏的原生 macOS 下载管理器。**

原生 · 多线程 · 断点续传 · 剪切板 · 优先下载 · 通知

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()

</div>

---

## ✨ 为什么是 MacDL？

大多数下载器要么臃肿、要么绑定云盘、要么一启动就砸一个大窗口在你桌面。
MacDL 恰恰相反——它是个**菜单栏应用**，只做一件事：把文件下得**快、静、稳**。

- 🔒 **完全沙盒** — 不会悄悄读取你整个磁盘
- 🧩 **零外部引擎** — 纯原生 `URLSession`，不依赖 aria2 / wget 等第三方
- ⚡ **多线程** — 文件拆成分块，最多 8 个连接同时下载
- ⏸️ **真正的续传** — `.macdl` 暂存 + HTTP `Range`，重启后也能接着下
- 📋 **从剪切板下载** — 复制链接，一键开始
- 🎯 **优先下载** — 右键聚焦某个任务，其余自动暂停、完成后恢复
- 🔔 **通知** — 开始 / 完成 / 失败 / 优先任务重试耗尽
- 🚀 **菜单栏原生** — 开机自启、关窗隐藏 Dock 图标、后台运行
- 🌏 **双语** — English & 简体中文

## 🧠 下载原理

```
 粘贴一个 URL
      │
      ▼
 [探测: Range: bytes=0-0] ──► 206?  ──►  分块并行下载
      │                              │
      │                              └─►  200?  ──►  单连接兜底
      ▼
 之后恢复？  ──►  发送有界 Range 头，不重复下载
      ▼
 完成  ──►  把 .macdl 暂存文件重命名为真实文件名
```

## 🛠️ 构建

```bash
open MacDL.xcodeproj          # 然后 ⌘R
# 或命令行：
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

> **系统要求：** macOS 26+ · Xcode 26+

## 🧪 测试

```bash
# 引擎包测试
cd MacDLCore && swift test

# App 测试（串行，避免并行测试宿主下 Observation 的偶发崩溃）
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO
```

## 🏗️ 架构

```
MacDLCore/   Swift Package —— 引擎
             URLSession 分块引擎 · 令牌桶限速 · 续传逻辑
             （无 AppKit 依赖，可独立回归测试）

MacDL/       App —— SwiftUI 菜单栏界面 · 持久化 · 通知 · 沙盒
```

引擎是独立的 Swift Package，零 AppKit 依赖——可以复用到其他项目，
并拥有自己的快速 `swift test` 套件。

## 📄 许可证

[GPL-3.0](LICENSE) —— 可自由使用与修改，但衍生作品必须保持开源。
