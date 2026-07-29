# Aria2Desk 企业级架构重构方案

## 一、当前架构分析

### 1.1 目录结构

```
Aria2Desk/
├── App/
│   └── Aria2DeskApp.swift          # 369 行 —  App 入口 + AboutView + MenuBarContent
├── Components/
│   └── LocalizedText.swift          # 10 行 —  本地化文本组件 ✅ 干净
├── Features/
│   ├── Content/
│   │   ├── ContentView.swift        # 222 行 —  主视图（含 NewDownloadView）
│   │   ├── DownloadListView.swift   # 159 行 —  下载列表（含 DownloadRow）
│   │   └── SidebarItem.swift        # 27 行  —  侧栏筛选枚举 ✅ 干净
│   └── Settings/
│       └── SettingsView.swift       # 144 行 —  设置视图（含 Appearance 枚举）
├── Models/
│   ├── Download.swift               # 121 行 —  下载模型（含 mock 数据）
│   └── RPCConfig.swift              # 57 行  —  RPC 配置（混入 UserDefaults）
├── Resources/
│   └── Localizable.xcstrings
├── Services/
│   ├── Aria2RPCClient.swift         # 231 行 —  引擎管理 + RPC + 端口 + 目录
│   └── LanguageManager.swift        # 55 行  —  语言管理（含通知）
└── Aria2DeskTests/
    └── DownloadTests.swift
```

### 1.2 依赖关系图

```
Aria2DeskApp.swift
  ├── ContentView.swift
  │     ├── SidebarItem.swift
  │     ├── LocalizedText.swift  →  LanguageManager (@Environment)
  │     ├── DownloadListView.swift
  │     │     ├── LocalizedText.swift
  │     │     ├── Download.swift
  │     │     └── formatSpeed (duplicated)
  │     ├── Download.swift (mock 数据)
  │     ├── LanguageManager.shared (直接调用)
  │     ├── Aria2RPCClient.shared (直接调用)
  │     └── SettingsView.swift (仅为 Appearance 枚举)
  │
  ├── SettingsView.swift
  │     ├── LocalizedText.swift
  │     ├── LanguageManager (@Environment)
  │     └── Aria2RPCClient (@Environment)
  │
  ├── LanguageManager.swift
  └── Aria2RPCClient.swift → RPCConfig.swift
```

### 1.3 核心问题清单

| # | 问题 | 严重程度 | 说明 |
|---|---|---|---|
| 1 | **App.swift 过度臃肿** | 🔴 | 369 行混合 App 生命周期 + About 弹窗 + 终端彩蛋 |
| 2 | **Logic in View** | 🔴 | pause/resume/delete 业务逻辑直接写在 ContentView |
| 3 | **无协议抽象** | 🔴 | LanguageManager / Aria2RPCClient 无 protocol，无法 mock |
| 4 | **全局单例** | 🟡 | `shared` 无处不在，测试困难 |
| 5 | **重复格式化代码** | 🟡 | `formatSpeed` 在两个文件重复定义 |
| 6 | **DownloadStatus 重复 switch** | 🟡 | statusIcon/statusColor/statusKey 四遍遍历 |
| 7 | **跨 Feature 依赖** | 🟡 | Appearance 定义在 Settings, ContentView 跨目录引用 |
| 8 | **UserDefaults 混入 Model** | 🟡 | RPCConfig 读写 UserDefaults，隐式副作用 |
| 9 | **Mock 数据在 Model** | 🟢 | Download.mock 在生产代码中，应与业务分离 |
| 10 | **Raw JSON 序列化** | 🟢 | JSON-RPC 用 `[String:Any]` + JSONSerialization，类型不安全 |

---

## 二、目标架构

### 2.1 架构层次

