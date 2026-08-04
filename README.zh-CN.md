# MacDL

一个常驻菜单栏的 macOS 高速下载管理器。它由一套基于 `URLSession` 的多线程分块下载引擎驱动，安静地在后台完成工作，不打扰你。

![screenshot](screenshot.png)

## 功能特性

- **菜单栏应用** — 关闭主窗口后继续在后台运行，下载不会中断（可设置关闭窗口时隐藏 Dock 图标）。
- **多线程分块下载** — 每个下载最多 8 条并行连接，所有分块共用同一个 `URLSession`，HTTP/2 可在单条连接上多路复用。
- **自动探测断点支持** — 启动时发送 `Range` 探测请求，获取真实文件大小并判断服务器是否支持 `206`；不支持 Range 的服务器自动降级为单流下载。
- **暂停 / 续传** — 下载先写入 `.macdl` 暂存文件，完成后改名。续传不重复下载已完成的字节（有界的 `Range` 请求头），断点状态在应用重启后依然有效。
- **服务器变更安全保护** — 下载过程中若服务器端文件大小发生变化，立即中止而非产出损坏文件。
- **限速** — 字节级令牌桶节流，既支持单任务限速，也支持全局默认限速。
- **优先下载** — 将一个任务置为优先，其余任务自动暂停；优先结束时自动恢复（状态跨重启保留）。
- **从剪贴板下载** — 直接在菜单栏提取链接；遇到重复链接会提示是否重新下载。
- **Finder 进度徽章** — 下载中的任务在 Dock 和 Finder 中显示实时进度。
- **系统通知** — 可分别开关开始 / 完成 / 失败通知，失败通知带「重新下载」操作按钮。
- **自动更新** — 检查 GitHub Releases，可一键下载并安装新版 DMG（安装永远需要手动点击，不会自动执行）。
- **中英双语界面** — 支持 English 与简体中文，运行时即时切换。
- **沙盒化** — 启用 App Sandbox，自定义下载目录通过安全作用域书签访问。

## 架构

项目分为两层：

1. **`MacDLCore`** — 独立 Swift Package，不依赖 AppKit。负责下载引擎：分块调度、限速、重试与续传。
2. **`MacDL`** — App 目标。SwiftUI 视图、业务逻辑、持久化、通知、更新与沙盒处理。

App 通过 `DownloadEngineProtocol` 协议驱动引擎，因此测试可以用假引擎替换真实引擎，完全不触碰网络与磁盘。

### 引擎层（`MacDLCore/Sources/MacDLCore`）

| 文件 | 职责 |
|------|------|
| `DownloadEngine.swift` | 门面。每个下载对应一个 `ChunkManager`，所有控制调用串行化处理。 |
| `DownloadEngineProtocol.swift` | 协议边界，App 层可注入测试替身。 |
| `ChunkManager.swift` | 协调单个下载：Range 探测、按连接上限调度分块、指数退避重试、单流降级。 |
| `ChunkDownloadTask.swift` | 单条 Range 请求。基于事件驱动写入（`NSCondition`，无轮询），带缓冲上限与背压。 |
| `ChunkSessionDelegate.swift` | 把 `URLSession` 的回调路由到对应的分块任务。 |
| `TokenBucket.swift` | 同一下载内所有分块共享的字节级限速桶。 |
| `Chunk.swift` | 一个字节区间及其进度；`Codable`，保证重启后状态可恢复。 |
| `EngineConstants.swift` | 调参集中地：超时、缓冲大小、重试退避、上报节奏。 |
| `DownloadError.swift` | 引擎抛给 App 层的错误（`cancelled`、`fileDeleted`、`rangeNotSatisfiable`、`fileChanged`、`httpStatus`、`network`）。 |
| `EngineLog.swift` | `os.Logger` 分类日志，同时镜像写入容器内的日志文件。 |

**一次下载的工作流程**

1. 探测请求携带 `Range: bytes=0-262143`，通过响应头 `Content-Range` 得知文件总大小，并判断服务器是否返回 `206`。
2. 文件按固定 256 KB 大小切分，并按 `maxConcurrent` 上限调度。
3. 失败的分块按指数退避重试（1s、2s、4s … 上限 10s，最多 3 次）；`429`/`5xx`/网络错误会重试，永久性错误不会。
4. 若服务器忽略 `Range`（返回 `200`），引擎降级为单流整文件下载，失败时快速重试一次。

引擎所有可变状态都限定在一条串行队列内，回调仍回到该队列，保证任何状态都不会被两个线程同时访问。

### App 层（`MacDL`）

App 围绕 `@Observable` 状态对象组织：

```
ContentView ──────────────► ContentViewModel ─────► DownloadService ──► DownloadStore
      │                            (视图状态)           (业务逻辑)         (列表 + 持久化)
      │                                                    │
      │               DownloadEngineCoordinator（引擎胶水、Finder 徽章、沙盒）
      │               PriorityDownloadCoordinator（优先下载状态机）
      └── DownloadListView / DownloadRow / NewDownloadView / SettingsView
```

