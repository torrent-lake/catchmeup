# CatchMeUp — Handoff Guide

> If you are a new agent or developer picking this project up, this is the first file you read.
> Budget: 30 minutes, and you should be productive. 5 minutes if you only need to resume mid-task.

---

## 1. What this project is, in two sentences

CatchMeUp is a local-first macOS app that answers "I think someone said something about..." moments by cross-referencing the user's mail, chat (WeChat), meeting transcripts, files, and calendar — all indexed locally via [LEANN](https://github.com/yichuan-w/LEANN), all synthesized by Claude Opus 4.6 with source-cited answers. It is being rebuilt on top of an existing, polished macOS app called AllTimeRecorded (Liquid Glass UI, Whisper transcription, EventKit integration) — the capture layer stays, the identity pivots from "dashcam for your life" to "the trusted system for everything you didn't write down."

## 2. Read order (strict)

1. **`docs/CONTEXT.md`** — the course (NBA 6170 AI Solutions, Prof. Lutz Finger, Cornell), the grading rubric (50/20/30), the professor's framework (Feasible / Actionable / Feedback / Ethical), and the constraint that this will be peer-voted by MBA classmates with industry experience. **5 min.**
2. **`docs/PLAN.md`** — the full implementation blueprint. 17 sections. Read once end-to-end. **20 min.** If you are time-pressed, read §0 (Context), §1 (The Spine — hit rate KPI), §2 (Strategic Decisions), §11 (Phased Delivery), and §17 (the one-sentence test).
3. **`docs/changelog/`** — read the most recent entry (chronologically latest filename). This tells you where the project *actually* is, which may diverge from where the plan thinks it should be. **3 min.**
4. **`docs/RUBRIC_ALIGNMENT.md`** — verify your next action advances a rubric criterion. If it doesn't, reconsider. **2 min.**
5. Code. You are now oriented.

## 3. The one-sentence test

> *"CatchMeUp is the tool that makes 'I think someone said...' into a solved problem, measured by hit rate, defended by guardrails, and earned by trust."*

Every proposed change must advance that sentence. If it doesn't, it's out of scope and belongs in the Phase 5 wishlist in `docs/PLAN.md` §11.

## 4. Key locations

| Thing | Path |
|---|---|
| App source | `Sources/AllTimeRecorded/` (renamed to `Sources/CatchMeUp/` in Phase 4) |
| Tests | `Tests/AllTimeRecordedTests/` |
| This repo | `https://github.com/torrent-lake/catchmeup` (public) |
| Sister repo (original recorder) | `https://github.com/torrent-lake/alltimerecorded` (public, frozen) |
| Local LEANN install | `/Users/yizhi/leann/` |
| Existing LEANN indices | `mail_index` (26 MB), `wechat_history_magic_test_11Debug_new` (43 MB) — both already built, usable immediately |
| User data root (app support) | `~/Library/Application Support/AllTimeRecorded/` (→ `CatchMeUp/` in Phase 4) |
| Audio segments | `~/Library/Application Support/AllTimeRecorded/audio/YYYY-MM-DD/*.m4a` |
| Whisper transcripts | `~/Library/Application Support/AllTimeRecorded/transcripts/YYYY-MM-DD/transcript.json` |
| Whisper model | `~/Library/Application Support/AllTimeRecorded/models/ggml-large-v3-turbo-q5_0.bin` |
| Whisper binary | `~/Library/Application Support/AllTimeRecorded/models/whisper-cli` |
| Eval reports (once Phase 3 lands) | `~/Library/Application Support/CatchMeUp/eval/` |
| Plan file (session copy) | `~/.claude/plans/humble-doodling-aurora.md` (same content as `docs/PLAN.md`) |

## 5. Current state snapshot

**Last updated**: see the most recent file in `docs/changelog/`.

