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
3. **You take rough notes during the call.** A simple editor. You jot bullets,
   half-sentences, action items.
4. **AI enhances after the meeting.** It combines your sloppy notes + the full
   transcript + a template, and produces polished, structured notes. The user's
   notes steer *what matters*; the transcript supplies *the detail*.
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

We isolate all of this behind one trait/interface:

```
AudioCapture
  ├─ start() -> two streams: mic_pcm, system_pcm  (16 kHz mono f32, post-resample)
  ├─ level meters / VAD hooks
  └─ stop()
implementations: MacTap (Core Audio), WindowsLoopback (WASAPI), LinuxMonitor (PipeWire)
```

### 2.2 Real-time local transcription

- **Engine: `whisper.cpp`** (ggml). Runs on CPU, Metal (mac), CUDA, Vulkan — the
  only realistic choice for an embeddable cross-platform local engine. Bind it via
  `whisper-rs` (Rust) or the C API.
- **Run it as a persistent in-process engine**, not by shelling out per chunk.
  Spinning whisper up per segment makes model-load dominate latency; keep the model
  resident and feed it audio. Expect ~0.5–2 s behind live speech.
- **Chunking via VAD.** Use Silero/WebRTC VAD to cut the stream into utterances,
  transcribe each, and stitch with a local-agreement policy (à la whisper_streaming)
  so we don't rewrite stable text. Two streams → transcribe each separately and
  interleave by timestamp into a single labeled transcript ("Me" / "Them").
- **Model tiers (user-selectable):** `base.en`/`small.en` for live low-latency,
  `medium`/`large-v3` for a higher-accuracy re-transcribe pass after the call if
  desired. Ship quantized GGUF models, download on first run.

### 2.3 Local note generation (the "AI" in AI notes)