```
┌──────────────────────────────────────────────────────────────────┐
│                       App Layer                                  │
│  Aria2DeskApp.swift     (仅场景声明)                              │
│  MenuBarContent.swift   (独立提取)                                │
│  AboutView.swift        (独立提取)                                │
└───────────────────────────────┬──────────────────────────────────┘
                                │
┌───────────────────────────────┼──────────────────────────────────┐
│                   Feature Layer                                  │
│                                                                  │
│  Content/                      Settings/                         │
│  ├─ ContentView.swift          ├─ SettingsView.swift             │
│  ├─ ContentViewModel.swift     ├─ GeneralPane.swift              │
│  ├─ DownloadListView.swift     ├─ DownloadPane.swift             │
│  ├─ DownloadRow.swift          └─ Appearance.swift  (提取独立)  │
│  ├─ DownloadRowViewModel.swift                                   │
│  └─ SidebarItem.swift                                             │
└───────────────────────────────┼──────────────────────────────────┘
                                │
┌───────────────────────────────┼──────────────────────────────────┐
│                   Service Layer                                   │
│                                                                  │
│  Protocols:                    Implementations:                  │
│  ├─ LanguageServiceProtocol   ├─ LanguageManager.swift           │
│  ├─ EngineServiceProtocol     ├─ Aria2Engine.swift  (从 RPCClient│
│  ├─ RPCTransportProtocol      ├─ RPCTransport.swift  拆分)      │
│  ├─ PortAllocatorProtocol     ├─ PortAllocator.swift            │
│  └─ SettingsStoreProtocol     └─ SettingsStore.swift  (新增)    │
└───────────────────────────────┼──────────────────────────────────┘
                                │
┌───────────────────────────────┼──────────────────────────────────┐
│                   Model Layer                                     │
│                                                                  │
│  Download.swift            (纯数据结构)                           │
│  DownloadStatus+Display.swift (显示逻辑扩展)                     │
│  RPCConfig.swift           (无 UserDefaults)                     │
│  Formatters.swift          (formatSpeed/Size 统一)              │
│  PreviewContent.swift      (mock 数据移出)                       │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 目标目录结构

```
Aria2Desk/
├── App/
│   ├── Aria2DeskApp.swift        # 仅场景声明 + 静态方法
│   ├── MenuBarContent.swift      # 菜单栏内容
│   └── AboutView.swift           # 关于页面（含彩蛋）
├── Components/
│   └── LocalizedText.swift       # ✅ 不变
├── Features/
│   ├── Content/
│   │   ├── ContentView.swift     # 纯视图，依赖 ViewModel
│   │   ├── ContentViewModel.swift # 业务逻辑
│   │   ├── DownloadListView.swift
│   │   ├── DownloadRow.swift     # 从 DownloadListView 拆分
│   │   ├── DownloadRowViewModel.swift
│   │   ├── NewDownloadView.swift # 从 ContentView 拆分
│   │   └── SidebarItem.swift     # ✅ 不变
│   └── Settings/
│       ├── SettingsView.swift
│       ├── GeneralPane.swift
│       ├── DownloadPane.swift
│       └── Appearance.swift      # 从 SettingsView 拆分
├── Models/
│   ├── Download.swift            # 纯数据，无 mock
│   ├── DownloadStatus+Display.swift  # 显示逻辑扩展
│   ├── DownloadStore.swift       # 可观察的状态容器
│   ├── RPCConfig.swift           # 无 UserDefaults
│   ├── Formatters.swift          # 格式化工具统一
│   └── PreviewContent.swift      # mock 数据（仅 Debug）
├── Resources/
│   └── Localizable.xcstrings     # ✅ 不变
├── Services/
│   ├── Protocols/
│   │   ├── LanguageServiceProtocol.swift
│   │   ├── EngineServiceProtocol.swift
│   │   ├── RPCTransportProtocol.swift
│   │   ├── PortAllocatorProtocol.swift
│   │   └── SettingsStoreProtocol.swift
│   ├── LanguageManager.swift     # 实现 LanguageServiceProtocol
│   ├── Aria2RPCClient.swift      # Facade，组合子服务
│   ├── Aria2Engine.swift         # 进程管理（从 Client 拆分）
│   ├── RPCTransport.swift        # JSON-RPC HTTP（从 Client 拆分）
│   ├── PortAllocator.swift       # 端口分配（从 Client 拆分）
│   ├── SettingsStore.swift       # UserDefaults 封装
│   └── ServiceLocator.swift      # 依赖注册
└── Aria2DeskTests/
    └── ...
