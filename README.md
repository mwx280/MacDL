# MacDL

A native macOS download manager that lives in your menu bar.

Multi-threaded downloads, pause/resume, speed limiting, clipboard downloads and
system notifications — all sandboxed and offline (no third-party engines).

## Features

- **Multi-threaded downloads** — splits files into chunks and downloads up to 8 at once
- **Pause / resume** — downloads to a `.macdl` staging file and resumes with HTTP `Range` headers; restart-safe
- **Speed limiting** — byte-level token bucket, adjustable per task or globally
- **Download from Clipboard** — copy a link, pick "Download from Clipboard" in the menu bar, done
- **Priority downloads** — right-click a task to prioritize it; the rest pause and resume automatically
- **Notifications** — start / complete / failure, plus a dedicated banner when a priority download gives up after retries
- **App Sandbox** — security-scoped bookmarks keep custom download folders reachable across launches
- **Menu bar app** — launch at login, hide the Dock icon when the window closes, start in the background
- **Localized** — English and Simplified Chinese

## Requirements

- macOS 26 or later
- Xcode 26 or later (to build from source)

## Build

```sh
open MacDL.xcodeproj   # then ⌘R
# or
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## Test

```sh
# engine package tests
cd MacDLCore && swift test

# app tests (serial, to avoid a flaky Observation registrar crash in the parallel test host)
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO
```

## Architecture

```
MacDLCore/   Swift Package — the download engine
             (URLSession-based chunk engine, token-bucket throttling, resume logic)
MacDL/       App — SwiftUI menu-bar UI, persistence, notifications, sandbox access
```

The engine is a standalone Swift Package with no AppKit dependency, so it's
regression-tested in isolation (`swift test`) and could be reused elsewhere.

## How downloads work

1. The engine sends a small `Range` probe to learn the total size and whether the
   server supports ranges (`206`).
2. The file is split into chunks and downloaded concurrently.
3. If the server can't do ranges, it falls back to a single-stream download.
4. While paused, partial data is kept; resuming sends bounded `Range` headers so
   no bytes are re-fetched.
5. On completion the `.macdl` staging file is renamed to the real filename.

## License

[GPL-3.0](LICENSE)
