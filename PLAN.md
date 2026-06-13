# Oat — a local-first Granola clone

> An AI meeting-notes app that listens to your computer's audio (no bot joins the
> call), transcribes locally, and merges your rough notes with the transcript into
> clean notes — with everything running on-device by default.

This document is the build plan. It captures **what** Oat does, **how** it works
under the hood, the **tech-stack** decisions, and a **phased roadmap** you can
execute one slice at a time.

---

## 1. What we're cloning

Granola's product is deceptively simple and its design choices are worth copying
exactly, because they're what make it feel magical:

1. **No meeting bot — invisible to the other party. (This is the whole point.)**
   It never joins the call as a participant; no bot shows up in the attendee list,
   nothing asks the room for consent, nothing appears on anyone's screen. It simply
   captures the audio already playing on *your* machine — your mic (you talking) plus
   the system output (everyone else). This works with Zoom, Meet, Teams, Slack
   huddles, or an in-person conversation, because it operates at the OS audio level,
   not via a calendar/meeting integration. **Everything in this plan is in service of
   keeping the capture silent and local — that invisibility is the product.**
2. **Audio is kept.** We record and store the audio locally so it can be replayed,
   re-transcribed later with a better model, and scrubbed against the transcript.
   (This is a deliberate departure from Granola, which deletes audio after
   transcription. We trade some disk for the ability to revisit a recording.) The
   transcript is stored alongside it.
3. **You take rough notes during the call — in a barebones, Apple Notes-like
   editor.** This is a load-bearing UX choice. During a live conversation you can't
   fuss with formatting, so the editor is deliberately minimal: open it, start a new
   note, type. Bullets, half-sentences, a stray name, an action item. No menus to
   hunt through, no mode-switching, instant and distraction-free. The whole job of
   the in-call editor is to get out of your way so you can listen.
4. **After the call, AI fleshes the notes out using the full recording.** It takes
   your sparse jottings and expands them with the complete transcript as context —
   filling in detail, surrounding context, decisions, and action items you only
   half-wrote. Your notes steer *what matters*; the transcript supplies *the detail
   and accuracy*. The output is a clean, structured version of what you would have
   written if you'd had time. The raw note is preserved alongside the enhanced one.
5. **Organization on top:** folders, templates, full-text + semantic search,
   calendar to auto-title meetings.

Our twist: **local-first**. Transcription and note-generation run on-device by
default (Whisper + a local LLM). Cloud is an *opt-in* quality/speed upgrade, never
a requirement.

---

## 2. The hard parts (and how we solve them)

Three things make this non-trivial. Everything else is a CRUD app with a nice editor.

### 2.1 Capturing system audio without a bot

This is the single hardest, most platform-specific piece.

- **macOS 14.4+** — Use **Core Audio process taps** (`CATap`) to capture system
  output, plus `AVAudioEngine`/CoreAudio for the mic. This is the modern, no-extra-
  driver path and is exactly what newer recorders use. (Apple: *Capturing system
  audio with Core Audio taps*; reference impl: `insidegui/AudioCap`.) On macOS
  13–14.3, fall back to **ScreenCaptureKit** audio-only capture or a virtual device
  (BlackHole).
- **Windows** — **WASAPI loopback** captures the render endpoint (system output);
  WASAPI capture for the mic. No driver needed.
- **Linux** — **PipeWire/PulseAudio monitor** source for system audio, normal source
  for mic.

**Key design decision: keep mic and system audio as two separate channels/streams.**
This is the trick that gives near-free speaker separation: the mic stream is "Me",
the system stream is "Them". We never have to run real diarization to get a usable
"who said what" for the common 1-on-1 / "me vs the room" case. (Multi-speaker
diarization within the system stream is a later, optional enhancement via pyannote.)

Since Oat is **macOS-native**, this is a focused, single-platform problem (no
cross-platform abstraction to maintain). We capture via **Core Audio process taps**
for system output + **AVAudioEngine** for the mic, written in Swift:

```
AudioCaptureService (Swift)
  ├─ start() -> two AVAudioPCMBuffer streams: micStream, systemStream
  ├─ taps: CATap (system output) + AVAudioEngine input node (mic)
  ├─ resample -> 16 kHz mono Float32 for the transcriber
  ├─ encode -> Opus files on disk for retention (see §4)
  └─ stop()
```

