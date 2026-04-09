# Catch Me Up

> *Your context, always within reach.*

A local-first macOS personal context engine that answers "I think someone said something about..." by cross-referencing mail, chat, meetings, files, and audio transcripts — all indexed locally via [LEANN](https://github.com/yichuan-w/LEANN), all synthesized by Claude with source-cited answers.

**Course**: NBA 6170 AI Solutions, Prof. Lutz Finger, Cornell  
**Repo**: [torrent-lake/catchmeup](https://github.com/torrent-lake/catchmeup)  
**Stack**: Swift 6.2 · macOS 15+ · LEANN · Claude Opus 4.6 · Liquid Glass UI

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI Layer                                                           │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ MainDashboardView│  │  AgentChatView   │  │ API Settings     │  │
│  │ • Heatmap        │  │ • Streaming chat │  │ • URL + Token    │  │
│  │ • Calendar arcs  │  │ • Citation chips │  │ • Model select   │  │
│  │ • Ripple wordcld │  │ • 👍👎 feedback  │  │ • Format toggle  │  │
│  │ • Context bar    │  │ • File drag-drop │  │                  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────────────┘  │
│           │                     │                                   │
├───────────┼─────────────────────┼───────────────────────────────────┤
│  Workflow │                     │                                   │
│  ┌────────▼─────────┐  ┌───────▼──────────┐  ┌──────────────────┐  │
│  │DayContextLoader  │  │  AgentSession    │  │ BriefingService  │  │
│  │ Loads LEANN data │  │ Question→Answer  │  │ Pre-meeting brief│  │
│  │ per selected day │  │ pipeline         │  │ Daily digest     │  │
│  └────────┬─────────┘  └───────┬──────────┘  │ Proactive intel  │  │
│           │                     │             └──────────────────┘  │
├───────────┼─────────────────────┼───────────────────────────────────┤
│  Reasoning│                     │                                   │
│  ┌────────▼─────────────────────▼──────────┐  ┌──────────────────┐  │
│  │           CrossRefEngine                │  │  GuardrailGate   │  │
│  │  Parallel fanout → Dedupe → Rerank      │  │  Input sanitize  │  │
│  │  topK=10/src · budget=20 · deadline=15s │  │  Chunk scrub     │  │
│  │                                         │  │  Output validate │  │
│  │  Rerank formula:                        │  └──────────────────┘  │
│  │    score = leann_score                  │                        │
│  │          + recency_bonus (up to +0.2)   │  ┌──────────────────┐  │
│  │          − diversity_penalty (0.15/ea)  │  │  PromptComposer  │  │
│  │                                         │  │  <source> tags   │  │
│  │  Dedupe: ID → 7-gram shingle hash      │  │  <user_content>  │  │
│  └─────────────────────┬───────────────────┘  └──────────────────┘  │
│                        │                                            │
├────────────────────────┼────────────────────────────────────────────┤
│  Adapters              │                                            │
│  ┌─────────────────────▼───────────────────────────────────────┐    │
│  │                    LEANNBridge (actor)                       │    │
│  │  Subprocess wrapper: leann search <index> <query> --top-k N │    │
│  │  Working dir: /Users/yizhi/leann (required for index lookup)│    │
│  │  Binary: .venv/bin/leann · Timeout: 15s                     │    │
│  │  Timestamp extraction: [Date], [YYYY-MM-DD HH:MM], [HH:MM] │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ AnthropicClient  │  │  CalendarData    │  │  RemindersData   │  │
│  │ (actor)          │  │  Source          │  │  Source          │  │
│  │                  │  │                  │  │                  │  │
│  │ SSE streaming    │  │ EventKit API     │  │ EventKit API     │  │
│  │ x-api-key +      │  │ Direct query     │  │ Direct query     │  │
│  │ Bearer headers   │  │ Broad match for  │  │ Broad match for  │  │
│  │                  │  │ schedule queries │  │ reminder queries │  │
│  │ Claude Opus 4.6  │  │                  │  │                  │  │
│  │ (/relay compat)  │  │                  │  │                  │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  Capture Layer                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ RecordingPolicy  │  │  CalendarOverlay │  │  Whisper.cpp     │  │
│  │ Gentle/Manual/   │  │  Service         │  │  Transcription   │  │
│  │ Rogue modes      │  │  9 calendars     │  │  large-v3-turbo  │  │
│  │                  │  │  auto-enable     │  │  22kHz mono      │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Sources & LEANN Indices

### RAG Layer (LEANN semantic search)

| Index | Size | Chunks | Source | Embedding | Chunking |
|---|---|---|---|---|---|
| `mail_index` | 26 MB | ~5K | Apple Mail `.emlx` files | `all-MiniLM-L6-v2` (384d) | LEANN auto-chunk by paragraph |
| `wechat_history` | 43 MB | ~10K | WeChat export (full history) | `all-MiniLM-L6-v2` | LEANN auto-chunk |
| `wechat_recent` | 0.2 MB | 164 | 8 chats via WeChat MCP | `all-MiniLM-L6-v2` | Per-message, `[timestamp] sender: text` |
| `transcripts_index` | 61 MB | 48,042 | Whisper.cpp `.txt` transcripts (23 days) | `all-MiniLM-L6-v2` | Per-utterance, `[HH:MM:SS-HH:MM:SS] text` |
| `imessage_index` | 0.3 MB | ~150 | iMessage `chat.db` export (603 msgs) | `all-MiniLM-L6-v2` | Per-message, `[timestamp] sender: text` |
| `files_index` | 0.2 MB | ~200 | ~/Downloads + ~/Documents scan | `all-MiniLM-L6-v2` | Per-file metadata + text content |

**Total indexed**: ~130 MB across 6 LEANN indices, ~63K chunks

### System API Layer (direct query, no embedding)

| Source | API | Chunking | Data |
|---|---|---|---|
| Calendar | EventKit `EKEventStore` | 1 event = 1 chunk (title + time + location + attendees + notes) | 9 calendars, ~10 events/day |
| Reminders | EventKit `EKReminder` | 1 reminder = 1 chunk (title + due + status + notes) | 29 active reminders |
| Files | Spotlight `mdfind -onlyin ~` | 1 file = 1 chunk (name + path + size + modified date) | Real-time search |

---

## Prompt Architecture

### 7 Versioned System Prompts (`PromptTemplates.swift`)

All prompts are **hardcoded constants** — never user-templated. Each includes the `<safety>` block verbatim.

| Template | Purpose | Used by |
|---|---|---|
| `safetyBlockV1` | Injection defense: treats `<source>` as data, not instructions. Redacts credentials. Requires citations. | Embedded in all prompts below |
| `systemOnDemandAnswerV1` | On-demand Q&A from Agent Chat | `AgentSession` via `.onDemand` |
| `systemBriefingV1` | Pre-meeting brief (Key Context / People / Open Items / Suggested Topics) | `BriefingService` via `.briefing` |
| `systemDailyDigestV1` | End-of-day summary (Highlights / Action Items / Missed / Looking Ahead) | `BriefingService` via `.dailyDigest` |
| `systemProactiveV1` | "What might I forget tomorrow?" (⏰ Time-sensitive → 📋 Action → 💡 Good to know) | `BriefingService` via `.proactive` |
| `systemFileAggregationV1` | File gathering for drag-and-drop | `BriefingService` via `.fileAggregation` |
| `debugProbeSystemV1` | Health check: respond "hello" | `#if DEBUG` status bar probe |

### Prompt Composition (`PromptComposer.swift`)

```
System: <template from above>

User message:
  <user_content>
  {sanitized question}
  </user_content>

  <source id="1" type="mail" date="2026-04-08T..." origin="mailto:...">
  {chunk body}
  </source>
  <source id="2" type="wechat" date="2026-04-06T...">
  {chunk body}
  </source>
  ...

  Answer:
```

---

## LLM Configuration

```swift
// LLMEndpointConfig — all UserDefaults-backed, runtime-swappable
CatchMeUp.llm.baseURL      = "https://api.anthropic.com"  // or relay URL
CatchMeUp.llm.apiFormat     = "anthropic"                   // or "openai"
CatchMeUp.llm.defaultModel  = "claude-opus-4-6"

// Auth token in Keychain
Service: "com.catchmeup.anthropic"
Account: "default"
// Fallback: ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY env var
```

**AnthropicClient** sends both `x-api-key` and `Authorization: Bearer` headers for relay compatibility.

**Agent Chat parameters**: temperature `0.2` · maxTokens `2000` · deadline `15s`

---

## Context Density Heatmap

96 bins × 15 minutes = 24-hour timeline. Each bin can have multiple density layers:

| Color | Source | Method |
|---|---|---|
| **Cyan** (deep/shallow) | Audio recording | `events.jsonl` segments + loudness normalization |
| **Gold** | Calendar events | EventKit time-range overlap (all-day events filtered >12h) |
| **Violet** | Email | LEANN chunks → ambient density on active bins |
| **Green** | WeChat/iMessage | LEANN chunks → ambient density or timestamp placement |
| **Pink** | Files | LEANN chunks → ambient density |

When a LEANN source has no parseable timestamps, `ContextDensityBinMapper` applies **ambient density** — color is spread across bins that already have recording or calendar activity, with intensity proportional to chunk count (`min(0.6, count / 10 * 0.3)`).

**Multi-source color blending** (`HeatmapPalette.contextDensityColor`): recording keeps cyan base; context sources add a subtle tint. If only context (no recording), the dominant source color is used directly.

---

## Guardrails & Evaluation

### GuardrailGate

| Stage | Defense |
|---|---|
| **Input** | Length cap 4000, control char strip, injection pattern detection (4 regex patterns) |
| **Chunks** | Base64 blob stripping (>300 chars) |
| **Output** | System prompt leakage detection, payload string detection |

### EvalService

- **Golden set**: 10 queries (3 single-source, 3 cross-source, 2 temporal, 2 negative)
- **Adversarial corpus**: 3 prompts (plain injection, fake system tag, exfiltration image)
- **Metrics**: Hit rate, hallucination rate, adversarial block rate, median latency

---

## Ripple Word Cloud

Bottom of the main dashboard. Uses the `ASCIIBackgroundView` ripple animation from AllTimeRecorded:

- **36×5 character grid**, 14×18px cells, `Canvas` rendering
- Words from calendar events + transcripts + LEANN chunks appear at random positions
- Concentric `·` dot waves radiate outward and decay (`brightness *= 0.86` per tick)
- 13pt semibold monospace, **neonCyan** single-color (#47E6F2)
- Peak brightness `0.4`, word brightness `×3.0`, render multiplier `×3.0`
- Tick interval: `0.10s` (~10 FPS)
- Reacts to `@ObservedObject calendarService` — updates when day data loads

---

## Recording Modes

| Mode | Behavior | Default |
|---|---|---|
| **Gentle** | No auto-record. Calendar-driven nudge T-5min before meetings. | ✅ |
| **Manual** | User starts/stops explicitly. No automation. | |
| **Rogue** | Open-lid auto-record on launch (legacy AllTimeRecorded behavior). | |

Audio: 22.05 kHz mono · AAC-LC 24 kbps · 30-min segments · daily merge via `afconvert`

---

## Model Comparison

| Model | Context | Latency | Chinese | Licensing | Cost | Our Use |
|---|---|---|---|---|---|---|
| **Claude Opus 4.6** | 200K | ~3s TTFT | Good | Commercial API | $$$ | **Default** — highest citation fidelity |
| Claude Sonnet 4.6 | 200K | ~1s TTFT | Good | Commercial API | $$ | Latency-sensitive fallback |
| Claude Haiku 4.5 | 200K | ~0.5s | Acceptable | Commercial API | $ | Eval `runQuick()` |
| GPT-4.1 | 1M | ~2s | Good | Commercial API | $$$ | Comparable quality |
| Gemini 2.5 Pro | 1M | ~2s | Good | Commercial API | $$ | Longer context window |
| Llama 3.3 70B | 128K | ~5s (local) | Fair | Open weights | Free | Local privacy option |
| MLX Qwen 3 | 32K | ~2s (M-series) | **Excellent** | Open weights | Free | Future: offline mode |

---

## Project Structure

```
Sources/AllTimeRecorded/
├── App/
│   ├── Main.swift                    @main, --probe-claude CLI mode
│   ├── AppDelegate.swift             Wires all 9 DataSources + services
│   ├── AppModel.swift                @Published snapshot + recording mode
│   └── MicrophonePermissionManager.swift
├── AI/
│   ├── LLMClient.swift               Protocol: stream() + complete()
│   ├── AnthropicClient.swift          Actor: SSE streaming, dual auth headers
│   ├── AnthropicStreamingDecoder.swift SSE parser
│   ├── PromptComposer.swift           6 prompt kinds → (system, user) pairs
│   ├── PromptTemplates.swift          7 versioned static let prompts
│   └── KeychainStore.swift            Keychain + env var fallback
├── RAG/
│   ├── LEANNBridging.swift            Protocol: search(), searchRaw(), ask()
│   ├── LEANNBridge.swift              Actor: subprocess, timestamp extraction
│   ├── DataSource.swift               Protocol + SourceChunk struct
│   ├── MailDataSource.swift           → mail_index
│   ├── WeChatDataSource.swift         → wechat_history / wechat_recent / imessage_index
│   ├── TranscriptDataSource.swift     → transcripts_index / files_index
│   ├── CalendarDataSource.swift       → EventKit (broad match for schedule queries)
│   ├── RemindersDataSource.swift      → EventKit (broad match for todo queries)
│   ├── FileDataSource.swift           → Spotlight mdfind + LEANN fallback
│   ├── CrossRefEngine.swift           Parallel fanout + dedupe + rerank
│   └── DayContextLoader.swift         Async LEANN fetch per day for heatmap
├── Workflow/
│   ├── AgentSession.swift             Question → retrieve → scrub → compose → stream
│   ├── BriefingService.swift          Pre-meeting / digest / proactive / file gather
│   ├── BriefingModels.swift           Briefing, Highlight, ActionItem
│   ├── MeetingTriggerWatcher.swift    Calendar T-5min notifications
│   └── DigestScheduler.swift          Daily 19:13 digest
├── Security/
│   ├── GuardrailGate.swift            Input sanitize + chunk scrub + output validate
│   └── AuditLog.swift                 JSONL append-only + production hit rate
├── Eval/
│   └── EvalService.swift              10 golden + 3 adversarial, hit/hallucination/block rates
├── Timeline/
│   ├── DayBinMapper.swift             96 bins from recording segments + loudness
│   ├── ContextDensityBinMapper.swift  Multi-source density merge + ambient fallback
│   └── CalendarArcMapper.swift        Event → arc segments
├── Recording/
│   ├── RecordingMode.swift            Gentle / Manual / Rogue enum
│   ├── RecordingPolicy.swift          Protocol + factory
│   ├── GentleRecordingPolicy.swift    No auto-start, calendar nudge
│   ├── ManualRecordingPolicy.swift    Explicit start/stop only
│   └── RogueRecordingPolicy.swift     Auto-record on launch
├── UI/
│   ├── MainDashboardView.swift        Main window: heatmap + arcs + ripple cloud
│   ├── StatusBarController.swift      Menu bar + context menu + API Settings
│   ├── MainGlassWindowController.swift Liquid Glass window host
│   ├── TimelineHeatmapPanel.swift     96-bin grid with multi-source colors
│   ├── HeatmapPalette.swift           Single-source + context density color modes
│   ├── Theme.swift                    neonCyan #47E6F2 + 6 source colors
│   ├── GlassMaterialView.swift        NSGlassEffectView (macOS 26+) + fallback
│   ├── APISettingsWindow.swift        URL + Token + Model + Test button
│   └── Briefing/
│       ├── AgentChatView.swift        Streaming chat + citations + feedback + file drag
│       ├── AgentChatViewModel.swift   State machine + proactive brief + file gather
│       ├── CitationChip.swift         Clickable source reference with popover
│       ├── StreamingTokenText.swift   Markdown rendering (bold/italic/code/[N] citations)
│       └── FileTransferRepresentation.swift  NSPasteboard multi-file drag
└── Core/
    ├── Models.swift                   DayBin (+ 5 density fields), RecordingSegment, etc.
    ├── Protocols.swift                RecordingService, PowerAssertionService
    ├── AppConstants.swift             Sample rates, thresholds, model URLs
    ├── LLMEndpointConfig.swift        UserDefaults-backed URL/format/model
    ├── QueryModels.swift              QueryResult, QueryService
    └── CalendarModels.swift           CalendarOverlayEvent, CalendarArcSegment
```

---

## Quick Start

```bash
git clone https://github.com/torrent-lake/catchmeup.git
cd catchmeup
swift build
swift test   # 18 tests

# Store your API key
security add-generic-password -U -s com.catchmeup.anthropic -a default -w "YOUR_TOKEN"

# Optional: set relay URL
defaults write AllTimeRecorded CatchMeUp.llm.baseURL "https://your-relay/api"

# Launch
.build/debug/AllTimeRecorded
```

---

## License

Private repository. Cornell NBA 6170 course project.
