# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-08-16

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
- Connection cap raised from 8 to 16 per download.
- Dynamic chunk sizing: the chunk size is chosen from the file size, probe
  latency and single-connection rate instead of a fixed 256 KB, so large files
  are not chopped into hundreds of thousands of chunks.
- Multi-source / mirror downloads: one download can span several mirrors.
  Chunks are scheduled across sources weighted by each one's measured
  throughput, and a failing source is cooled down while its chunks fail over to
  healthier sources.
- Per-host download history: bandwidth and RTT from past sessions seed the
  cold-start connection count and chunk size, so repeated sources start near
  their learned optimum without re-probing from scratch.
- Checksum verification: a download carrying an expected SHA-256 is verified
  before the staging file is renamed; a mismatch is discarded and reported as
  failed.
- Metalink support: `.metalink` / `.meta4` links expand into mirror URLs plus a
  checksum and file size.
- FTP downloads: `ftp://` links stream the whole file single-threaded, since
  FTP has no Range support.
- Global bandwidth pool: a shared token bucket caps the aggregate throughput
  across all downloads from the global speed-limit setting.
- Rate-limit degradation: a hard `429` drops the download to one connection,
  then re-probes upward with exponential backoff instead of staying stuck at a
  low count.
- Notification tap opens the main window: tapping a download notification now
  brings up the main window (previously it did nothing), and the window-opening
  logic is centralized so the menu bar "Show Window" action reuses it.
- Stall detection: a download whose aggregate throughput has been zero for a
  few seconds (silent network drop / half-open connection) now cancels and
  retries its active tasks instead of waiting out the URLSession request
  timeout, so a dropped link is detected and re-established much faster. The
  stall signal is kept separate from the adaptive connection policy and source
  cooldown, so a local network drop never reads as server-side stress.
  Detection is per-task (each request tracks its own idle clock), and a
  transport failure that schedules a retry with no recent bytes also flips the
  row into the retrying state — so turning Wi-Fi off mid-download shows
  "network interrupted, retrying" instead of a frozen 0 KB/s.
- Transport failures no longer freeze the adaptive connection policy: only
  server responses (429/5xx) count as stress signals for the failure freeze, so
  a Wi-Fi drop never leaves the engine unable to ramp connections back up after
  the link returns.
- Retrying state callback: the engine reports when a stalled transfer is being
  re-established, so the app can surface "network interrupted, retrying"
  instead of a frozen counter.
- Retrying row state: a download that is stalled and reconnecting shows a
  "Retrying" status with an orange highlight across the row (status badge, file
  icon, progress bar and background), and the speed slot is replaced by
  "Network interrupted, retrying..." instead of a frozen 0 KB/s.
- `macdl://` deep links: opening a `macdl://<url>` link (from a bookmarklet,
  Shortcut or the terminal) hands the URL to the app to add as a download;
  other URL opens are ignored.
- Selectable update channel: Settings gains a stable/preview picker, so a
  preview build follows preview releases and a stable build stays on stable.
- Completed-download notifications offer a "Show in Finder" action to reveal
  the finished file, and the duplicate-download notification action is tailored
  to the existing task's state (resume a paused one, retry a failed one, reveal
  a finished one; active/waiting tasks get no action).
- Launching in the background with active downloads posts a "MacDL is Running"
  notice, so a menu-bar launch doesn't go unnoticed while transfers continue.

### Fixed

- False "network interrupted" flashes under a speed limit: with many concurrent
  chunks sharing one token bucket, individual chunks could wait longer than the
  5s stall threshold between writes while the download kept progressing, and the
  stall watchdog cancelled them in a loop. Stall detection now only fires when
  the whole download has been silent for the timeout (a link drop stops
  everything; a speed limit does not), and each request's URLSession idle
  timeout is sized by the throttle rate so a throttled connection is never
  mistaken for a dead one.
- Adaptive connections no longer collapse to one connection during a normal
  download. The soft rate-limit detector that halved the connection count when a
  chunk was slower than the fastest recent one mistook the per-connection
  slowdown of a shared link for server throttling and kept halving (16→8→4→2→1).
  Soft throttling is now handled by the adaptive no-gain backoff instead, and the
  recovery backoff resets once a chunk completes so a transient `429` recovers
  in about a minute instead of growing toward ten minutes.
- Re-adding a download from the clipboard reports its actual state in the
  notification ("Download Completed" / "Paused Download" / "Failed Download")
  instead of always "Already in Download List".
- Adding a duplicate of a completed download now redownloads the existing task
  from scratch instead of creating a second entry: the finished file (and any
  stale staging) is removed and the same row restarts.

### Changed

- Adaptive connections now require a full five-sample throughput window below
  the historical best before rolling back. A brief bandwidth dip no longer
  drops connections, while a sustained slowdown still returns to the best known
  count; upward probe scoring remains responsive through the existing EMA.
- The learned best connection count is promoted only after a sustained,
  non-probing run above the previous best instead of on every speed spike. A
  transient spike at a high connection count can no longer rewrite the best
  count and dead-code the regression rollback, which previously left the
  download stuck at 16 connections on a high-latency link. The EMA smoothing
  coefficient was lowered so short speed spikes are damped, and the informed
  one-shot connection estimate now caps itself on very high RTT links where a
  slow single connection is bandwidth-delay-product limited rather than
  bandwidth limited.
