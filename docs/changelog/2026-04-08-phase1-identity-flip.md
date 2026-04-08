# 2026-04-08 — Phase 1: Identity flip

> Second entry of the day. See `2026-04-08-day0-planning.md` for the planning
> session that produced this work, and `docs/PLAN.md` §11 Phase 1 for the spec.

## What shipped

**Phase 1 is complete.** The app's identity has flipped from "dashcam for your
life" (AllTimeRecorded) to "a trusted system for everything you didn't write
down" (CatchMeUp), with the full recording-policy abstraction, LEANN bridge
plumbing, Keychain-backed auth token storage, and a briefing dashboard that
reads as a real product surface — not a developer scaffold.

### Files created (13 new)

- `Recording/RecordingMode.swift` — enum + `UserDefaults.recordingMode` bridge
- `Recording/RecordingPolicy.swift` — protocol + `RecordingPolicyFactory`
- `Recording/GentleRecordingPolicy.swift` — default, no auto-record at launch
- `Recording/ManualRecordingPolicy.swift` — user-driven only, zero automation
- `Recording/RogueRecordingPolicy.swift` — legacy open-lid auto-record, opt-in
- `RAG/LEANNBridging.swift` — protocol (enables mock for tests)
- `RAG/LEANNBridge.swift` — `actor`-based subprocess wrapper with binary
  resolution, async continuation-based `Process` execution, pipe collectors,
  timeout guard, and a best-effort line-based output parser
- `RAG/DataSource.swift` — `DataSource` protocol + `SourceChunk` struct (the
  universal currency of the retrieval layer)
- `RAG/MailDataSource.swift` — concrete wrapping `mail_index`
- `AI/KeychainStore.swift` — Keychain + env-var-fallback storage for the LLM
  auth token. Supports `ANTHROPIC_AUTH_TOKEN` (relay) and `ANTHROPIC_API_KEY`
  (direct) as dev fallbacks.
- `Core/LLMEndpointConfig.swift` — `UserDefaults`-backed baseURL, apiFormat
  (`anthropic` / `openai`), defaultModel (`claude-opus-4-6`). Snapshot struct
  for passing to Phase 2's `AnthropicClient`.
- `UI/Briefing/BriefingDashboardView.swift` — the new main window content.
  4-panel layout with product-level empty states, a watching-status line,
  and a pulsing recording-mode badge. NO developer affordances in this view.

### Files modified (5)

- `App/AppDelegate.swift` — no more auto-start. Recording launch is now routed
  through `RecordingPolicy.appLaunched()`. The policy is built from
  `UserDefaults.recordingMode`, and a mode change from the status bar menu
  stops the current policy, rebuilds a new one, and calls `appLaunched()`.
  Also calls `paths.ensureBaseDirectories()` (so the new `briefings/` dir is
  created) and opens the main window on launch so the new identity is
  immediately visible.
- `App/AppModel.swift` — new `@Published var recordingMode` that mirrors
  `UserDefaults.recordingMode` so views can observe it.
- `Storage/AppPaths.swift` — new paths: `briefingsRoot`, `auditFileURL`,
  `consentFileURL`. `ensureBaseDirectories()` now creates the briefings dir.
- `UI/MainGlassWindowController.swift` — primary content is now
  `BriefingDashboardView`. The legacy `MainDashboardView` (heatmap) remains
  in the source tree, unused, ready for the Phase 3 context-density
  reinterpretation. Window title changed to `"CatchMeUp"`.
- `UI/StatusBarController.swift` — three new mode toggle menu items
  (`Recording: Gentle/Manual/Rogue`) with live checkmarks synced to
  `AppModel.recordingMode`. Debug-only `Debug: Probe LEANN` menu item
  wrapped in `#if DEBUG` that runs an `NSAlert` with the LEANN probe result.
  In release builds, this entire item disappears. New constructor argument
  `leannBridge` forwarded to `MainGlassWindowController`. Tooltip and
  debug-log strings retain the "AllTimeRecorded" bundle id (rename deferred
  to Phase 4 per plan).

## What deviated from the plan

