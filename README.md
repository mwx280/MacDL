<div align="center">

# ⬇️ MacDL

**The download manager that gets out of your way.**

Paste a link. It downloads. Quit the app — it still downloads. That's the whole pitch.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()

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
  (`MacDLCore`) with zero AppKit, regression-tested in isolation.

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

## 📄 License

[GPL-3.0](LICENSE) — use it, change it, but keep derivatives open source.
