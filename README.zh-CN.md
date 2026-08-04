<div align="center">

# ⬇️ MacDL

**一个不打扰你的下载管理器。**

---

## 📦 下载 — 预览版

当前版本为 **v0.1.0（预览版）** —— 早期发布，**可能不稳定**。
可从 [Releases 页面](https://github.com/mwx280/MacDL/releases) 下载 DMG。

> 首次打开：右键 → 打开（ad-hoc 签名，未公证）。



粘贴链接，它就下载。退出应用，它还在下载。就这么简单。

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()
[![CI](https://github.com/mwx280/MacDL/actions/workflows/ci.yml/badge.svg)](https://github.com/mwx280/MacDL/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v0.1.0%20Preview-orange.svg)](https://github.com/mwx280/MacDL/releases)
[![Size](https://img.shields.io/badge/app-1.8%20MB-lightgrey.svg)]()

**[English](README.md)** · 简体中文

</div>

---

## 🎯 问题

每次下大文件都像打一场小仗。浏览器下到一半放弃续传；你装的"下载管理器"非要霸占整个屏幕；还有那个下两小时的 8 GB 文件——Wi‑Fi 抖一下，全部重来。

**本不该如此。**

## 💡 MacDL 的做法

> **一个菜单栏小图标。八路并行下载。真正能续传的续传。仅此而已。**

- **🪶 轻量** — 整个 App 仅约 1.8 MB（DMG 不到 1 MB）。无重型引擎、无云、无臃肿。
- **复制链接 → 开下。** 没有向导、没有表单、没有登录。点一下「从剪切板下载」就行。
- **大文件，拉满速度。** 文件拆成分块，最多 **8 路并行**下载——多数浏览器做不到。
- **续传扛得住一切。** 退出应用、重启 Mac、一周后再回来：下载**分毫不差**地从断点继续，绝不重新下载。
- **绝不打扰你。** 它是菜单栏应用。隐藏 Dock 图标、开机自启、后台运行——屏幕始终是你的。
- **真·沙盒。** 只碰你选定的文件夹，绝不静默读取整个磁盘。
- **该出声时出声。** 下载开始/完成时一个安静的横幅；更关键的是——**优先下载重试耗尽时它会告诉你**，让你不会对着死掉的进度条干等。

## 🚀 10 秒上手

```
1. 复制任意直链到剪切板                              ⌘C
2. 点菜单栏 ↓ →「从剪切板下载」
3. 在菜单栏看它下完——或者打开窗口，安心等
```

就这么简单。这是个下载器，不是全家桶。

## 📸 截图

![MacDL](screenshot.png)

## 🧠 原理

```
 粘贴 URL
      │
      ▼
 [Range 探测] ──► 206?  ──►  分块并行下载（最多 8 路）
      │              │
      │              └──► 200?  ──►  单连接兜底
      ▼
 续传？  ──►  有界 Range 头，零字节重复
      ▼
 完成  ──►  .macdl 暂存重命名为真实文件
```

- **纯原生** — `URLSession`，无 aria2/wget 副进程，无云、无账号。
- **令牌桶限速** — 字节级，可按任务或全局。
- **一个引擎，两套代码** — 引擎是独立 Swift Package（`MacDLCore`），零 AppKit，可独立回归测试。
  引擎自带 [GPL-3.0 LICENSE](MacDLCore/LICENSE)，被复用/拷贝时许可随包走。

## 🛠️ 构建

```bash
open MacDL.xcodeproj          # 然后 ⌘R
# 或命令行：
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

> **系统要求：** macOS 26+ · Xcode 26+

## 🧪 测试

```bash
cd MacDLCore && swift test                    # 引擎套件
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO   # App 套件
```

## 📜 更新日志

完整的版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 📄 许可证

[GPL-3.0](LICENSE)

**明确限制：**

- ✅ 个人使用、学习、修改、fork 完全自由
- ✅ 将修改后的版本以 GPL-3.0 协议开源发布，完全自由
- ❌ 将本项目的任何部分（包括 `MacDLCore` 引擎）以**闭源形式**集成进任何商业软件并分发，严格禁止
- ❌ 将本项目的代码或修改版作为**闭源产品**对外销售，严格禁止

违反上述条款的行为将被视为侵犯著作权，作者保留追究法律责任的权利。
