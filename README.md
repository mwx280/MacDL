<div align="center">

<img src="icon.png" width="128" alt="MacDL">

# MacDL

A native macOS download manager that you can use entirely from the menu bar.

</div>

## Download

Current build: **v0.2.0 (Preview)** — an early release, expect rough edges.
[Get the DMG from Releases.](https://github.com/mwx280/MacDL/releases)

> First launch: right-click → Open (ad-hoc signed, not notarized).
> Requires macOS 26 or later.

## What it is

MacDL is a native SwiftUI desktop app. It has a normal window with a sidebar
and download list, and it also lives in the menu bar — you can run it with no
window at all and do everything from the status bar icon: paste a link, watch
progress, pause or resume, or open the window only when you need it.

It's small (~1.8 MB), sandboxed, and has no account, cloud, or engine behind it.

## The download engine

The engine (`MacDLCore`) is the part that actually downloads. It's built
directly on `URLSession` — no aria2, wget, or other sidecar process.

- **Multi-threaded chunks.** A file is split into fixed-size chunks and each
  chunk downloads over its own connection, up to 8 in parallel.
- **Range probe first.** Before chunking, the engine asks the server for a
  `Range` request. If it gets a `206`, the file size is known and chunks run in
  parallel. If the server ignores `Range` (returns `200`), it falls back to a
  single connection for the whole file.
- **Resume that actually resumes.** Bytes are written to a `.macdl` staging
  file as they arrive. Quit the app, reboot, come back a week later — each
  chunk continues from its exact offset using bounded `Range` headers. Nothing
  is re-fetched.
- **Retry with backoff.** A failed chunk retries with exponential backoff
  (1s, 2s, 4s…), and rate-limit / server-error storms (429/5xx) are handled
  without hammering the server.
- **Per-task speed limits.** A byte-level token bucket throttles each download
  independently (or globally), not just per connection.
- **Unknown-size downloads.** If a server sends no `Content-Length`, progress
  shows as indeterminate instead of a fake percentage, and the real size is
  filled in when the download completes.

## Features

- **New Download sheet** — paste several URLs at once. Each one gets its own
  thread count and speed limit, and resume support is probed automatically
  (non-resumable tasks are locked to a single thread). Drag links in, or let it
  pick them up from the clipboard.
- **Download from Clipboard** — copy a link and use the menu bar item.
- **Priority downloads** — mark one task as priority; the others pause until
  it finishes, then resume on their own.
- **Notifications you control** — pick which alerts you want (started,
  completed, failed, duplicate link), or turn them all off.
- **Update checking** — checks GitHub Releases for a new version, can download
  it automatically, and installs with one click (relaunch included).
- **Background-friendly** — start with only the menu bar icon, enable launch at
  login, hide the Dock icon when the window closes.
- **Bilingual** — English and Simplified Chinese.

## Quick start

```
1. Copy a direct link                          ⌘C
2. Click the ↓ in the menu bar → "Download from Clipboard"
3. Watch it finish from the menu bar — or open the window
```

## Architecture

- `MacDL` — the app: SwiftUI views, services (settings, persistence,
  notifications, updates) and the download lifecycle.
- `MacDLCore` — the engine, a standalone Swift Package with zero AppKit. The
  app talks to it through a protocol with dependency injection, so the engine
  is regression-tested in isolation. It carries its own
  [GPL-3.0 license](MacDLCore/LICENSE).

## Build

```bash
open MacDL.xcodeproj        # then ⌘R
# or from the command line:
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

## Test

```bash
cd MacDLCore && swift test                    # engine tests
xcodebuild build-for-testing -project MacDL.xcodeproj \
  -scheme MacDL -destination 'platform=macOS' \
  && xcodebuild test-without-building -project MacDL.xcodeproj \
  -scheme MacDL -destination 'platform=macOS'   # app tests
```

App tests need two steps: build first, then run. A bare `xcodebuild test`
finds 0 tests on a fresh checkout — an Xcode quirk, not a problem with this
project.

## Known limitations

- Ad-hoc signed and not notarized, so macOS warns on first launch.
- Notifications only show while the app is running (local notifications).
- The in-app updater mounts the DMG; if the sandbox blocks that, it falls back
  to opening the DMG in Finder.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[GPL-3.0](LICENSE). Use it, change it, fork it — any distributed derivative
must stay open source.

Restrictions:

- ✅ Personal use, learning, modification, forking.
- ✅ Releasing a modified version under GPL-3.0.
- ❌ Integrating any part (including `MacDLCore`) into closed-source commercial
  software and distributing it.
- ❌ Selling this code or a modified version as a closed-source product.

Violations are treated as copyright infringement; the author reserves the right
to pursue legal action.