1. **UI scope**: The PLAN.md §11.1 acceptance list said "A dev-only 'Test
   LEANN' button issues `leann search mail_index "hello"` and shows the 5
   chunks raw." I initially built this as a button + raw output pane directly
   inside `BriefingDashboardView`, visible to users. The user correctly called
   this out as leaking implementation details into the product surface
   ("这个窗口是我们的产品页面吗？"). I moved the probe to a `#if DEBUG`
   status bar menu item that displays results in an `NSAlert`, and rewrote
   the 4 panel empty states from phase-documentation placeholder text into
   product-level copy that communicates what each panel will eventually show.
   **Lesson saved as a design principle for future phases** (see §"Design
   Principles Learned" below).

2. **Added `LLMEndpointConfig.swift`** (not explicitly in §11.1 scope):
   The user asked mid-session for the Phase 2 `AnthropicClient` to support
   a configurable base URL and both Anthropic/OpenAI API formats, because
   they're using a Claude Code-compatible relay service
   (`https://code.milus.one/api`). I added `LLMEndpointConfig` now as plumbing
   so Phase 2 can consume it immediately. No runtime behavior change in
   Phase 1 — the struct is just read but not called.

3. **Added `Recording/ManualRecordingPolicy.swift` and
   `Recording/RogueRecordingPolicy.swift`** (plan listed only Gentle
   explicitly). These were implicit in the acceptance ("Mode toggle in
   Settings switches between Gentle/Manual/Rogue, Rogue actually starts
   recording") but not in the create list. Added for completeness so the
   three-mode acceptance is actually testable.

4. **Split `RAG/MailDataSource.swift` out of `RAG/DataSource.swift`**
   (plan listed them together). Separate file for easier future addition of
   `WeChatDataSource` / `TranscriptDataSource` / `FilesDataSource` in Phases
   2–3 without one giant file.

## Acceptance verification

- `swift build`: green (one unused warning in legacy `RecallPanelView.swift`,
  not introduced by this work)
- `swift test`: all 18 tests passing, zero regression
- Launch from `.build/debug/AllTimeRecorded`:
  - App starts, `briefings/` directory is created under the app support root
  - Main window opens automatically showing `BriefingDashboardView`
  - Status bar icon appears (style inherited from previous `statusIconStyle`
    UserDefault, `radialNeedle12`)
  - In Gentle mode (default): `find -mmin -2` in the audio directory returns
    no new segments. **Recording does not auto-start.** Confirmed over a
    multi-minute observation window.
- LEANN CLI smoke test: `leann search mail_index "hello" --top-k 5` returns
  5 scored results with recognizable structure. `LEANNBridge.parseSearchOutput`
  regex matches the `"N. Score: ..."` header format.
- LLM endpoint config: `defaults read AllTimeRecorded | grep 'llm\.'` shows
  `baseURL = https://code.milus.one/api`, `apiFormat = anthropic`,
  `defaultModel = claude-opus-4-6`.
- Keychain slot verified via
  `security find-generic-password -s com.catchmeup.anthropic -a default`:
  exists with `acct=default`, created `20260408 22:05:48Z`. Actual token
  value not inspected (by design — never print secret material).
- User visually confirmed the new briefing dashboard reads as a product page
  ("应该好了").

## Design principles learned

These are now the rules for all future phases. Updates to `docs/CONTEXT.md`
will fold them in on the next doc-only commit.

1. **Empty states are not roadmap text.** An empty panel must read as a
   finished product waiting for content, not as "Phase N populates this".
   Gmail's empty inbox says "No new messages," not "Feature placeholder."
2. **Third-party implementation details never leak into UI strings.** No
   "LEANN", "Whisper", "SQLite", "Claude" strings in any user-facing surface.
   Internal code comments, docs, and debug affordances are fine; the user-
   facing product page is not.
3. **Developer affordances live behind `#if DEBUG`** or a hidden UserDefaults
   flag. They never appear in the primary product surface, even during
   development. The status bar right-click menu is a legitimate location for
   `#if DEBUG`-wrapped items because it's secondary and discoverable only
   by intent.
4. **Every visible element must be valuable to the end user.** If a view
   element exists to help me debug, it needs to be in a debug-only path.

## Open things for Phase 2 (next session)

- User has placed the LLM auth token in Keychain (service
  `com.catchmeup.anthropic`, account `default`). The relay base URL is set
  in `UserDefaults`. `KeychainStore.readLLMAuthToken()` returns the token
  without revealing the value to logs or stdout.
- Phase 2 begins with `AI/AnthropicClient.swift`: an `actor`-based streaming
  HTTP client that reads `LLMEndpointConfig.snapshot()` and the Keychain
  token, constructs requests using the configured API format (`.anthropic`
  / `.openai`), and exposes the plan's `LLMClient` protocol.
- The first real Claude call is the simplest one: a smoke test in a new
  `Debug: Probe Claude` status bar menu item that sends a 10-token
  "reply with only the word 'hello'" completion and verifies the response.
  This proves the relay + token + HTTP path end-to-end before we wire up
  `CrossRefEngine` and `BriefingService`.
- The user recommended starting with the relay (Claude Opus 4.6 quality)
  and adding local MLX Qwen as a Phase 3+ "Offline Mode" backend. Recorded
  in Phase 2 prep notes in `docs/PLAN.md` §2 D3.

## Reminder: token rotation

The auth token `cr_...` was pasted into the planning conversation transcript
and is now in the persistent chat history for this session. Rotate the token
at the relay provider (`code.milus.one`) **after** Phase 2 is confirmed
working end-to-end. The replacement token can be loaded into Keychain via
the same one-liner:

```bash
security add-generic-password -U -s com.catchmeup.anthropic -a default -T "" -w
```

(interactive prompt, no token value touches shell history).
