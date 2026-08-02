<div align="center">

# ⬇️ MacDL

**A sleek, sandboxed download manager that lives in your menu bar.**

Native macOS · Multi-threaded · Resume · Clipboard · Priority · Notifications

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-00a4ff.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-000000.svg)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)]()
[![UI](https://img.shields.io/badge/UI-SwiftUI-0D0D0D.svg)]()
[![Engine](https://img.shields.io/badge/engine-URLSession-745fff.svg)]()

</div>

---

## ✨ Why MacDL?

Most download managers are either bloated, cloud-bound, or drop a heavy window on
your desktop. MacDL is the opposite — it's a **menu-bar app** that does one thing
well: downloads files fast, quietly, and safely.

- 🔒 **Fully sandboxed** — no silent access to your whole disk
- 🧩 **No external engine** — pure native `URLSession`, no aria2/wget sidecar
- ⚡ **Multi-threaded** — splits files into chunks, up to 8 connections at once
- ⏸️ **True resume** — `.macdl` staging + HTTP `Range`; survives app restarts
- 📋 **Download from Clipboard** — copy a link, one click, done
- 🎯 **Priority downloads** — right-click to focus one task; others pause and resume
- 🔔 **Notifications** — start / complete / failure / priority retry-exhausted
- 🚀 **Menu bar native** — launch at login, hide the Dock icon, run in the background
- 🌏 **Bilingual** — English & 简体中文

## 🧠 How it works

```
 You paste a URL
      │
      ▼
 [Probe: Range: bytes=0-0] ────► 206?  ──►  chunked parallel download
      │                              │
      │                              └─►  200?  ──►  single-stream fallback
      ▼
  Resume later?  ──►  sends bounded Range headers, re-fetches nothing
      ▼
  Done  ──►  renames .macdl staging file to the real filename
```

## 🛠️ Build

```bash
open MacDL.xcodeproj          # then ⌘R
# or, headless:
xcodebuild -project MacDL.xcodeproj -scheme MacDL -destination 'platform=macOS'
```

> **Requirements:** macOS 26+ · Xcode 26+

## 🧪 Test

```bash
# engine package tests
cd MacDLCore && swift test

# app tests (serial to avoid a flaky Observation crash in the parallel host)
xcodebuild test -project MacDL.xcodeproj -scheme MacDL \
  -destination 'platform=macOS' -parallel-testing-enabled NO
```

## 🏗️ Architecture

```
MacDLCore/   Swift Package — the engine
             URLSession chunk engine · token-bucket throttle · resume logic
             (no AppKit, regression-tested in isolation)

MacDL/       App — SwiftUI menu-bar UI · persistence · notifications · sandbox
```

The engine is a standalone Swift Package with zero AppKit dependency — it can be
reused elsewhere and is covered by its own fast `swift test` suite.

## 📄 License

[GPL-3.0](LICENSE) — free to use and modify, but derivative works must stay open source.
