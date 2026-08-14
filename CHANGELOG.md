# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Adaptive connection mode (default on): the connection (thread) setting gains
  an "Adaptive" option that picks the starting count from the probed file size
  and adapts it to observed throughput — IDM-style. It probes one connection at
  a time, keeps additions only when speed grows, and converges at the best count.
  Available in Settings, the New Download sheet and the per-row thread menu.
  - The Range probe doubles as a latency and single-connection speed sample:
    high RTT and a low measured rate raise the starting count immediately,
    so per-connection-throttled or high-latency servers get a fast head start
    instead of a slow +1 climb.
  - A burst of retryable failures (429/5xx/network) freezes upward probing and
    drops back to the best known count, so rate-limited servers are not made
    worse.
  - Strong throughput gains make the probe jump +2/+3 connections instead of
    one, converging faster on large files.

### Changed

- The launch notification is no longer posted at startup; the "Launch
  Notification" settings toggle is kept but currently has no effect.
- Settings window redesigned: rows gain inline description subtitles, icons get
  per-row colors, and the window auto-sizes to the active pane. Navigation uses
  the native system `TabView` instead of a self-drawn pill tab bar.

### Fixed

- Engine no longer hangs in the probing phase when a download fails with a pure
  network error (no HTTP response): after retries are exhausted the failure is
  reported instead of leaving the task stuck at "Preparing" forever.
- Engine now completes a resumed download whose persisted chunks are already
  all complete, so a crash between the last chunk write and the rename does not
  strand the task at 100%.

## [0.2.0] - 2026-08-05

Second preview release.

### Added

- App icon: macOS-style rounded-rect tile with a blue gradient and download
  arrow, shipped as a full multi-size `AppIcon.icns` set.
- New Download sheet redesign:
  - Paste-focused drop zone with clipboard detection and drag-and-drop URLs
  - Per-task thread count and speed limit (non-resumable tasks locked to a
    single thread)
  - Hover-to-remove tasks, invalid-link feedback, already-queued and
    will-be-renamed hints
- Update checking from GitHub Releases (preview channel):
  - Settings pane with current version, detect-updates button, download progress
    and install-and-restart
  - "Auto check and download updates" toggle (default on) checks at launch
- Notification settings pane:
  - Per-type toggles for start / completed / failed / redownload alerts
  - When notification permission is missing, the pane deep-links to System
    Settings instead of showing the toggles
- Launch in Background setting (default on): the app starts with only the menu
  bar icon and no main window
- Launch at Login is enabled automatically on first launch

### Changed

- Download chunk state is persisted compactly: merged completed byte ranges plus
  partial resume points instead of the full chunk array (big files shrink from
  hundreds of thousands of entries to a few ranges)
- Download lifecycle (add / pause / resume / retry / redownload / delete /
  priority / completion) extracted into `DownloadService`; `ContentViewModel`
  keeps only view state
- New-download parsing, validation and resume probing extracted into
  `NewDownloadModel` (unit-tested)
- App-side shared state consolidated behind `@MainActor`, removing scattered
  locks (`DownloadNotifier`, `DownloadEngineCoordinator`, `SandboxAccess`,
  `ProgressPublisher`)
- Engine chunk writer is event-driven (`NSCondition`) instead of polling, and
  the backpressure path no longer busy-sleeps
- Settings panes split into per-file views
- Localized strings update reactively (dropped the `.id(refresh)` view rebuild)
- Migrated to the Swift 6 language mode with explicit actor isolation
  (`@MainActor`, `@Sendable`, `nonisolated`) instead of the approachable-
  concurrency default isolation
- Deployment target lowered from macOS 26.5 to macOS 15

### Fixed

- Downloads served without a `Content-Length` (e.g. GitHub archive redirects) no
  longer sit at a fake 100%: the bar shows indeterminate progress while the size
  is unknown and the real total is backfilled on completion
- Indeterminate progress animation now stops once a download errors
- Resuming a non-resumable (single-stream) download resets its progress, matching
  the engine's restart-from-zero behavior
