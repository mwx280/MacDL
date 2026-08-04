# MacDL

A fast, sandboxed download manager for macOS that lives in your menu bar. It
drives a multi-threaded, chunked download engine built on `URLSession`, and
stays out of the way while it works.

![screenshot](screenshot.png)

## Features

- **Menu-bar app** — keeps running when the main window closes; downloads
  continue in the background (Dock icon can be hidden on close).
- **Multi-threaded chunked downloads** — up to 8 parallel connections per
  download, all sharing one `URLSession` so HTTP/2 multiplexes on a single
  connection.
- **Automatic resume detection** — a `Range` probe discovers the real file size
  and whether the server honours `206`; servers without Range support fall back
  to a single-stream download.
- **Pause / resume** — downloads to a `.macdl` staging file that is renamed on
  completion. Resuming re-fetches nothing (bounded `Range` headers), and state
  survives app restarts.
- **Safe on server changes** — if the server file changes size mid-download,
  the download aborts instead of producing a corrupt file.
- **Speed limits** — byte-level token-bucket throttle, both per task and as a
  global default.
- **Priority downloads** — promote one task; the others auto-pause and are
  restored when priority ends (state survives restart).
- **Download from clipboard** — grab links straight from the menu bar, with a
  re-download prompt for duplicates.
- **Finder progress badges** — active downloads show live progress in the Dock
  and Finder.
- **System notifications** — configurable alerts for started / completed /
  failed downloads, plus a "Redownload" action.
- **Auto-update** — checks GitHub Releases and can download + install a new
  DMG with one click (install is never automatic).
- **Bilingual UI** — English and 简体中文, switchable at runtime.
- **Sandboxed** — App Sandbox with security-scoped bookmarks for custom
  download folders.

## Architecture

The project is split into two layers:

1. **`MacDLCore`** — a standalone Swift Package with no AppKit dependency. It
   owns the download engine: chunk scheduling, throttling, retries, resume.
2. **`MacDL`** — the app target. SwiftUI views, business logic, persistence,
   notifications, updates and sandbox handling.

The app drives the engine through `DownloadEngineProtocol`, so tests can swap
in a fake engine without touching the network or disk.

### Engine (`MacDLCore/Sources/MacDLCore`)

| File | Role |
|------|------|
| `DownloadEngine.swift` | Facade. One `ChunkManager` per download; every control call is serialized. |
| `DownloadEngineProtocol.swift` | Protocol boundary so the app can inject a test double. |
| `ChunkManager.swift` | Orchestrates one download: range probe, chunk scheduling up to the connection cap, retry with exponential backoff, single-stream fallback. |
| `ChunkDownloadTask.swift` | One range request. Event-driven writer (`NSCondition`, no polling) with a bounded buffer and backpressure. |
| `ChunkSessionDelegate.swift` | Routes `URLSession` delegate callbacks to the owning task. |
| `TokenBucket.swift` | Byte-level throttle shared by all chunks of a download. |
| `Chunk.swift` | A byte range with progress; `Codable` so state survives restart. |
| `EngineConstants.swift` | Tuning knobs: timeouts, buffer sizes, retry backoff, reporting cadence. |
| `DownloadError.swift` | Engine errors surfaced to the app (`cancelled`, `fileDeleted`, `rangeNotSatisfiable`, `fileChanged`, `httpStatus`, `network`). |
| `EngineLog.swift` | `os.Logger` categories mirrored to a log file in the container. |

**How a download works**

1. A probe request sends `Range: bytes=0-262143`. Its `Content-Range` header
   reveals the total size and whether the server answers with `206`.
2. The file is split into fixed 256 KB chunks and scheduled up to the
   `maxConcurrent` cap.
3. Failed chunks retry with exponential backoff (1s, 2s, 4s … capped at 10s,
   max 3 attempts); `429`/`5xx`/network errors are retried, permanent errors are
   not.
4. If the server ignores `Range` (returns `200`), the engine switches to a
   single whole-file stream with one quick retry on failure.

All engine state is confined to a serial queue; callbacks re-enter it, so
nothing is touched from two threads at once.