**Infrastructure already in place** (do NOT rebuild):
- macOS Swift Package (`Package.swift`), macOS 15+ target, Swift 6.2, single executable
- Liquid Glass UI (`Theme.swift` with neonCyan #47E6F2, `GlassMaterialView` with macOS 26+ `NSGlassEffectView` + fallback)
- Recording pipeline (AVAudioRecorder → 30-min segments → daily merge → Whisper.cpp via subprocess)
- Calendar integration (`SystemCalendarProvider` via EventKit, `ICSBasicParser` for local ICS files, `CalendarOverlayService` publishing `@Published currentEvents`/`currentArcs`)
- Menu-bar status icon with dynamic `StatusTimelineImageFactory` rendering
- Recall panel scaffold (currently keyword-only, to be rewired to agent chat in Phase 2)
- Onboarding view (3-step, glass-styled)
- EventStore JSONL persistence with unclean-shutdown recovery
- Sleep/wake monitoring, power assertions, disk-guard low-space pausing
- 6 test files covering heatmap, calendar arcs, daily-merged encoder, ICS parser, timeline marker

**What does NOT exist yet** (Phase 1+ work):
- Any LLM client (no `anthropic` import, no Claude calls, no streaming)
- Any LEANN integration (no subprocess wrapper, no cross-source fusion)
- Any guardrail / injection defense
- Any eval harness / golden set / hallucination checker
- The `RecordingPolicy` abstraction (recording auto-starts on launch today)
- The briefing dashboard (today's main window is recording-centric)
- The context-density heatmap reinterpretation
- Settings UI for mode toggle / source consent / eval results

## 6. Daily discipline (non-negotiable)

- **Every significant session ends with a new changelog entry** at `docs/changelog/YYYY-MM-DD-<slug>.md`. Format:
  - What I did
  - What I learned (or was surprised by)
  - What's broken or open
  - What I'd do next
  - Prose narrative, not commit messages. Written so a future agent reading this alone can reconstruct the session.
- **Commits** follow conventional style: `feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`. Never skip hooks. Never force-push main.
- **Every PR-sized change** that touches a rubric-relevant criterion updates `docs/RUBRIC_ALIGNMENT.md` (the mapping table).
- **Every new LLM call or prompt template** gets a version bump in `docs/PROMPT_LIBRARY.md` with rationale.
- **Every guardrail / security decision** gets an entry in `docs/SECURITY_THREATS.md` with a link to the paper or threat model it addresses.

## 7. Things that surprise people

1. **Recording is not the product.** It is one of four data sources, opt-in by default. If your instinct is to start recording on launch, stop. Read `docs/PLAN.md` §2 D4.
2. **LEANN already has mail_index and wechat_history built.** You do not need to build them. Run `leann list` to verify; they are listed under `Other Projects → leann`. Do NOT rebuild them unless the existing indices are corrupted.
3. **LEANN supports `--llm anthropic` natively.** For scoped single-source queries (`@mail` prefix in the user's query), we use `leann ask mail_index --llm anthropic ...` directly — no Swift-side Claude call needed. Only cross-source fusion calls Claude from Swift.
4. **The TimelineHeatmapPanel is not legacy — it is being reinterpreted.** Do not delete it. Its new role is "context density heatmap," layering recording + mail + chat + file activity density per 15-minute bin. See `docs/PLAN.md` §2 D5.
5. **The app is NOT sandboxed.** `com.apple.security.app-sandbox = false` in `AppTemplate/AllTimeRecorded.entitlements`. This is intentional — we need full filesystem access for LEANN subprocess calls and Whisper model paths. Do not turn sandboxing on without updating the entire plan.
6. **We do NOT mask PII in retrieved chunks before sending to the LLM.** The data is the user's own. We DO sanitize credential patterns (CC / SSN / passwords) in the *output*. See `docs/SECURITY_THREATS.md` for the explicit rationale — this is a deliberate, documented decision.
7. **The two sister repos (`alltimerecorded` and `catchmeup`) share an initial commit history.** Do not attempt to merge them or rebase. They intentionally diverge from commit `039f1bb`.

## 8. If something is broken and you can't figure out why

1. Check `docs/changelog/` — the latest entry often explains in-flight debugging.
2. Check `git log --oneline -20` — the commit history tells the architectural story.
3. Check `~/Library/Application Support/AllTimeRecorded/meta/events.jsonl` — recording state, gaps, and sleep/wake transitions are logged there.
4. Check `~/Library/Application Support/CatchMeUp/audit.jsonl` (once Phase 3 is live) — every query, every injection block, every refusal is logged.
5. Run `swift build` from the repo root — compile errors point to the exact file.
6. Run `swift test` — regression suite covers heatmap math, calendar arc mapping, ICS parsing, audio encoding.
7. If LEANN subprocess calls fail, test them manually: `cd /Users/yizhi/leann && source .venv/bin/activate && leann search mail_index "hello" --top-k 3`. If LEANN itself is broken, that's a LEANN problem, not a CatchMeUp problem — fix it in `/Users/yizhi/leann` and the fix flows through.

## 9. When in doubt

- **Does this change raise hit rate?** If yes, prioritize. If no, justify why it still belongs in the current phase.
- **Does this change earn a rubric point?** Cross-check `docs/RUBRIC_ALIGNMENT.md`.
- **Does this change compromise the local-first story?** If it adds a cloud dependency, network telemetry, or a vendor lock-in, stop and raise it explicitly.
- **Would Rewind have survived if it had this property?** Rewind is the cautionary tale cited in the plan (§1.3). Every architectural decision can be cross-checked against "would this keep Rewind alive under 2025 regulation?"

## 10. Open questions (as of the most recent changelog)

These do not block execution but should be resolved as they come up. See `docs/PLAN.md` §16 for the authoritative list. Examples: transcript confidence threshold, digest time default, hotkey conflict fallback, rename timing.

---

**You are now oriented. Go read `docs/CONTEXT.md` next.**
