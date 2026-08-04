<div align="center">

<img src="icon.png" width="128" alt="MacDL">

# MacDL

一个原生 macOS 下载管理器，可以完全在状态栏里用。

</div>

## 下载

当前版本：**v0.2.0（预览版）** —— 早期发布，可能有不完善之处。
[从 Releases 下载 DMG](https://github.com/mwx280/MacDL/releases)。

> 首次打开：右键 → 打开（ad-hoc 签名，未公证）。
> 需要 macOS 26 或更高版本。

## 它是什么

MacDL 是一个原生 SwiftUI 桌面应用。它有正常的窗口（侧边栏 + 下载列表），同时也常驻状态栏——**可以完全不打开窗口**，从状态栏图标完成所有操作：粘贴链接、看进度、暂停/恢复，需要时再打开窗口。

它很小（约 1.8 MB）、沙盒运行，没有账号、云或重型引擎。

## 下载引擎

引擎（`MacDLCore`）是真正干活的下载部分，直接基于 `URLSession` 实现——没有 aria2、wget 之类的副进程。

- **多线程分块。** 文件按固定大小拆成多个分块，每个分块用独立连接下载，最多 **8 路并行**。
- **先做 Range 探测。** 下载前先发一个 `Range` 请求试探服务器：返回 `206` 就知道文件大小，然后分块并行；如果服务器忽略 `Range`（返回 `200`），就退化为单连接整文件下载。
- **能真正续传。** 字节先写入 `.macdl` 暂存文件。退出应用、重启、隔一周回来——每个分块都从精确的偏移量用有界 `Range` 头继续，零字节重复。
- **退避重试。** 分块失败按指数退避重试（1s、2s、4s…），对 429/5xx 这类限流/服务器错误做了保护，不会猛打服务器。
- **每任务限速。** 字节级令牌桶，可按单个任务或全局限速，不是只限制单连接。
- **未知大小的下载。** 服务器不给 `Content-Length` 时，进度显示为不确定态而不是假百分比；下载完成后补上真实大小。

## 功能

- **新建下载页** — 一次粘贴多个链接，每个都能单独设线程数和限速；自动探测续传支持（不可续传的任务锁定为单线程）。支持把链接拖进去，也能从剪贴板自动读取。
- **从剪贴板下载** — 复制链接，用状态栏菜单项直接下。
- **优先下载** — 把一个任务标记为优先，其他任务自动暂停等它下完，再自动恢复。
- **通知可配置** — 想要哪些提醒（开始、完成、失败、重复链接）自己勾选，也可以全关。
- **自动更新** — 从 GitHub Releases 检查新版本，可自动下载，一键安装并重启。
- **后台友好** — 启动只显示状态栏图标、开机自启、关窗后隐藏 Dock 图标。
- **双语** — 简体中文和 English。

## 快速上手

```
1. 复制一个直链                              ⌘C
2. 点状态栏 ↓ →「从剪贴板下载」
3. 在状态栏看它下完——或打开窗口查看
```

## 架构

- `MacDL` — App 本体：SwiftUI 界面、服务层（设置、持久化、通知、更新）和下载生命周期。
- `MacDLCore` — 引擎，独立 Swift Package，零 AppKit。App 通过协议 + 依赖注入调用引擎，引擎可以单独做回归测试。它带自己的 [GPL-3.0 许可](MacDLCore/LICENSE)。

## 构建

```bash
open MacDL.xcodeproj        # 然后 ⌘R
# 或命令行：
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## 测试

```bash
cd MacDLCore && swift test                    # 引擎测试
xcodebuild build-for-testing -project MacDL.xcodeproj \
  -scheme MacDL -destination 'platform=macOS' \
  && xcodebuild test-without-building -project MacDL.xcodeproj \
  -scheme MacDL -destination 'platform=macOS'   # App 测试
```

App 测试要分两步：先构建、再跑。直接 `xcodebuild test` 在干净检出上会找到 0 个测试——这是 Xcode 的已知怪癖，不是项目的问题。

## 已知限制

- ad-hoc 签名、未公证，首次打开 macOS 会有警告。
- 通知仅在 App 运行期间生效（本地通知）。
- 应用内更新的安装需要挂载 DMG；若沙盒阻止，会降级为在 Finder 中打开 DMG 手动安装。

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

[GPL-3.0](LICENSE)。可以自由使用、修改、fork——任何分发的衍生版本必须保持开源。

明确限制：

- ✅ 个人使用、学习、修改、fork
- ✅ 以 GPL-3.0 协议开源发布修改版
- ❌ 将本项目的任何部分（包括 `MacDLCore` 引擎）以闭源形式集成进商业软件并分发
- ❌ 将本项目的代码或修改版作为闭源产品对外销售

违反上述条款将被视为侵犯著作权，作者保留追究法律责任的权利。