| 文件 | 职责 |
|------|------|
| `App/MacDLApp.swift` | SwiftUI `App`、菜单栏附加、设置场景、单实例强制、退出前活动下载确认。 |
| `App/MenuBarContent.swift` | 菜单栏操作：从剪贴板下载、显示/隐藏窗口、关于、偏好设置、退出。 |
| `Features/Content/ContentViewModel.swift` | SwiftUI 面向的视图状态（选中项、过滤器），把调用转发给 `DownloadService`。 |
| `Features/Content/DownloadService.swift` | 下载生命周期：添加/暂停/续传/重试/重新下载/删除、等待队列、引擎完成处理、文件完整性检查。 |
| `Features/Content/DownloadStore.swift` | 下载列表与持久化的唯一数据源。 |
| `Features/Content/DownloadEngineCoordinator.swift` | 安装引擎回调、进度持久化节流、错误到本地化文案的映射。 |
| `Features/Content/PriorityDownloadCoordinator.swift` | 优先下载状态机（置顶、自动暂停其它、恢复）。 |
| `Features/Content/ProgressPublisher.swift` | 发布/更新 Finder 的 `NSProgress` 徽章并接管取消。 |
| `Models/Download.swift` | 下载模型；紧凑持久化（合并的已完成区间 + 部分分块续传点）。 |
| `Models/DownloadPath.swift` | `.macdl` 暂存文件与最终目标路径的唯一来源。 |
| `Models/AppConfig.swift` | 在沙盒下解析真实用户「下载」目录。 |
| `Services/DownloadPersistence.swift` | Application Support 下的 JSON 持久化、后台写入、旧数据迁移。 |
| `Services/DownloadNotifier.swift` | `UNUserNotificationCenter` 通知与「重新下载」操作。 |
| `Services/SettingsStore.swift` | `UserDefaults` 支撑的设置。 |
| `Services/SandboxAccess.swift` | 对用户自选目录的安全作用域访问。 |
| `Services/LanguageManager.swift` | 运行时语言切换（跟随系统 / English / 简体中文）。 |
| `Services/UpdateService.swift`、`UpdateModel.swift` | GitHub Releases 自动更新：检查、下载 DMG、安装并重启。 |
| `Services/LaunchAtLoginService.swift` | 通过 `SMAppService` 开机自启。 |
| `Services/DockIconManager.swift` | 窗口开关时隐藏/恢复 Dock 图标。 |
| `Features/Settings/*` | 设置面板：通用、下载、更新、通知。 |
| `Features/Content/NewDownloadView.swift`、`NewDownloadModel.swift` | 新建下载面板：粘贴/拖拽链接、每个任务独立线程数与限速、续传探测。 |

**下载生命周期**

```
添加 → 探测（状态 .active，显示「Preparing」）→ 分块调度
     → 完成 → 把 .macdl 改名为正式文件 → 通知
     → 暂停 → .paused → 续传（不重复下载已完成的字节）
     → 失败 → .error → 重试 / 重新下载 / 删除
```

每个下载与全局都有并发上限，超出部分进入等待队列；任务结束时会自动启动下一个等待中的下载。

**持久化**

分块进度不存全量分块数组，而是紧凑存储：合并的连续已完成区间 + 各分块续传偏移。这样一份完成 100 GB 的文件只占几个区间条目，而不是约 40 万个分块条目。进度节流保存（每 5 秒一次），退出时立即落盘。

## 系统要求与构建

- macOS 26.5 及以上（引擎包声明的最低版本为 macOS 15）。
- 带 macOS 26 SDK 的 Xcode。
- 无外部依赖。

```sh
# 打开并在 Xcode 中运行
open MacDL.xcodeproj
# scheme: MacDL

# 引擎包测试
cd MacDLCore && swift test

# App 测试
xcodebuild test -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## 目录结构

```
MacDL.xcodeproj        Xcode 工程（App + App 测试）
MacDL/                 App 目标
  App/                 App 入口、菜单栏、关于窗口
  Features/Content/    下载界面、视图模型、服务、协调器
  Features/Settings/   设置面板
  Models/              下载模型、路径、格式化、过滤器
  Components/          共享 SwiftUI 组件
  Services/            持久化、通知、更新、沙盒、语言
  Resources/           Localizable.xcstrings、资源目录
MacDLCore/             引擎 Swift Package
  Sources/MacDLCore/   引擎实现
  Tests/               引擎测试（Swift Testing + 假 URLProtocol）
MacDLTests/            App 测试（XCTest + 假引擎）
.github/workflows/     CI：引擎测试 + App 构建 + App 测试
```

## 测试

共 180 个测试，分两套：

- **引擎（30）** — 使用 Swift Testing 配合假 `URLProtocol`，不发起真实网络请求。覆盖分块完整性、暂停/续传、限速、退避、单流降级与 Range 边界情况。
- **App（150）** — 使用 XCTest 配合假引擎，不触碰真实磁盘与通知中心。覆盖下载生命周期、优先流程、重复策略、持久化往返、更新状态机与本地化。

CI（GitHub Actions）先跑引擎测试，再构建并测试 App。

## 本地化

界面文案集中在 `MacDL/Resources/Localizable.xcstrings`（英文为源语言，含简体中文翻译）。`LanguageManager` 决定使用语言（跟随系统或手动指定），语言切换时所有文案响应式刷新。错误信息持久化的是目录键（catalog key），因此切换语言后仍会正确重新本地化。

## 许可证

[GPL-3.0](LICENSE)