Requires the audio-capture entitlement + a TCC permission prompt on first run
(macOS asks the user to allow system-audio recording). Reference: Apple's *Capturing
system audio with Core Audio taps* and `insidegui/AudioCap`.

### 2.2 Real-time local transcription

- **Engine: [WhisperKit](https://github.com/argmaxinc/WhisperKit)** — a Swift-native
  port of OpenAI Whisper that runs on **CoreML across the Apple Neural Engine / GPU /
  CPU**. It's purpose-built for exactly this: real-time streaming transcription with
  progressive results, word-level timestamps, and built-in VAD chunking. Being
  Swift-native (vs. binding C++) keeps the whole app one language and one toolchain.
- **Two streams → two transcribers**, interleaved by timestamp into one labeled
  transcript ("Me" / "Them"). For multi-speaker separation *within* the system
  stream, Argmax's **SpeakerKit** diarization is a drop-in later enhancement.
- **Model tiers (user-selectable):** a small English model (e.g. `base`/`small`) for
  low-latency live captions; `large-v3` for an optional higher-accuracy re-transcribe
  pass after the call (we kept the audio — see §1 / §4 — so we can). Models are
  CoreML packages downloaded on first run.

### 2.3 Local note generation (the "AI" in AI notes)

This is the after-the-call step from §1.4 — expand sparse notes using the full
transcript. It's **not latency-critical and quality matters most**, so per the split
in §3.2 the **default is cloud Claude**, with a fully-local fallback for offline /
privacy mode. Three interchangeable `NoteEngine` implementations:

- **Cloud (default): the [Claude API](https://docs.anthropic.com)** — `claude-haiku-4-5`
  for fast/cheap, `claude-sonnet-4-6` for best-quality notes. This gives the strongest
  enhancement; only *text* (transcript + notes) is sent, never audio. Anthropic also
  ships a Swift package that plugs Claude into the Foundation Models framework, so
  local↔cloud can share one call site.
- **Local (privacy/offline): Apple's [Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)**
  (macOS 26+). The on-device ~3B Apple Intelligence model via a Swift API, with
  **guided generation** (typed/structured output) and tool calling — clean notes
  schema with **zero deps, zero network, zero install**.
- **Heavier local option: `llama.cpp` (Metal) / MLX-Swift** running a 7–8B model
  (Llama 3.1 / Qwen2.5) when the 3B Apple model isn't enough but the user still wants
  to stay offline — at the cost of bundling a runtime + weights.

**The enhancement prompt** takes `{user_rough_notes} + {transcript} + {template}` →
structured notes. Templates are system-prompt + output-schema presets ("Standup",
"1:1", "Sales discovery", "Interview"). For long meetings, map-reduce the transcript
(chunk → partial summaries → final synthesis) to fit context.

The transcriber and note engine sit behind Swift protocols so local vs cloud is a
settings toggle, not a rewrite:

```swift
protocol Transcriber { func transcribe(_ audio: AudioBuffer) async -> [Segment] }   // WhisperKit | CloudSTT
protocol NoteEngine  { func enhance(notes: String, transcript: String, template: Template) async -> Note } // AppleFoundation | LlamaLocal | ClaudeCloud
protocol Embedder    { func embed(_ text: String) -> [Float] }                       // NLEmbedding | CloudEmbed
```

---

## 3. Recommended tech stack — all-Apple-native

macOS-only lets us use one language (Swift) and the platform's own ML stack end to
end. No web layer, no cross-platform abstraction, no bundled inference servers.

| Layer | Choice | Why |
|---|---|---|
| App | **Swift + SwiftUI**, macOS 26+ (Apple Silicon) | Native, single language, menu-bar + window UX |
| Editor | **SwiftUI `TextEditor` / TextKit 2 + AttributedString** | The barebones, Apple Notes-like jotting surface (§1.3) — minimal by design |
| Audio capture | **Core Audio process taps + AVAudioEngine** (Swift) | Native bot-free mic + system capture (§2.1) |
| Transcription | **WhisperKit** (CoreML, Neural Engine) | Swift-native, streaming, on-device |
| Diarization (later) | **SpeakerKit** (Argmax) | Multi-speaker within the system stream |
| Local LLM | **Apple Foundation Models framework** (on-device 3B); **llama.cpp/MLX** for bigger models | Native note enhancement, zero deps by default |
| Cloud LLM (opt-in) | **Claude API** (`claude-haiku-4-5` / `claude-sonnet-4-6`) | Quality upgrade, off by default |
| Storage | **SQLite via GRDB.swift** + **FTS5** | Notes, transcripts, keyword search in one file |
| Embeddings / semantic search | **NLEmbedding** (Natural Language framework) or local CoreML model + **sqlite-vec** | On-device semantic search |
| Audio encoding | **Opus / AVAudioFile** | Compact retained recordings (§4) |
| Calendar (opt-in) | **EventKit** | Auto-title & link meetings |
| Packaging | Xcode app, Developer ID signed + notarized | Standard mac distribution |

### 3.1 Stack risk note
The one genuinely risky, can't-fake-it piece is **system-audio capture via Core Audio
taps** (entitlements, the TCC permission prompt, clean teardown). De-risk it with a
throwaway capture spike in **Phase 2** before building anything on top of the
`AudioCaptureService` interface. Everything above that interface is unaffected by how
capture is implemented. Secondary watch item: **Foundation Models requires macOS 26 +
Apple Intelligence**; keep the `NoteEngine` protocol so we can fall back to a bundled
llama.cpp model on older/unsupported machines.

### 3.2 What runs locally vs in the cloud (the split)

Cloud is now allowed for **LLM quality** and **storage/collaboration**, but not
everything should leave the device. The guiding rule: **anything privacy-critical or
latency-critical stays local; cloud is for quality, scale, and sharing — and is
explicit in the UI.**

| Concern | Where | Why |
|---|---|---|
| Audio capture | **Local only** | It's the OS audio layer — can't be remote, and it's the most sensitive data |
| Raw audio recordings | **Local by default** | Most sensitive artifact; cloud backup is opt-in & encrypted |
| Live transcription (captions during call) | **Local (WhisperKit)** | Latency-critical + always-on; must work offline and never stream live audio out |
| Raw notes (your jottings) | **Local-first** | Yours; synced to cloud only if sync is on |
| **Note enhancement (after call)** | **Cloud by default, local fallback** | Not latency-critical and quality matters most → **Claude** gives the best notes; fall back to on-device model offline / when privacy mode is on |
| Ask-AI / chat across meetings | **Cloud by default, local fallback** | Reasoning quality over many transcripts; retrieval runs locally, generation can be cloud |
| Embeddings / semantic index | **Local** | Cheap on-device (NLEmbedding); keeps the search index private |
| Primary datastore | **Local SQLite** | Source of truth; works fully offline |
| Cross-device sync / backup | **Cloud (opt-in), E2E-encrypted** | Convenience; user owns the keys |
| Sharing & team Spaces | **Cloud** | Inherently multi-user; only shared notes leave the device |
| Integrations (Slack/Notion/CRM/calendar) | **Cloud APIs** | Third-party services; only the data the user chooses to push |

Net: a **"privacy mode"** toggle flips enhancement + chat to the local model and
disables all egress, so the app is still 100% functional offline; the default is a
hybrid that uses cloud Claude for the best notes while raw audio/transcripts stay on
the device unless the user turns on sync or sharing.

---

## 4. Data model (SQLite)

```
meeting(id, title, started_at, ended_at, template_id, folder_id, calendar_event_id, language)
recording(id, meeting_id, mic_path, system_path, codec, duration, size_bytes)
transcript_segment(id, meeting_id, speaker /* me|them|spkN */, t_start, t_end, text)
note(id, meeting_id, kind /* raw|enhanced */, content_json, content_md, updated_at)
attendee(id, meeting_id, name, email)                 -- from calendar
template(id, name, system_prompt, output_schema, is_team)
folder(id, name, parent_id, space_id)
space(id, name, kind /* personal|shared */, acl)      -- team workspaces (cloud)
chat_message(id, scope /* meeting|folder|global */, scope_id, role, content)
share(id, meeting_id|folder_id, url, audience, created_at)
integration(id, kind /* slack|notion|hubspot|… */, config, auth_ref)
embedding(id, meeting_id, chunk_text, vector)         -- via NLEmbedding + sqlite-vec
sync_state(entity, id, rev, dirty)                    -- for opt-in cloud sync
settings(key, value)                                  -- model choices, privacy mode, cloud opt-in
```

- **Audio is kept.** Each meeting's mic and system streams are written to disk
  (recommend per-stream Opus files for a good size/quality trade-off) and tracked in
  `recording`. This enables replay synced to the transcript, re-transcription with a
  larger model later, and "jump to this moment" from any transcript line. Show
  per-meeting and total storage usage; offer manual/aged-out cleanup so disk doesn't
  grow unbounded.
- FTS5 virtual table over `transcript_segment.text` + `note.content_md` for instant
  keyword search; `sqlite-vec` for semantic search.

---

## 5. Phased roadmap

Each phase is independently shippable and demoable. **Build in this order** — the
early phases de-risk the editor/storage before touching native audio, and the cloud
collaboration features (sharing, sync, Spaces) come last, after the local core is
solid.

- **Phase 0 — Scaffold.** SwiftUI app + GRDB/SQLite. App opens, creates/lists
  meetings, settings screen. Xcode project, signing, CI.
- **Phase 1 — Notes app (no audio).** The barebones Apple Notes-like editor (§1.3),
  folders, raw-notes CRUD, FTS5 keyword search. A usable local notes app on its own.
- **Phase 2 — Audio capture spike.** Implement `AudioCaptureService` via Core Audio
  taps + AVAudioEngine. Record mic + system to two Opus files, show level meters,
  handle the TCC permission prompt. **De-risk gate** before building on top.
- **Phase 3 — Local transcription.** WhisperKit streaming; live transcript pane with
  Me/Them labels; **audio retained on disk and linked to the meeting** (§4) with
  synced playback + "jump to moment" from a transcript line. Model manager + optional
  re-transcribe-with-`large-v3` pass.
- **Phase 4 — AI enhancement + templates.** "Enhance notes" merges raw notes +
  transcript → structured markdown via the `NoteEngine` (cloud Claude by default,
  Apple Foundation Models in privacy/offline mode). Template library (1:1, standup,
  discovery, interview, custom) with **Decisions / Action items / Next steps**
  sections. Map-reduce for long meetings.
- **Phase 5 — Calendar + auto-context.** EventKit (system) + Google/Outlook OAuth:
  auto-detect upcoming meetings, **auto-title** notes, pull **attendees**, and start
  a note from a calendar event in one click. Multi-language auto-detect (WhisperKit).
- **Phase 6 — Search & Ask-AI.** Keyword (FTS5) + semantic (NLEmbedding + sqlite-vec)
  search; **Ask-AI / chat** scoped to a meeting, a folder, or all meetings (local
  retrieval + cloud-or-local generation); export (md/pdf/copy).
- **Phase 7 — Sharing & integrations.** Share a note/folder via link (viewable by
  non-users); push summaries to **Slack / Notion / HubSpot / Affinity** + a generic
  webhook/Zapier path; expose Oat over **MCP** so other AI tools can query meetings.
- **Phase 8 — Sync, Spaces & polish.** Opt-in **E2E-encrypted cloud sync/backup**,
  **team Spaces** (shared folders with access controls), encrypt-at-rest, privacy-mode
  toggle, onboarding, storage management.

---

## 6. Privacy principles (the product's spine)

Local-first, hybrid where it helps — see the split in §3.2.

- **Invisible capture is the headline feature.** No bot, no participant, no on-screen
  indicator to the other party — capture happens entirely on the user's machine.
- **Sensitive data is local by default.** Raw audio, the live transcript, and the
  primary datastore live on the device. They leave only when the user turns on sync,
  sharing, or cloud enhancement — and the UI says so when they do.
- **Live audio never streams to the cloud.** Transcription is on-device; only *text*
  (transcript/notes) is ever sent out, and only for the features that need it.
- **Privacy mode = fully local.** One toggle routes enhancement + chat to the
  on-device model and disables all egress; the app stays 100% functional offline.
- **Cloud is explicit, not a hidden default.** Cloud LLM, sync, sharing, and
  integrations are clearly indicated and individually controllable.
- **Data is portable.** Single SQLite file + markdown/PDF export; users own their data
  (and their sync keys — E2E-encrypted).
- **No silent telemetry.** Any analytics is opt-in and anonymous.

---

## 7. Open decisions to confirm before Phase 0

1. **Enhancement default** — recommend **cloud Claude by default for note quality**,
   with one-toggle local fallback (Apple Foundation Models) + privacy mode. Confirm
   this vs. local-by-default.
2. **macOS floor** — Foundation Models needs **macOS 26 + Apple Intelligence**. Confirm
   we target 26+, or also support macOS 14–15 via a bundled llama.cpp model.
3. **Sync backend** — build our own E2E-encrypted sync vs. CloudKit vs. a managed
   backend (Supabase/Turso). Recommend **CloudKit** for a mac-native, no-server start.
4. **Heavier local model** — whether to bundle llama.cpp/MLX (7–8B) at all, or rely on
   Apple's 3B locally + Claude for quality. Recommend **start without it**.

---

## 8. Feature parity with Granola (gap check)

Cross-referenced against Granola's current feature set. ✅ planned · ➕ added this pass
· 🔷 cloud-dependent (now in scope) · ⏭️ deliberately out of scope.

| Granola feature | Status | Where |
|---|---|---|
| Bot-free device-audio capture (mic + system) | ✅ | §2.1, Phase 2 |
| Real-time transcription | ✅ | §2.2, Phase 3 |
| Rough notes during call (Apple Notes-like) | ✅ | §1.3, Phase 1 |
| AI-enhanced notes from full transcript | ✅ | §1.4 / §2.3, Phase 4 |
| Templates (1:1, standup, discovery, interview, custom) | ✅ | Phase 4 |
| Decisions / Action items / Next steps extraction | ➕ | Phase 4 (template sections) |
| Folders & organization | ✅ | Phase 1 |
| Keyword + semantic search | ✅ | Phase 6 |
| Ask-AI / chat with a meeting | ➕ | Phase 6 |
| Chat with a folder / across all meetings | ➕ | Phase 6 |
| Multi-language (12+) with auto-detect | ➕ | Phase 5 (WhisperKit) |
| Calendar sync (Google/Outlook), auto-title, attendees | ➕🔷 | Phase 5 |
| Share notes via link (incl. non-users) | ➕🔷 | Phase 7 |
| Integrations: Slack, Notion, HubSpot, Affinity, Zapier | ➕🔷 | Phase 7 |
| MCP server (let other AI tools query meetings) | ➕🔷 | Phase 7 |
| Cross-device sync / unlimited history | ➕🔷 | Phase 8 |
| Team workspaces / Spaces with access controls | ➕🔷 | Phase 8 |
| Retain audio + synced playback (our addition vs Granola) | ➕ | §1.2 / §4, Phase 3 |
| iPhone app + phone-call transcription | ⏭️ | macOS-only for v1; iOS is a later companion |
| Windows app | ⏭️ | Out of scope (macOS-native by design) |

No remaining Granola features are unaccounted for; the only intentional omissions are
the non-mac platforms.

---

## Sources

- [How transcription works — Granola Docs](https://docs.granola.ai/help-center/taking-notes/transcription)
- [How to build a desktop recording app (Like Granola) — Recall.ai](https://www.recall.ai/blog/how-to-build-a-desktop-recording-app)
- [How to get access to system audio on macOS — Recall.ai](https://www.recall.ai/blog/how-to-access-to-system-audio)
- [Capturing system audio with Core Audio taps — Apple Developer](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [AudioCap — system audio recording sample (macOS 14.4+)](https://github.com/insidegui/AudioCap)
- [Whisper.cpp vs faster-whisper 2026 benchmarks](https://www.promptquorum.com/power-local-llm/local-whisper-stt-comparison-2026)
- [Choosing a Real-Time Whisper Engine](https://allenkuo.medium.com/choosing-a-real-time-whisper-engine-c4eeb5885e22)
- [WhisperKit — Swift on-device ASR (Argmax)](https://github.com/argmaxinc/WhisperKit)
- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Granola integrations (Slack, Notion, HubSpot, Zapier)](https://www.granola.ai/blog/granola-integrations-hubspot-slack-notion-zapier)
- [In-Depth Granola Review 2026 (feature set)](https://www.bluedothq.com/blog/granola-review)
