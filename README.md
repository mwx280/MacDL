<div align="center">

<img src="icon.png" width="128" alt="MacDL">

# MacDL

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()
[![CI](https://github.com/mwx280/MacDL/actions/workflows/ci.yml/badge.svg)](https://github.com/mwx280/MacDL/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v0.2.0%20Preview-orange.svg)](https://github.com/mwx280/MacDL/releases)
[![Size](https://img.shields.io/badge/app-5.5%20MB-lightgrey.svg)]()

</div>

A download manager that lives in your macOS menu bar. Under the hood it runs a
multi-threaded, chunked download engine built on `URLSession`, so downloads are
fast and the app quietly stays out of your way.

![screenshot](screenshot.png)

## Features

- **Menu bar resident**: closing the main window keeps the app running and
  downloads going. Optionally hides the Dock icon when the window closes.
- **Multi-threaded chunked downloads**: up to 8 parallel connections per
  download; all chunks share a single `URLSession`, so HTTP/2 can reuse one
  connection. An "Adaptive" connection mode (default) picks the starting count
  from the file size and adapts it to observed throughput — it adds connections
  only while they keep making the transfer faster and converges at the best count.
- **Automatic resume detection**: a `Range` probe at start discovers the real
  file size and whether the server answers `206`. Servers without Range support
  automatically fall back to a single-threaded download.
- **Pause / resume**: downloads go to a `.macdl` staging file that is renamed
  on completion. Resume uses bounded `Range` headers, so already-downloaded
  bytes are never re-fetched, and the state survives restarts.
- **Server change protection**: if the file size on the server changes
  mid-download, the task aborts instead of producing a corrupt file.
- **Speed limiting**: a byte-level token-bucket throttle, per task and as a
  global default.
- **Priority downloads**: promote one task and the others auto-pause; they are
  restored when priority ends (the state survives restarts).
- **Download from clipboard**: grab links straight from the menu bar. Duplicate
  links ask whether to re-download.
- **Finder progress**: active tasks show live progress in the Dock and Finder.
- **Notifications**: separate toggles for started / completed / failed, with a
  "Redownload" action on failures.
- **Auto-update**: checks GitHub Releases and can download and install a new
  DMG with one click (installation is never automatic).
- **Bilingual UI**: English and 简体中文, switchable at runtime.
- **Sandboxed**: App Sandbox enabled, with security-scoped bookmarks for custom
  download folders.

## Architecture

The project is split into two layers:

1. **`MacDLCore`**: a standalone Swift Package with no AppKit dependency. The
   download engine lives here — chunk scheduling, speed limiting, retries and
   resume.
2. **`MacDL`**: the app itself. SwiftUI views, business logic, persistence,
   notifications, updates and sandbox handling.

The app drives the engine through the `DownloadEngineProtocol`, so tests can
swap in a fake engine and never touch the network or disk.

### Engine (`MacDLCore/Sources/MacDLCore`)

| File | Role |
|------|------|
| `DownloadEngine.swift` | Facade. One `ChunkManager` per download; every control call goes through a single serial queue. |
| `DownloadEngineProtocol.swift` | Protocol boundary so tests can inject a fake. |
| `ChunkManager.swift` | Coordinates one download: Range probe, chunk scheduling up to the connection cap, retries with exponential backoff, single-thread fallback when Range is unsupported. |
| `ChunkDownloadTask.swift` | One range request. Event-driven writer (`NSCondition`, no polling) with a bounded buffer and backpressure. |
| `ChunkSessionDelegate.swift` | Routes `URLSession` delegate callbacks to the owning chunk task. |
| `TokenBucket.swift` | The speed-limit bucket shared by all chunks of a download. |
| `Chunk.swift` | A byte range with progress; `Codable` so state survives restart. |
| `EngineConstants.swift` | Central tuning knobs: timeouts, buffer sizes, retry backoff, reporting cadence. |
| `DownloadError.swift` | Errors the engine reports to the app: `cancelled`, `fileDeleted`, `rangeNotSatisfiable`, `fileChanged`, `httpStatus`, `network`. |
| `EngineLog.swift` | `os.Logger` categories, mirrored to a log file inside the container. |

**How a download runs**

1. A probe request with `Range: bytes=0-262143` reveals the total file size
   from the `Content-Range` response header and whether the server returns
   `206`.
2. The file is split into fixed 256 KB chunks and scheduled up to the
   `maxConcurrent` cap.
3. Failed chunks retry with exponential backoff (1s, 2s, 4s … capped at 10s, at
   most 3 attempts). `429`, `5xx` and network errors are retried; permanent
   errors are not.
4. If the server ignores the Range header (returns `200`), the engine falls
   back to a whole-file single-threaded download, retrying once quickly on
   failure.

All engine state lives on one serial queue and callbacks return to it, so no
state is ever touched by two threads at once.

### App (`MacDL`)

The app is organised around `@Observable` state objects:

```
ContentView ──────────────► ContentViewModel ─────► DownloadService ──► DownloadStore
      │                            (view state)         (business logic)   (list + persistence)
      │                                                    │
      │               DownloadEngineCoordinator (engine glue, Finder badge, sandbox)
      │               PriorityDownloadCoordinator (priority state machine)
      └── DownloadListView / DownloadRow / NewDownloadView / SettingsView
```

| File | Role |
|------|------|
| `App/MacDLApp.swift` | App entry point. SwiftUI `App`, menu bar icon, settings window, single-instance enforcement, quit-with-downloads guard. |
| `App/MenuBarContent.swift` | Menu bar actions: download from clipboard, show/hide window, about, preferences, quit. |
| `Features/Content/ContentViewModel.swift` | SwiftUI-facing view state (selection, filters); forwards real work to `DownloadService`. |
| `Features/Content/DownloadService.swift` | Download lifecycle: add/pause/resume/retry/redownload/delete, waiting queue, post-completion handling, file-integrity checks. |
| `Features/Content/DownloadStore.swift` | Single source of truth for the download list; reads and writes persistence. |
| `Features/Content/DownloadEngineCoordinator.swift` | Registers engine callbacks, throttles progress saves, maps errors to localized text. |
| `Features/Content/PriorityDownloadCoordinator.swift` | Priority state machine: promote, auto-pause the others, restore when done. |
| `Features/Content/ProgressPublisher.swift` | Publishes and updates the Finder `NSProgress` badge; owns cancellation. |
| `Models/Download.swift` | Download model; compact persistence (merged completed ranges + per-chunk resume points). |
| `Models/DownloadPath.swift` | Single place that decides the `.macdl` staging and final destination paths. |
| `Models/AppConfig.swift` | Resolves the real user Downloads folder under the sandbox. |
| `Services/DownloadPersistence.swift` | Stores the list as JSON in Application Support, writes in the background, migrates legacy data. |
| `Services/DownloadNotifier.swift` | System notifications and the "Redownload" action. |
| `Services/SettingsStore.swift` | `UserDefaults`-backed settings. |
| `Services/SandboxAccess.swift` | Security-scoped access to folders the user picks. |
| `Services/LanguageManager.swift` | Runtime language switching (system / English / 简体中文). |
| `Services/UpdateService.swift`, `UpdateModel.swift` | GitHub Releases auto-update: check, download the DMG, install and relaunch. |
| `Services/LaunchAtLoginService.swift` | Launch at login via `SMAppService`. |
| `Services/DockIconManager.swift` | Hides/restores the Dock icon as windows open and close. |
| `Features/Settings/*` | Settings panes: General, Download, Update, Notifications. |
| `Features/Content/NewDownloadView.swift`, `NewDownloadModel.swift` | New-download sheet: paste/drop links, per-task threads and limits, resume probing. |

**Download lifecycle**

```
add → probe (status "active", UI shows Preparing) → chunk scheduling
    → complete → rename .macdl → real file → notification
    → pause → paused → resume (already-downloaded bytes are not re-fetched)
    → fail → error → retry / redownload / delete
```

Per-download and global concurrency caps queue up the overflow; when a task
finishes, the next waiting download starts automatically.

**Persistence**

Chunk progress is not stored as the full chunk array. Instead it is compacted
into merged contiguous completed ranges plus per-chunk resume offsets, so a
finished 100 GB file persists as a handful of ranges instead of roughly 400,000
chunk entries. Progress is saved every 5 seconds and flushed immediately on
quit.

## Requirements and build

- macOS 15 or later.
- Xcode with a macOS 15 SDK or later.
- No external dependencies.

```sh
# Open and run in Xcode
open MacDL.xcodeproj
# scheme: MacDL

# Engine package tests
cd MacDLCore && swift test

# App tests
xcodebuild test -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## Project layout

```
MacDL.xcodeproj        Xcode project (app + app tests)
MacDL/                 App target
  App/                 Entry point, menu bar, about window
  Features/Content/    Download UI, view models, services, coordinators
  Features/Settings/   Settings panes
  Models/              Download model, paths, formatters, filters
  Components/          Shared SwiftUI components
  Services/            Persistence, notifications, updates, sandbox, language
  Resources/           Localizable.xcstrings, asset catalog
MacDLCore/             Engine Swift Package
  Sources/MacDLCore/   Engine implementation
  Tests/               Engine tests (Swift Testing + fake URLProtocol)
MacDLTests/            App tests (XCTest + fake engine)
.github/workflows/     CI: engine tests + app build + app tests
```

## Testing

180 tests across two suites:

- **Engine (30)**: Swift Testing against a fake `URLProtocol`, no real network.
  Covers chunk integrity, pause/resume, throttling, backoff, single-thread
  fallback and Range edge cases.
- **App (150)**: XCTest with a fake engine, no real disk or notification
  center. Covers the download lifecycle, priority flow, duplicate policy,
  persistence round trips, the update state machine and localization.

CI (GitHub Actions) runs the engine tests first, then builds and tests the
app.

## Localization

All UI strings live in `MacDL/Resources/Localizable.xcstrings` (English as the
source language, with 简体中文 translations). `LanguageManager` picks the
language (follow the system or a forced choice) and the UI refreshes
immediately on change. Errors persist the string key, so they re-localize
correctly even after a language switch.

## License

[GPL-3.0](LICENSE) — use it, change it, but keep derivatives open source.

**Explicit restrictions:**

- Personal use, learning, modification, and forking are completely free
- Publishing your modified version under GPL-3.0 is completely free
- Integrating any part of this project (including the `MacDLCore` engine) into
  closed-source commercial software and distributing it is strictly prohibited
- Selling this code or modified versions as a closed-source product is strictly
  prohibited

Violating the above will be treated as copyright infringement, and the author
reserves the right to pursue legal action.