- **Engine: a local LLM via [Ollama](https://ollama.com)** (easiest lifecycle) or
  embedded `llama.cpp`. Default to a solid 7–8B instruct model (e.g. Llama 3.1 8B /
  Qwen2.5 7B) that runs on a 16 GB laptop. Expose model choice in settings.
- **The enhancement prompt** takes: `{user_rough_notes} + {transcript} + {template}`
  → structured markdown notes. Templates are just system-prompt + output-schema
  presets ("Standup", "1:1", "Sales discovery", "Interview").
- **Local model quality is the weak link.** So:
  - Keep prompts tight and schema-constrained; do map-reduce summarization for long
    transcripts (chunk → partial summaries → final synthesis) to fit context.
  - Offer an **opt-in cloud fallback** for users who want top quality. When enabled,
    route enhancement to the **Claude API** — `claude-haiku-4-5` for cheap/fast,
    `claude-sonnet-4-6` for best-quality notes. This is strictly optional and
    off by default to honor the local-first promise.

The LLM and transcription both sit behind provider interfaces so local vs cloud is
a config flag, not a rewrite:

```
Transcriber { transcribe(audio) -> segments }   // WhisperLocal | CloudSTT
NoteEngine  { enhance(notes, transcript, tmpl) } // OllamaLocal | ClaudeCloud
Embedder    { embed(text) -> vec }               // LocalOnnx   | CloudEmbed
```

---

## 3. Recommended tech stack

| Layer | Choice | Why |
|---|---|---|
| Shell | **Tauri v2** (Rust core + web UI) | Tiny binaries, native Rust for audio/whisper FFI, good local-first fit. *Electron is the fallback if native audio in Rust proves painful — see §3.1.* |
| UI | **React + TypeScript + Vite** | Mainstream, fast iteration |
| Editor | **TipTap (ProseMirror)** | Block editor like Granola; structured JSON we can diff/store |
| Audio capture | **Rust + per-OS native** (Core Audio tap / WASAPI / PipeWire), Swift FFI shim on mac | The unavoidable native part |
| Transcription | **whisper.cpp via whisper-rs** | Local, accelerated, cross-platform |
| Local LLM | **Ollama** (HTTP) or embedded llama.cpp | Easy local inference |
| Cloud fallback (opt-in) | **Anthropic Claude API** (`claude-haiku-4-5` / `claude-sonnet-4-6`) | Quality upgrade, off by default |
| Storage | **SQLite** (`rusqlite`/`sqlx`) + **FTS5** + **sqlite-vec** | Notes, transcripts, full-text *and* semantic search in one file |
| Embeddings | local ONNX MiniLM / `nomic-embed` via Ollama | On-device semantic search |
| Calendar (opt-in) | system EventKit / Google Calendar OAuth | Auto-title & link meetings |

### 3.1 Stack risk note
The riskiest dependency is **native system-audio capture inside Tauri/Rust**. If it
costs too much time, the pragmatic pivot is **Electron + a small native Swift/C++
helper process** for audio (Electron is also what several real desktop recorders
use). Decide this in Phase 2 after a capture spike — don't build the whole app on an
unproven audio layer. Everything above the `AudioCapture` interface is unaffected by
the choice.

---

## 4. Data model (SQLite)

```
meeting(id, title, started_at, ended_at, template_id, folder_id, calendar_event_id)
recording(id, meeting_id, mic_path, system_path, codec, duration, size_bytes)
transcript_segment(id, meeting_id, speaker /* me|them|spkN */, t_start, t_end, text)
note(id, meeting_id, kind /* raw|enhanced */, content_json, content_md, updated_at)
template(id, name, system_prompt, output_schema)
folder(id, name, parent_id)
embedding(id, meeting_id, chunk_text, vector)         -- sqlite-vec
settings(key, value)                                  -- model choices, cloud opt-in
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
early phases de-risk the editor/storage before touching native audio.

- **Phase 0 — Scaffold.** Tauri + React + SQLite. App opens, creates/lists meetings,
  settings screen. CI + cross-platform build.
- **Phase 1 — Notes app (no audio).** TipTap editor, folders, raw-notes CRUD, FTS5
  keyword search. This is a usable local notes app on its own.
- **Phase 2 — Audio capture spike + decision.** Implement `AudioCapture` for **one**
  platform (macOS Core Audio tap first). Record mic + system to two WAVs, show level
  meters. **Gate:** confirm Tauri/Rust vs Electron here.
- **Phase 3 — Local transcription.** whisper.cpp resident engine + VAD chunking; live
  transcript pane with Me/Them labels; **audio saved to disk (Opus) and linked to the
  meeting**, with synced playback + "jump to moment" from a transcript line. Model
  download/manager + optional re-transcribe-with-bigger-model pass.
- **Phase 4 — AI enhancement.** Ollama integration; templates; "Enhance notes" merges
  raw notes + transcript → structured markdown. Map-reduce for long meetings.
- **Phase 5 — Search & org.** Semantic search (local embeddings + sqlite-vec), better
  folders/tags, export (md/pdf), chat-with-your-meetings Q&A over the transcript.
- **Phase 6 — Polish & opt-in cloud.** Calendar auto-titling, Windows/Linux capture
  backends, opt-in Claude cloud fallback for transcription/enhancement, optional
  encrypted-at-rest + cloud sync.

---

## 6. Local-first / privacy principles (the product's spine)

- **On-device by default.** Transcription and note generation work with **zero**
  network. The app is fully functional offline.
- **Invisible capture is the headline feature.** No bot, no participant, no on-screen
  indicator to the other party — capture happens entirely on the user's machine.
- **Audio stays on the user's device.** Recordings are kept locally (encrypt-at-rest
  option), never uploaded unless the user explicitly enables cloud sync. Storage
  usage is visible and user-controllable (manual delete / age-out policy).
- **No telemetry.** If we ever add analytics, it's opt-in and anonymous.
- **Cloud is a toggle, not a tier.** Any cloud feature (Claude enhancement, sync) is
  explicit, off by default, and clearly indicated in the UI when active.
- **Data is portable.** Single SQLite file + markdown export; users own their data.

---

## 7. Open decisions to confirm before Phase 0

1. **Target platform first** — recommend **macOS-first** (best audio APIs, Granola's
   own primary platform), then Windows, then Linux.
2. **Tauri vs Electron** — recommend **Tauri**, decided for real at the Phase 2 gate.
3. **Local LLM delivery** — bundle Ollama as a dependency vs embed llama.cpp. Recommend
   **Ollama** initially for speed of development.

---

## Sources

- [How transcription works — Granola Docs](https://docs.granola.ai/help-center/taking-notes/transcription)
- [How to build a desktop recording app (Like Granola) — Recall.ai](https://www.recall.ai/blog/how-to-build-a-desktop-recording-app)
- [How to get access to system audio on macOS — Recall.ai](https://www.recall.ai/blog/how-to-access-to-system-audio)
- [Capturing system audio with Core Audio taps — Apple Developer](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [AudioCap — system audio recording sample (macOS 14.4+)](https://github.com/insidegui/AudioCap)
- [Whisper.cpp vs faster-whisper 2026 benchmarks](https://www.promptquorum.com/power-local-llm/local-whisper-stt-comparison-2026)
- [Choosing a Real-Time Whisper Engine](https://allenkuo.medium.com/choosing-a-real-time-whisper-engine-c4eeb5885e22)
