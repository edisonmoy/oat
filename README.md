# Oat

A local-first, macOS-native AI meeting-notes app — a rebuild of [Granola](https://granola.ai).

It listens to your computer's audio (no bot ever joins the call), transcribes
on-device, and turns your rough jottings into clean notes using the full
transcript. Sensitive data stays on your Mac; cloud is used only for note quality
and collaboration, and is always explicit. See **[PLAN.md](./PLAN.md)** for the
full architecture, the local-vs-cloud split, and the phased roadmap.

## Status

- **Phase 0 — scaffold ✅.** SwiftUI app, GRDB/SQLite store, meeting list,
  Apple Notes-like editor, settings window.
- **Phase 1 — notes app ✅.** Folders (filter + assign), built-in templates
  (seeded), and FTS5 keyword search across titles and note bodies.
- **Phase 4 — AI enhancement ✅ (code).** "Enhance" turns rough notes into clean
  notes via **Claude** (cloud, default) or **Apple Foundation Models** (on-device,
  privacy mode). API key stored in the Keychain. Transcript is wired in at Phase 3.
- **Next:** Phase 2 (silent macOS system-audio capture) → Phase 3 (WhisperKit
  transcription) → semantic search, calendar, integrations, sync.

Audio capture and transcription are still stubbed under `Sources/Oat/Services/`.

> Built on Linux without an Xcode toolchain, so the code has **not been compiled
> here** — the first real build runs on a Mac or in CI.

## Requirements

- macOS 14+ and Xcode 16+ to build this scaffold.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project
  from `project.yml` (so there's no checked-in `.xcodeproj`).
- Later phases need **macOS 26 + Apple Intelligence** for on-device note
  enhancement via the Foundation Models framework.

## Build & run

```bash
brew install xcodegen      # once
xcodegen generate          # creates Oat.xcodeproj from project.yml
open Oat.xcodeproj         # then Run (⌘R) in Xcode
```

Or from the command line:

```bash
xcodegen generate
xcodebuild build -scheme Oat -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test  -scheme Oat -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Dependencies (currently just [GRDB](https://github.com/groue/GRDB.swift)) are
resolved by Swift Package Manager when the project is generated.

## Project layout

```
project.yml                      XcodeGen spec (targets, deps, settings)
Sources/Oat/
  OatApp.swift                   @main app + menu commands
  AppEnvironment.swift           object graph; live meeting list via GRDB observation
  Data/
    AppDatabase.swift            SQLite connection + schema migrations
    Models/                      Meeting, Note, Folder, Template
    Repositories/                MeetingRepository, NoteRepository
  Features/
    Meetings/                    list, row, and the note editor (detail)
    Settings/                    settings window (local/cloud preferences)
  Services/                      protocol stubs for later phases:
    Audio/                       AudioCaptureService   (Phase 2)
    Transcription/               Transcriber           (Phase 3)
    Notes/                       NoteEngine            (Phase 4)
    Embedding/                   Embedder              (Phase 6)
Tests/OatTests/                  GRDB-backed unit tests
.github/workflows/ci.yml         macOS build + test
```