- `FileHandle.synchronizeFile` no longer crashes the app when the staging file
  is removed mid-cleanup
- Flaky parallel-test-host crashes: `DownloadNotifier`, `DownloadEngineCoordinator`
  and `SandboxAccess` serialize their shared mutable state, and
  `ContentViewModel` no longer registers global observers / a file-check timer
  per instance (moved to `startAppServices()`, app-only). Parallel app tests now
  run reliably, so CI no longer needs `-parallel-testing-enabled NO`.
- `.other` file-type filter no longer swallows known types: `.ttf`/`.otf` count
  as documents, `.iso`/`.img`/`.exe`/`.msi` as archives, and `.torrent` is
  recognized (not "Other"); `allKnown` now covers every extension the app gives
  an icon/color.
- `fileTypeColor` no longer falls back to `.secondary` for text, font and
  torrent files.
- `%lld` format-string/argument type mismatches fixed in `DownloadRow` and
  `DialogPresenter`.
- New-download sheet: the previously dead `browseFolder()` folder picker is now
  wired to a button, so per-batch custom folders (with security-scoped
  bookmarks) actually work.
- Removed a duplicated `import Foundation` in `AppConfig`.
- Menu bar "Show Window" no longer raises a previously opened hidden settings
  window
- No lingering Dock icon when the app launches in the background
- Opening Preferences from the menu bar now fronts the settings window

### Localization

- Added missing catalog entries: `HTTP %ld`, `Invalid URL`, `Version %@ (build %@)`,
  and filled in the empty `OK` key (zh: 确定), so they no longer fall back to the
  English key in Chinese.
- Localized the "Launch at Login" alert title and its "OK" button.
- Error messages now persist a catalog key (`Download.errorKey`) instead of only a
  pre-localized string, so failed-download text re-localizes when the app language
  changes. Legacy persisted English messages are migrated to keys on load and the
  download row / notifications / duplicate dialog render through it.
- Added catalog entries for update checking, notification settings, the new
  download sheet and launch-in-background.

### Testing

- App tests grew from 86 to 150; engine tests from 21 to 30 (total 180).
- Swift 6 migration: every test suite is explicitly `@MainActor`, and
  timing-sensitive assertions poll for their condition instead of fixed sleeps.
- New suites: `NewDownloadModel` (parsing / probing), `DuplicatePolicy`
  (duplicate-add decisions), `UpdateModel` (version compare + state machine),
  chunk compact-persistence round trips, notification toggle gates, bulk delete
  and file-integrity handling.

## [0.1.0] - 2026-08-02

Initial preview release.

### Added

- Menu-bar macOS download manager (sandboxed, GPL-3.0)
- Multi-threaded chunked engine built on URLSession (up to 8 connections)
  - Range probe detects total size and server `206` support
  - Falls back to single-stream when the server lacks Range support
  - Chunk retry with exponential backoff; permanent errors reported cleanly
- Pause / resume:
  - Downloads to a `.macdl` staging file, renamed to the real name on completion
  - Resumes with bounded `Range` headers (no bytes re-fetched, survives restarts)
  - Detects when the server file changed mid-download and aborts instead of corrupting
- Byte-level token-bucket speed limiting (per task and global)
- Download from Clipboard (menu bar) with duplicate re-download prompt
- Priority downloads (auto-pause / resume other tasks, persists across restart)
- System notifications:
  - Download start / complete / failure
  - Dedicated banner when a priority download gives up after retries
- App Sandbox with security-scoped bookmarks for custom folders
- Menu-bar app behaviors: launch at login, hide Dock icon when the window closes
- Bilingual UI (English / 简体中文)

### Changed

- Engine lives in a standalone Swift Package `MacDLCore` (no AppKit dependency)
- App depends on the engine through a protocol, with dependency injection

### Security

- App Sandbox enabled with minimal entitlements (network client, user-selected
  read-write, app-scoped bookmarks, downloads read-write)

### Testing

- 107 tests: 21 engine (fake URLProtocol, no server) + 86 app (fake engine)
- GitHub Actions CI: engine `swift test` + app `xcodebuild test`
