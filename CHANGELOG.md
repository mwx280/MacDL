# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- App icon: macOS-style rounded-rect tile with a blue gradient and download
  arrow, shipped as a full multi-size `AppIcon.icns` set.

### Fixed

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
- Test-detection is centralized in `ProcessInfo.isRunningTests` instead of
  duplicated `XCTestConfigurationFilePath` env checks.
- New-download sheet: the previously dead `browseFolder()` folder picker is now
  wired to a button, so per-batch custom folders (with security-scoped
  bookmarks) actually work.
- Removed a duplicated `import Foundation` in `AppConfig`.

### Localization

- Added missing catalog entries: `HTTP %ld`, `Invalid URL`, `Version %@ (build %@)`,
  and filled in the empty `OK` key (zh: 确定), so they no longer fall back to the
  English key in Chinese.
- Localized two hardcoded settings strings: the "Launch at Login" alert title and
  its "OK" button.
- Error messages now persist a catalog key (`Download.errorKey`) instead of only a
  pre-localized string, so failed-download text re-localizes when the app language
  changes. Legacy persisted English messages are migrated to keys on load and the
  download row / notifications / duplicate dialog render through it.

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
