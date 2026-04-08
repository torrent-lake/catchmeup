# 2026-04-08 — Day 0: Planning session and Phase 0 docs

> This is the first entry in the CatchMeUp changelog. Read `docs/HANDOFF.md` first if you are new.

## What happened today

A long planning conversation produced the first fully specified implementation plan for the CatchMeUp pivot. Before today, `~/project/catchmeup` was a freshly cloned copy of `~/project/alltimerecorded` — same code, different repo, no new identity. After today, the repo has a complete plan, a complete set of reference docs, and a clear Phase 0 → Phase 4 delivery path.

## What was decided

The short version is in `docs/PLAN.md` §17 (the one-sentence test). The longer version:

1. **Identity pivot**: from "dashcam for your life" (AllTimeRecorded) to "a trusted system for everything you didn't write down" (CatchMeUp). Recording is demoted from always-on default to one of four data sources, opt-in by default. Three recording modes: Gentle (default, calendar-driven nudge) / Manual / Rogue (legacy open-lid behavior preserved as opt-in).
2. **Primary KPI**: Query Hit Rate. Target ≥85% on a controlled golden eval set, ≥70% user-confirmed in production. Measured per-answer via 👍/👎/"wrong source" inline feedback. Rejected earlier drafts that tried to measure softer things like "permission to forget index" or "self-reported letting-go Likert" — those felt academic and un-actionable. Hit rate is the Inbox-Zero-style operational metric.
3. **Business objective framing**: soft problem-solution tone, centered on "brain fog" moments. Avoids cute language ("放下感", "笔记频次下降"). Uses GTD's "trusted system" as the conceptual anchor because it's well-understood in MBA curricula.
4. **LEANN is the RAG layer**. No in-Swift vector store. Subprocess calls to the CLI, existing mail_index and wechat_history indices reused as-is. LEANN supports `--llm anthropic` natively for scoped single-source queries; cross-source fusion is implemented in Swift on top of parallel `leann search` fanout + Claude synthesis.
5. **Claude Opus 4.6 is the default generation model**. Unlimited-Opus budget removes the cost objection. `LLMClient` protocol keeps Sonnet/Haiku swappable for latency-sensitive paths.
6. **The TimelineHeatmapPanel is reinterpreted, not deleted**: it becomes a context density heatmap (layered recording + mail + chat + file activity density per 15-min bin). This is the clever reuse that ties the existing beautiful UI to the new identity.
7. **Prompts are versioned, transparent, shipped as readable constants** in `PromptTemplates.swift`. Published in `docs/PROMPT_LIBRARY.md`. Transparency over obfuscation is a deliberate rubric play under Stage 3 Interpretability.
8. **Guardrails built against the AI Agents Under Threat paper's 4-gap taxonomy**, with primary attention to Gap 4 (indirect prompt injection via retrieved content). Four defense layers: input sanitization, chunk scrubbing, prompt isolation via `<source>` tags, output validation. See `docs/SECURITY_THREATS.md`.
9. **Explicit PII masking decision**: we do NOT mask general PII (names, emails, phone numbers) from retrieved chunks because it breaks the core value prop ("who emailed me?"), but we DO sanitize credential patterns (CC, SSN, API keys, passwords) in the output. Documented with rationale so the rubric's Confidentiality criterion is earned with an argument, not a blind restrictive filter.
10. **Phase 0 persists everything to GitHub first**. The user specifically asked for zero-cost handoff to a future agent — clone the repo, read HANDOFF.md, be productive in 5 minutes. This entry is part of that commitment.

## What I built today

Files created in `docs/`:

- `PLAN.md` — full 17-section implementation blueprint (copy of session plan at `~/.claude/plans/humble-doodling-aurora.md`)
- `HANDOFF.md` — first-read guide for future agents / contributors
- `CONTEXT.md` — course, professor, rubric transcription, framework, peer-grading context
- `RUBRIC_ALIGNMENT.md` — mapping matrix: rubric criterion → plan element → evidence file → status
- `SECURITY_THREATS.md` — applied 4-gap threat model, defense layers, explicit PII decision
- `LEANN_INTEGRATION.md` — CLI reference, existing indices state, Swift subprocess contract, known quirks
- `REPORT_REFERENCE.md` — verbatim NBA 6145 Catch Me Up report + NBA 6170 evolution notes
- `PROMPT_LIBRARY.md` — V1 prompts, injection-defense wrapper convention, model selection rationale, RAG-vs-LoRA argument
- `changelog/2026-04-08-day0-planning.md` — this file

Directory scaffolding:
- `docs/changelog/` for narrative session logs
- `docs/eval/` for golden set and adversarial corpus (populated in Phase 3)
- `docs/pitch/` + `docs/pitch/slides/` for pitch script and deck assets (populated in Phase 4)

Code changes: **zero**. Phase 0 is docs-only by design. Phase 1 (identity flip) begins in the next session.

## What I learned / was surprised by