- Adaptive connection circuit breaker: when the connection count keeps
  reversing direction, the engine locks to a conservative count instead of
  oscillating. The lock releases automatically after a quiet period so a
  network that recovered mid-download can climb back, and pausing, resuming,
  changing the connection mode or changing the speed limit still gives the
  download a fresh chance immediately.
- Source scheduling: an unmeasured mirror now serves only one trial chunk until
  its throughput is sampled, so a slow mirror no longer eats half the file at
  cold start. A persistently failing source backs off its cooldown
  exponentially (30s → 600s) instead of re-trying on a fixed cadence.
- Global connection budget: adaptive connections across all running downloads
  are capped at a shared budget (32, split evenly), so many simultaneous
  downloads no longer each climb to 16 and exhaust the network.
- Adaptive connections back off after repeated no-gain probes: when a speed
  limit or a saturated link caps throughput, the engine re-probes upward less
  and less often instead of churning, and skips the throttled cold-start
  estimate. Changing the global or per-download speed limit now re-converges the
  connection count immediately, and a throttled download no longer records its
  capped speed as per-host history.
- Network reachability: the engine now monitors the system link (`NWPathMonitor`).
  While it is down, downloads hold their chunks instead of burning retries
  against a dead network, show the retrying state, and resume automatically
  when the link returns. A `NetworkReachability` change callback is plumbed to
  the app so a disconnect policy (auto-pause, extended retry) can be built on
  top of it.
- Priority scheduling moved into the engine: `setPriorityDownload` pauses every
  other running download (remembered for restore) and starts a queued/paused
  priority download; `endPriority` restores them; `registerPriorityPaused`
  rebuilds the set after a restart. The app's `PriorityDownloadCoordinator` now
  only keeps the persisted flags and reflects the engine's pause/restore
  callbacks in the store.
- Download scheduling moved into the engine: a new `DownloadScheduler` owns the
  global concurrency cap and FIFO waiting queue. `DownloadEngine.schedule()` /
  `enqueue()` register downloads, and a completion or a grown cap promotes the
  next queued download via a promotion callback. The app's `DownloadService`
  no longer counts active downloads or promotes waiting ones itself; it hands
  new/redownloaded tasks to the scheduler and flips a promoted download to
  active. Pausing a download frees its slot without starting a replacement;
  deleting it cancels the queued/running task. Persisted waiting downloads are
  re-registered into the scheduler on launch, and changing the Max Downloads
  setting resizes the cap live. Waiting downloads also start after priority
  mode ends (previously they could stay stuck).
- Chunk-state reconstruction moved into the engine: `CompletedRange`/`PartialChunk`
  and the rebuild/ensure/merge logic now live in `MacDLCore` (`Chunk.swift`), and
  the app's `Download` model delegates to it. Single source of truth for chunk
  semantics; the persisted JSON format is unchanged.
- The launch notification is no longer posted at startup; the "Launch
  Notification" settings toggle is kept but currently has no effect.
- Removed all Swift 6 concurrency-isolation build warnings: the engine classes
  declare their serial-queue/lock guarantees with `@unchecked Sendable`,
  `Download`/`Chunk` are now `Sendable`, and main-queue observers/timers use
  `MainActor.assumeIsolated`. No behavior change.
- Settings window redesigned: rows gain inline description subtitles, icons get
  per-row colors, and the window auto-sizes to the active pane. Navigation uses
  the native system `TabView` instead of a self-drawn pill tab bar.
- Large-file download performance: the engine tracks chunk completion and
  written bytes with incremental counters and drains the pending queue with a
  cursor, so progress/completion callbacks and scheduling are O(1) per event
  instead of O(n)/O(n²).
- Chunk state is synced to the app incrementally (only changed chunks) instead of
  copying the full array every tick, and the app keeps its own copy so the
  engine's writes never trigger full-array copy-on-write. Adds a
  `setChunksUpdateHandler` method to `DownloadEngineProtocol`.
- Chunk reconstruction from compact persisted state uses a single merge pass
  (O(n + m)) instead of a nested scan.
- HTTP error messages are now human-readable: 401/403/404/408/429/5xx map to
  plain-language reasons ("Authentication required", "Access denied", "File not
  found", "Request timed out", "Too many requests", "Server error") instead of
  a bare status code.

### Fixed

- Engine no longer hangs in the probing phase when a download fails with a pure
  network error (no HTTP response): after retries are exhausted the failure is
  reported instead of leaving the task stuck at "Preparing" forever.
- Engine now completes a resumed download whose persisted chunks are already
  all complete, so a crash between the last chunk write and the rename does not
  strand the task at 100%.
- A download whose sources are all cooling down no longer drops its pending
  head and hangs; failover keeps retry counts across sources so two failing
  sources cannot hand a chunk back and forth forever.
- A failed or unparsable Metalink now surfaces an error entry instead of
  silently downloading the `.metalink` document itself.
- A dynamic chunk size larger than the probe's initial 256 KB no longer makes
  the probe chunk look like a short read: chunk 0 keeps its probe range and
  completes without a second request.
- The engine's network-down flag was read and written from different queues (a
  data race that could strand a held chunk); its access is now lock-guarded.
- A dropped link with mirrors could cool down the primary source before the
  hold ran; the hold now takes priority over source failover so an outage does
  not pollute per-source cooldown state.
- Single-stream (no-Range) downloads now hold while the link is down instead of
  burning their one retry, matching the chunked path.

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