```

---

## 三、分步执行计划

### Phase 1 — 基础设施（无功能影响）

| 步骤 | 改动 | 涉及文件 |
|---|---|---|
| 1.1 | 提取 `Appearance` 枚举到独立文件 | **新建** `Models/Appearance.swift` |
| 1.2 | 创建统一格式化工具 | **新建** `Models/Formatters.swift` |
| 1.3 | Mock 数据从 `Download.swift` 移出 | **新建** `Models/PreviewContent.swift`，修改 `Download.swift` |
| 1.4 | 创建协议目录 + 协议定义 | **新建** `Services/Protocols/*.swift` (5 个协议) |
| 1.5 | `RPCConfig` 去掉 UserDefaults | **修改** `RPCConfig.swift`，**新建** `Services/SettingsStore.swift` |
| 1.6 | 创建 ServiceLocator | **新建** `Services/ServiceLocator.swift` |

### Phase 2 — Service 层重构

| 步骤 | 改动 | 涉及文件 |
|---|---|---|
| 2.1 | 从 `Aria2RPCClient` 拆分 `PortAllocator` | **新建** `Services/PortAllocator.swift` |
| 2.2 | 从 `Aria2RPCClient` 拆分 `RPCTransport` | **新建** `Services/RPCTransport.swift` |
| 2.3 | 从 `Aria2RPCClient` 拆分 `Aria2Engine` | **新建** `Services/Aria2Engine.swift` |
| 2.4 | 重写 `Aria2RPCClient` 为 Facade | **重写** `Services/Aria2RPCClient.swift` |
| 2.5 | 实现 `SettingsStore` | **新建** `Services/SettingsStore.swift` |
| 2.6 | `LanguageManager` 实现协议 | **修改** `LanguageManager.swift` |

### Phase 3 — ViewModel 层引入

| 步骤 | 改动 | 涉及文件 |
|---|---|---|
| 3.1 | 创建 `DownloadStore`（可观察状态容器） | **新建** `Models/DownloadStore.swift` |
| 3.2 | 创建 `ContentViewModel` | **新建** `Features/Content/ContentViewModel.swift` |
| 3.3 | pause/resume/delete/filter/add 逻辑移入 ViewModel | `ContentViewModel.swift` |
| 3.4 | `ContentView` 改为纯视图 | **重写** `Features/Content/ContentView.swift` |
| 3.5 | 创建 `DownloadRowViewModel` | **新建** `Features/Content/DownloadRowViewModel.swift` |

### Phase 4 — 重复代码消除

| 步骤 | 改动 | 涉及文件 |
|---|---|---|
| 4.1 | `formatSpeed`/`formatSize` 合并到 `Formatters.swift` | 删除各 View 中的副本 |
| 4.2 | `statusIcon`/`statusColor`/`statusKey`/`progressTint` 合并到 `DownloadStatus` 扩展 | **新建** `Models/DownloadStatus+Display.swift` |
| 4.3 | `fileTypeIcon`/`fileTypeColor` 合并为一个方法 | 修改 `DownloadListView.swift` 或 `DownloadRowViewModel` |

### Phase 5 — 文件拆分

| 步骤 | 改动 | 涉及文件 |
|---|---|---|
| 5.1 | `AboutView` 从 `App.swift` 拆分 | **新建** `App/AboutView.swift` |
| 5.2 | `MenuBarContent` 从 `App.swift` 拆分 | **新建** `App/MenuBarContent.swift` |
| 5.3 | `NewDownloadView` 从 `ContentView.swift` 拆分 | **新建** `Features/Content/NewDownloadView.swift` |
| 5.4 | `DownloadRow` 从 `DownloadListView.swift` 拆分 | **新建** `Features/Content/DownloadRow.swift` |
| 5.5 | `GeneralPane`/`DownloadPane` 从 `SettingsView.swift` 拆分 | **新建** `Features/Settings/` 下 |

---

## 四、协议定义（Phase 1.4）

```swift
// Services/Protocols/LanguageServiceProtocol.swift
protocol LanguageServiceProtocol {
    var selectedLanguage: Language { get set }
    func localized(_ key: String) -> String
}

// Services/Protocols/EngineServiceProtocol.swift
protocol EngineServiceProtocol {
    var engineState: EngineState { get }
    var rpcPort: Int { get }
    func start()
    func stop()
    func restart()
}

// Services/Protocols/RPCTransportProtocol.swift
protocol RPCTransportProtocol {
    var status: RPCConnectionStatus { get }
    var config: RPCConfig { get }
    func testConnection() async -> Bool
    func call<T: Decodable>(method: String, params: [Any]) async throws -> T
}

// Services/Protocols/PortAllocatorProtocol.swift
protocol PortAllocatorProtocol {
    func findAvailablePort() -> Int
}

// Services/Protocols/SettingsStoreProtocol.swift
protocol SettingsStoreProtocol {
    var appearance: Appearance { get set }
    var maxConnections: Int { get set }
    var maxConcurrentDownloads: Int { get set }
    var secretToken: String { get set }
}
```

---

## 五、不变的文件（不动）

| 文件 | 原因 |
|---|---|
| `Components/LocalizedText.swift` | 干净，10 行，单职责 |
| `Features/Content/SidebarItem.swift` | 简洁，27 行，单职责 |
| `Resources/Localizable.xcstrings` | 纯数据，无重构必要 |
| 项目配置 / Build Settings | 非代码层面 |
| 单元测试文件 | 等架构定型后再更新 |

---

## 六、代码规范

```
├── View                  → 仅布局，无业务逻辑
├── ViewModel             → @Observable，业务逻辑 + 状态
├── Service / Protocol    → 基础设施，依赖注入
├── Model                 → 纯数据结构 / 扩展
├── Store                 → 可观察状态容器
└── Formatters / Utils    → 纯函数工具
```

### 依赖方向

```
App → Scene → View → ViewModel → Service(Protocol)
                                        ↓
                                   Implementation
```

严禁 View 直接调用 Service 实现类。所有跨层依赖面向协议。

---

## 七、时间估计

| Phase | 内容 | 预估文件数 | 预估改动行数 |
|---|---|---|---|
| 1 | 基础设施 | 6 新建 + 3 修改 | ~200 |
| 2 | Service 层 | 5 新建 + 2 重写 | ~400 |
| 3 | ViewModel 层 | 2 新建 + 1 重写 | ~300 |
| 4 | 重复代码消除 | 1 新建 + 3 修改 | ~100 |
| 5 | 文件拆分 | 6 新建 | ~180 |
| **合计** | | **~29 文件** | **~1180 行** |

预计 7-10 次 commit，每次可独立验证编译通过。