- **LEANN is already further along than I expected.** The user's machine has `mail_index` (26 MB) and `wechat_history_magic_test_11Debug_new` (43 MB) already built and searchable via LEANN's MCP server. I can query them right now from Claude Code via `mcp__leann-server__leann_search`. This collapses Phase 2's estimated work significantly — we don't need to build any data ingest pipelines for mail or chat, just wrap the existing CLI.
- **The existing codebase is cleaner than expected.** AllTimeRecorded's recording service is cleanly abstracted behind a protocol; the trigger is hardcoded in `AppDelegate` (one line: `requestMicrophoneThenStart()`). Flipping the identity is *additive* at the trigger layer, not a rewrite of the recording pipeline. The `CalendarOverlayService` already publishes `@Published currentEvents` via Combine, so `MeetingTriggerWatcher` subscribes instead of polling.
- **Lutz's rubric is denser than the PDF version.** The `.docx` version of the AI Model Rubric is the full genAI manual and has criteria the PDF version doesn't (prompt stability under multicollinearity, adversarial stress tests, instruction following, human evaluation, longitudinal monitoring, feedback loops). Every criterion is now mapped in `docs/RUBRIC_ALIGNMENT.md`.
- **The AI Agents Under Threat paper's 4-gap taxonomy is a perfect frame for the pitch's security slide.** Gap 4 (untrusted external entities → indirect prompt injection) is exactly the threat a personal memory tool faces, and the defense story ("we sanitize retrieved content, wrap it in `<source>` tags, and tell the LLM to treat source content as untrusted data") is demonstrable in under 10 seconds on stage. This is Scene 3 of the pitch demo in `docs/PLAN.md` §10.
- **The user already pushed both `alltimerecorded` and `catchmeup` to public GitHub earlier in the session**, so Phase 0 docs can be published without re-negotiating repo setup. This is a faster start than expected.

## What's open / unresolved

Questions listed in `docs/PLAN.md` §16 remain open but don't block Phase 1:

- Transcript confidence threshold for Whisper segment filtering
- Digest time default (currently 7:13 PM, arbitrary)
- Hotkey for Agent Chat (⌥⌘Space conflicts with Alfred/Raycast for some users — need a fallback)
- Rename `AllTimeRecorded` → `CatchMeUp` timing (planned for Phase 4 to keep early diffs clean)
- Whether to build a `LEANNDaemonClient` in Phase 2 or Phase 4 for the latency win

## What I'd do next (if the next session starts from this changelog alone)

1. **Verify git state**: `cd ~/project/catchmeup && git status && git log --oneline -5`. Should show the Phase 0 docs commit.
2. **Confirm existing LEANN indices still work**: `leann list` (should show mail_index + wechat_history_magic_test_11Debug_new as ✅).
3. **Enter Phase 1**. Create the new directories per `docs/PLAN.md` §4.3:
   - `Sources/AllTimeRecorded/Recording/`
   - `Sources/AllTimeRecorded/AI/`
   - `Sources/AllTimeRecorded/RAG/`
4. **First code change**: create `Recording/RecordingMode.swift` as the enum + UserDefaults bridge. No LLM yet, no LEANN call yet, just the mode concept.
5. **Second code change**: create `Recording/RecordingPolicy.swift` protocol + `GentleRecordingPolicy` (no-op on appLaunched), `ManualRecordingPolicy` (no-op), `RogueRecordingPolicy` (current AllTimeRecorded behavior).
6. **Third code change**: modify `App/AppDelegate.swift` to instantiate the policy based on `UserDefaults.recordingMode` and call `policy.appLaunched()` instead of `requestMicrophoneThenStart()`. Gate the Rogue path behind `UserDefaults.recordingMode == .rogue` for now.
7. **Acceptance check**: `swift build` passes. Launching the app with `defaults write <bundle> CatchMeUp.recordingMode manual` followed by a launch should NOT start recording. Launching with `rogue` should.
8. Write a second changelog entry. Commit and move on.

## Handoff-readiness checklist

- [x] `docs/HANDOFF.md` exists and points at read order
- [x] `docs/PLAN.md` exists and is the full approved plan
- [x] `docs/CONTEXT.md` has the rubric and course context
- [x] `docs/RUBRIC_ALIGNMENT.md` has the mapping matrix
- [x] `docs/SECURITY_THREATS.md` has the threat model and defenses
- [x] `docs/LEANN_INTEGRATION.md` has the CLI and Swift contract
- [x] `docs/REPORT_REFERENCE.md` has the source material for pitch narration
- [x] `docs/PROMPT_LIBRARY.md` has the V1 prompts with injection-defense convention
- [x] `docs/changelog/` has this entry
- [ ] Pushed to GitHub (pending the final commit of this session)

Once the commit lands, any new agent can clone the repo and be oriented in 30 minutes without conversational context. That was the non-negotiable outcome of Phase 0.

---

**Session stats**: ~5 hours elapsed, 9 doc files created, 0 code files changed, 1 plan file approved. Next session targets: commit + push Phase 0, then Phase 1 code begins.
