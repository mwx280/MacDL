<div align="center">

# ⬇️ MacDL

**The download manager that gets out of your way.**

---

## 📦 Download — Preview

The current build is **v0.1.0 (Preview)** — an early release that **may be
unstable**. Grab the DMG from the [Releases page](https://github.com/mwx280/MacDL/releases).

> First launch: right-click → Open (ad-hoc signed, not notarized).



Paste a link. It downloads. Quit the app — it still downloads. That's the whole pitch.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()
[![CI](https://github.com/mwx280/MacDL/actions/workflows/ci.yml/badge.svg)](https://github.com/mwx280/MacDL/actions/workflows/ci.yml)
[![Release](https://img.shields.io/badge/release-v0.1.0%20Preview-orange.svg)](https://github.com/mwx280/MacDL/releases)
[![Size](https://img.shields.io/badge/app-1.8%20MB-lightgrey.svg)]()

**English** · [简体中文](README.zh-CN.md)

</div>

---

## 🎯 The problem

Every big download is a small war. The browser gives up on resume mid-file. The
"download manager" you installed insists on owning your entire screen. And that
2-hour, 8 GB file? One Wi‑Fi blip and you're starting over.

**It doesn't have to be like this.**

## 💡 What MacDL does instead

> **One tiny menu-bar icon. Eight parallel connections. Resume that actually
> resumes. Nothing else.**

- **🪶 Featherweight** — the whole app is ~1.8 MB on disk (DMG under 1 MB). No heavy engine, no cloud, no bloat.
- **Copy a link → it's downloading.** No wizard, no form, no login. Hit
  *Download from Clipboard* and go.
- **Big files, maximum speed.** Files are split into chunks and pulled down
  across up to **8 parallel connections** — most browsers can't touch that.
- **Resume that survives anything.** Quit the app, reboot your Mac, come back
  a week later: your download picks up *exactly* where it stopped. No re-downloading.
- **Never interrupts you.** It's a menu-bar app. Hide its Dock icon, launch it at
  login, let it run in the background — your screen stays yours.
- **Actually sandboxed.** It only ever touches the folders you choose. No silent
  reads of your whole disk.
- **Knows when to speak up.** A quiet banner when a download starts or finishes,
  and — importantly — it tells you when a **priority download gave up** after
  retries, so you're never left wondering why the bar went quiet.

## 🚀 Try it in 10 seconds

```
1. Copy any direct link to your clipboard          ⌘C
2. Click the ↓ in your menu bar → "Download from Clipboard"
3. Watch it finish from the menu bar — or open the window and relax
```

That's it. This is a download manager, not a productivity suite.

## 🧠 Under the hood

```
 paste a URL
      │
      ▼
 [Range probe] ──► 206?  ──►  chunked parallel download (up to 8)
      │              │
      │              └──► 200?  ──►  single-stream fallback
      ▼
 resume?  ──►  bounded Range headers, zero bytes re-fetched
      ▼
 done  ──►  .macdl staging renamed to the real file
```

- **Pure native** — `URLSession`, no aria2/wget sidecar, no cloud, no account.
- **Token-bucket throttling** — byte-level speed limits, per task or global.
- **Two codebases, one engine** — the engine is a standalone Swift Package
  (`MacDLCore`) with zero AppKit, regression-tested in isolation. It carries
  its own GPL-3.0 [LICENSE](MacDLCore/LICENSE), so it stays protected when reused.

## 🛠️ Build

```bash
open MacDL.xcodeproj          # then ⌘R
# or headless:
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

> **Requirements:** macOS 26+ · Xcode 26+

## 🧪 Test

```bash
cd MacDLCore && swift test                    # engine suite
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO   # app suite
```

## 📜 Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## 📄 License

[GPL-3.0](LICENSE) — use it, change it, but keep derivatives open source.

**Explicit restrictions:**

- ✅ Personal use, learning, modification, and forking are completely free
- ✅ Publishing your modified version under GPL-3.0 is completely free
- ❌ Integrating any part of this project (including the `MacDLCore` engine) into
  **closed-source commercial software** and distributing it is strictly prohibited
- ❌ Selling this code or modified versions as a **closed-source product** is
  strictly prohibited

Violating the above will be treated as copyright infringement, and the author
reserves the right to pursue legal action.