### App (`MacDL`)

The app is organised around the `@Observable` state objects:

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
| `App/MacDLApp.swift` | SwiftUI `App`, menu bar extra, settings scene, single-instance enforcement, quit-with-active-downloads guard. |
| `App/MenuBarContent.swift` | Menu bar actions: download from clipboard, show/hide window, about, preferences, quit. |
| `Features/Content/ContentViewModel.swift` | SwiftUI-facing state (selection, filters); forwards calls to `DownloadService`. |
| `Features/Content/DownloadService.swift` | Download lifecycle: add/pause/resume/retry/redownload/delete, waiting queue, engine completion handling, file-integrity checks. |
| `Features/Content/DownloadStore.swift` | Single source of truth for the download list + persistence. |
| `Features/Content/DownloadEngineCoordinator.swift` | Installs engine handlers, owns progress persistence throttling, maps errors to localized text. |
| `Features/Content/PriorityDownloadCoordinator.swift` | Priority state machine (promote, auto-pause others, restore). |
| `Features/Content/ProgressPublisher.swift` | Publishes/updates Finder `NSProgress` badges, wires cancel. |
| `Models/Download.swift` | Download model; compact persistence (merged completed ranges + partial resume points). |
| `Models/DownloadPath.swift` | Single source for the `.macdl` staging / final destination paths. |
| `Models/AppConfig.swift` | Resolves the real user Downloads folder under the sandbox. |
| `Services/DownloadPersistence.swift` | JSON persistence in Application Support, background writes, legacy migration. |
| `Services/DownloadNotifier.swift` | `UNUserNotificationCenter` notifications + redownload action. |
| `Services/SettingsStore.swift` | `UserDefaults`-backed settings. |
| `Services/SandboxAccess.swift` | Security-scoped access to user-picked folders. |
| `Services/LanguageManager.swift` | Runtime language switching (system / English / 简体中文). |
| `Services/UpdateService.swift`, `UpdateModel.swift` | GitHub Releases auto-update: check, download DMG, install + relaunch. |
| `Services/LaunchAtLoginService.swift` | Launch at login via `SMAppService`. |
| `Services/DockIconManager.swift` | Hides/restores the Dock icon as windows open/close. |
| `Features/Settings/*` | Settings panes: General, Download, Update, Notifications. |
| `Features/Content/NewDownloadView.swift`, `NewDownloadModel.swift` | New-download sheet: paste/drag links, per-task threads + limits, resume probing. |

**Download lifecycle**

```
add → probe (status .active, "Preparing") → chunk scheduling
    → complete → rename .macdl → real file → notification
    → pause → .paused → resume (no bytes re-fetched)
    → fail → .error → retry / redownload / delete
```

A per-download and global concurrency cap keeps a waiting queue: when a task
finishes, the next waiting download starts automatically.

**Persistence**

Chunk progress is stored compactly instead of as a full chunk array: merged
contiguous completed ranges plus per-chunk resume offsets, so a finished 100 GB
file persists as a handful of ranges rather than ~400k entries. Progress is
saved throttled (every 5 s) and flushed immediately on quit.

## Requirements and build

- macOS 26.5+ (the engine package declares a macOS 15 baseline).
- Xcode with a macOS 26 SDK.
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
  App/                 App entry point, menu bar, about window
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

- **Engine (30)** — Swift Testing against a fake `URLProtocol`, no real network.
  Covers chunk integrity, pause/resume, throttling, backoff, single-stream
  fallback and range edge cases.
- **App (150)** — XCTest with a fake engine, no real disk or notification
  center. Covers the download lifecycle, priority flow, duplicate policy,
  persistence round trips, update state machine and localization.

CI (GitHub Actions) runs the engine tests, then builds and tests the app.

## Localization

UI strings live in `MacDL/Resources/Localizable.xcstrings` (English source,
简体中文 translation). `LanguageManager` picks the language (follow system, or a
forced choice) and every string re-renders reactively when it changes. Error
messages persist a catalog key so they re-localize even after a language switch.

## License

[GPL-3.0](LICENSE)
