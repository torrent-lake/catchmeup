# NBA 6145 Catch Me Up Report — Verbatim Reference

> Full text of the 10-page report written by Yizhi Li for NBA 6145 (AI Strategy and Applications), Spring 2026, individual workflow assignment.
>
> **Purpose**: pitch script source material for NBA 6170. Every framing, every number, every competitive reference, every prompt template in the pitch video traces back to this document. When writing marketing copy or pitch narration, quote or paraphrase from here rather than inventing new material.
>
> **Source**: `/Users/yizhi/Documents/25spring/4280/report.pdf` — same text, transcribed below for in-repo reference.

---

# Catch Me Up
## An AI-Powered Personal Memory Workflow
### "Shoot first, focus later."

NBA 6145 — AI Strategy and Applications
Individual Assignment: Workflow
Yizhi Li · Spring 2026

---

## The Problem: Your Day Generates More Than You Can Keep

Every day as a graduate student, you absorb information from dozens of sources: a three-hour lecture, a networking chat over coffee, 40 emails, downloaded case studies, a hallway exchange about a shifted project deadline. By evening, half of it is gone. By next week, most of it is.

The brain is not built for lossless capture. We lose the name of someone we just met. We forget the aside the professor made about what the final deliverable actually requires. We miss the Slack message about a changed meeting room — because we were in another meeting.

**The core question**: What if you could say "catch me up" at any moment — and an AI assistant could reconstruct what happened, what you missed, and what needs your attention?

Catch Me Up is a working workflow that combines passive audio capture, calendar context, email signals, and downloaded files into one on-demand personal memory layer. It does not replace your attention. It insures against its limits.

---

## Market Context: A Category Without a Winner

### Rewind → Limitless → Meta (and the Privacy Lesson)

Rewind (2022) was the first serious attempt at a personal memory tool for Mac. It recorded your entire screen — every tab, document, and video call — compressed it 3,750×, and made it searchable. The key selling point: everything stayed on your device, processed locally by Whisper. No cloud. $33M in funding from a16z and Sam Altman.

Then came the pivot. In April 2024, Rewind rebranded to Limitless and launched a $99 wearable pendant focused on meeting capture. The architecture shifted: recordings moved to a "Confidential Cloud." In December 2025, Meta acquired the company for its wearables division. The Rewind app was shut down. Service in the EU, UK, Brazil, and China was terminated overnight due to GDPR concerns.

The privacy trajectory tells the whole story: local-first → cloud → Meta's data infrastructure → regional shutdown. Users who built workflows around Rewind lost access with two weeks' notice.

**What we take from this**: The demand is proven ($33M, Meta acquisition). But the moment you leave the device, you inherit every privacy liability in the book. Local-first is not just a feature — it is the only architecture that survives contact with regulation and acquisition.

### Typeless and the New Standard for Speech AI

Typeless (launched November 2025) is not a memory tool, but it sets the bar for what speech-to-text now means. Using LLMs, it removes filler words, auto-corrects mid-sentence, adapts tone per application, and outputs at 158 WPM. This is not your father's dictation software.

The same AI-driven transcription quality is what makes Catch Me Up viable. The audio captured throughout your day is not garbled — it is clean, readable text that a language model can reason over, cross-reference, and summarize.

### Where We Fit

| Capability | Existing Tools | Catch Me Up |
|---|---|---|
| Audio capture | Otter.ai, Limitless (shut down) | All Time Recorded |
| Calendar awareness | Apple/Google Calendar | Cross-referenced with audio |
| Email context | Gmail, Outlook | Linked to events & deadlines |
| File awareness | Spotlight, Finder | Content-indexed via RAG |
| Cross-source synthesis | — | **Core differentiator** |
| On-demand "catch me up" | — | **Primary interface** |

No single tool connects these sources into a queryable personal memory. That gap widened when Limitless disappeared.

---

## The Concept: "Shoot First, Focus Later"

Modern smartphones capture a burst of raw sensor data the instant you press the shutter. Focus, exposure, and HDR are applied after the fact. You never miss the shot because the processing happens later.

Catch Me Up applies this principle to your daily information flow:

1. **Capture passively.** All Time Recorded runs in the background — audio is transcribed by Whisper with zero manual effort. Calendar events, emails, and downloads already exist in your digital life.
2. **Process on demand.** No heavy background computation. When you say "catch me up," the Agent activates, pulls the relevant sources, cross-references, and synthesizes. Compute is spent only when you need the output.
3. **Keep the human in charge.** You choose when to invoke it, what time range to query, which sources to include. The system is a tool, not an autopilot.

**Design principle**: Capture like a dashcam. Process like a search engine. Present like a trusted assistant. **The human steers.**

---

## Privacy Architecture: Why Local-First Wins

Rewind proved the market. Its collapse proved the architecture matters more than the product.

The moment Rewind moved from local processing to cloud infrastructure, it inherited compliance obligations in every jurisdiction it operated in. When Meta acquired it, EU and UK users lost access within two weeks. The lesson is not "privacy is hard" — it is that **cloud-dependent personal data tools have a structural fragility that local-first tools do not**.

Catch Me Up is designed around this insight:

| On-Device Only | Whisper runs locally. Transcripts are stored locally. The RAG vector index (ChromaDB) lives on your machine. No audio or text is uploaded anywhere. |
|---|---|
| Audio, Not Screen | Rewind captured screen content — resource-intensive and privacy-invasive (passwords, DMs, financial data all visible). Catch Me Up captures audio only: the most information-dense signal at a fraction of the storage and exposure. |
| User-Controlled | Recording is pausable. Processing is opt-in. Deletion is immediate. You decide what the system touches. |
| No Vendor Lock-in | Because everything is local, there is no "service shutdown" risk. Your data does not disappear when a startup gets acquired. |

New York is a one-party consent jurisdiction — a participant in a conversation can record it. Combined with a local-first architecture, Catch Me Up avoids both the legal exposure and the trust problem that ultimately ended Rewind.

> **NBA 6170 note**: The NBA 6145 report specified ChromaDB as the local vector index. For CatchMeUp (NBA 6170), we replaced ChromaDB with LEANN — LEANN achieves 97% storage reduction via graph-based selective recomputation and has richer pre-built adapters (Apple Mail, WeChat, iMessage, etc.). The local-first architecture argument is preserved and strengthened.

---

## The Workflow

```
DATA SOURCES · passive · always on · zero effort
🗓️ Calendar    📧 Email    📂 Downloads    🎙️ All Time Rec

                        ▼

⚡ TRIGGER  "Catch me up" | New calendar event | Scheduled digest

                        ▼

AGENT PROCESSING · on-demand · only when triggered

1. Collect & Normalize
   Pull data from all four sources for the target time range. Unify into: timestamp + content + source tag.

2. Cross-Reference
   Match audio to calendar events by time. Link emails to courses by topic. Associate files with their context.

3. Summarize & Prioritize
   Per-event summaries. Action items extracted. Deadlines ranked. Low-attention windows flagged.

4. Persist & Index
   Structured data → SQLite. Content chunks → local ChromaDB vector index for semantic retrieval.

                        ▼

Daily Briefing                                   Ask Anything
Highlights · Action items · Deadlines            "What did the professor say about the capstone?"
Things you missed                                — answered with timestamp and source
```

### When Does It Run?

A workflow that never fires is not a workflow. Catch Me Up has three activation modes.

**Calendar-Driven Pre-Brief** — You drag a new event into Apple Calendar — "10am: Meet with Prof. Finger re: capstone." The Agent sees it, searches past transcripts and emails for anything related, and prepares a context brief before the meeting starts. You never had to remember to prepare. This is particularly natural for students: your class schedule is already in your calendar. The calendar becomes the trigger layer.

**On-Demand** — You open Catch Me Up and ask: "What did I miss in the last hour?" or "Summarize today." Only the requested window is processed. No batch jobs. No waiting.

**Scheduled Digest** — Every evening, a summary is generated automatically: today's events, outstanding action items, tomorrow's look-ahead. A personal end-of-day debrief delivered without asking.

**Architecture**: Capture is continuous and cheap (audio is lightweight). Processing is event-driven and on-demand (expensive compute only when needed). This avoids the always-on resource drain that made Rewind's screen capture impractical for many users.

---

## Tools & Stack

### All Time Recorded (Custom macOS App — Built This Semester)

I built All Time Recorded this semester using OpenAI Codex as a personal project to solve my own memory problem. It is a lightweight macOS app designed to be easily integrated into larger workflows:

- Starts recording when the laptop lid opens. Stops when it closes.
- Real-time transcription via OpenAI Whisper, running locally.
- Integrates with Apple Calendar — new events are instantly recognized and tagged.
- Stores timestamped transcripts on-device.

The app was the first piece of the puzzle — built before the Catch Me Up workflow existed. The workflow layer described in this document is what turns that raw capture into structured, actionable intelligence.

Audio-only capture uses a fraction of the resources that Rewind's screen recording required, while capturing the most information-dense signal: human speech.

### Claude API (Anthropic)

The intelligence layer: segmentation, cross-referencing, summarization, and natural-language Q&A. Claude processes the normalized data from all four sources and generates both structured briefings and free-form answers.

### RAG Pipeline (ChromaDB + Embeddings)

> **NBA 6170 update**: replaced with LEANN. See `docs/LEANN_INTEGRATION.md`.

Retrieval-Augmented Generation makes the "ask anything" mode possible. Transcript chunks are embedded and stored in a local ChromaDB instance. Queries retrieve the most relevant context before passing it to the LLM for synthesis. Everything stays on-device.

### Supporting Infrastructure

- **Python** — orchestration connecting all components *(not used in CatchMeUp; Swift subprocess-calls LEANN instead)*
- **SQLite** — structured storage for events, deadlines, action items
- **Apple EventKit** — reading calendar events and detecting triggers
- **IMAP / Mail.app** — pulling email content for cross-referencing

---

## Prompts Used (original NBA 6145 design)

### Prompt 1 — Transcript Segmentation

```
You are analyzing a continuous audio transcript from {start_time}
to {end_time}. It may contain multiple conversations, lectures,
or events.

1. Identify each distinct segment (lecture, meeting, conversation,
background noise).
2. For each: start time, end time, type, topic, participants.
3. Flag windows where speech quality drops or the speaker appears
to lose focus — these are "potential missed content" zones.

Transcript: {transcript}
```

### Prompt 2 — Cross-Reference

```
Given today's data:
CALENDAR: {events} | EMAIL: {emails} | FILES: {files}
| AUDIO: {segments}

1. Match audio segments to calendar events by time overlap.
2. Link emails to events or audio segments by topic.
3. Associate files with the course or meeting they belong to.
4. Flag orphaned items (no matching event).

Output: unified timeline with linked references.
```

### Prompt 3 — Catch Me Up Briefing

```
Generate a "Catch Me Up" briefing from: {unified_timeline}

Sections:
1. TODAY'S HIGHLIGHTS — Top 3-5 events, one sentence each.
2. ACTION ITEMS — From conversations + emails, ranked by urgency,
with source timestamps.
3. THINGS YOU MAY HAVE MISSED — Content from flagged
low-attention windows.
4. LOOKING AHEAD — Tomorrow's events with pre-prepared context.

Tone: concise, scannable. Under 2 minutes to read.
```

> **NBA 6170 evolution**: these prompts are V1 baseline. Phase 2 of `docs/PLAN.md` introduces updated, versioned system prompts in `docs/PROMPT_LIBRARY.md` with explicit injection-defense wrappers and citation requirements. The three original prompts above are kept as source material because they encode the conceptual structure (segmentation → cross-reference → briefing composition) that CatchMeUp's CrossRefEngine + BriefingService still follow.

---

## Workflow in Action

### Screenshot 1 — All Time Recorded: Passive Capture

*(Figure 1: All Time Recorded — main interface (left) and live recording dashboard (right))*

All Time Recorded is a macOS app I built this semester using OpenAI Codex — a personal project to capture open-lid audio with local Whisper transcription. The left panel shows the calendar-integrated daily view; the right shows live recording status — 01:38 recorded, zero gaps, 612 GB free storage. The app auto-resumes after forced sleep, ensuring no content is silently lost. Catch Me Up is the workflow layer built on top of this foundation.

### Figure 2 — Cross-Referencing: How Sources Connect

The diagram below illustrates the core value of the workflow: linking data across sources to produce context that no single source can provide alone.

```
🗓️ Calendar              📧 Email                📂 Downloads              🎙️ Audio (Whisper)
2:00–5:00 PM            Workflow due Mar 11      AI_Strategy_Wk3.pdf      3h lecture transcript
NBA 6145 Lecture        Reading: AI Agents       case_study_zillow.pdf    15min coffee chat
Sage Hall 101           Group mtg Thu 4pm        capstone_rubric.docx     2min hallway Q&A

     ▼                      ▼                         ▼                           ▼
     all sources collected for target time range

⚙ CROSS-REFERENCE ENGINE (Claude API)

Time Matching                              Topic Linking
Audio 2:00–5:00 PM ↔ Calendar "NBA 6145"   Email "Workflow due" ↔ Lecture min 47–52
Audio 5:10–5:25 PM ↔ no event (coffee)     PDF "AI_Strategy" ↔ Calendar "NBA 6145"

     ▼

UNIFIED TIMELINE

2:00–5:00 PM · NBA 6145 Lecture
📎 Audio: 3h transcript (flagged: min 80–100 low attention)
📎 Email: "Workflow assignment due Wed Mar 11 5pm"
📎 Email: "Reading list: AI Agents article"
📎 File: AI_Strategy_Wk3.pdf, capstone_rubric.docx
⚠ Prof. mentioned extra requirement at min 48 — not in syllabus email

5:10–5:25 PM · Coffee Chat (unscheduled)
📎 Audio: 15min transcript — mentioned "Team 10 capstone idea"
📎 Email: "Group mtg Thu 4pm" (related — same team)
💡 Action: share notes with team before Thursday
```

*(Figure 2: Cross-referencing engine linking calendar, email, files, and audio into a unified timeline)*

---

## Conclusion

Professor Finger's framework: *"AI agents aren't magic. They're models + permissions + tools + workflows."*

| Models | Whisper for transcription. Claude for reasoning, cross-referencing, and synthesis. |
|---|---|
| Permissions | User-controlled recording. On-demand processing. Local-only data. No vendor lock-in. |
| Tools | All Time Recorded, EventKit, IMAP, ChromaDB, SQLite. *(Updated for NBA 6170: LEANN replaces ChromaDB.)* |
| Workflow | Passive capture → event-driven trigger → multi-source cross-referencing → prioritized output. |

Rewind proved there is demand for personal memory tools. Its acquisition and shutdown proved that **architecture determines survivability**. Catch Me Up takes the local-first path that Rewind abandoned: audio-focused, on-device, and human-centered.

The hard part — continuous capture and real-time transcription — is already built and running. The workflow layer turns that raw signal into structured, actionable memory on demand. That is the difference between **recording** and **understanding**.

**Built with**: All Time Recorded (macOS), OpenAI Whisper, Claude API (Anthropic), ChromaDB, SQLite, Python. All data processed and stored on-device.

---

## NBA 6170 Evolution Notes

Mapping the NBA 6145 concept to the NBA 6170 execution:

| NBA 6145 concept | NBA 6170 execution |
|---|---|
| "Catch me up" on-demand query | `BriefingService.answerOnDemand` + Agent Chat UI with streaming + citation chips |
| Calendar-driven pre-brief | `MeetingTriggerWatcher` + `GentleRecordingPolicy` + pre-generated briefing cached to disk |
| Scheduled daily digest | `DigestScheduler` firing at 7:13 PM local |
| ChromaDB RAG layer | LEANN (97% storage reduction, already has mail/WeChat indices built) |
| Audio capture (always on) | **Demoted to one of four data sources, opt-in by default** — this is the single biggest pivot |
| Four data sources | Expanded to include WeChat chat history as a 5th source (LEANN adapter already exists) |
| "Catch me up" as the tagline | Replaced by "A trusted system for everything you didn't write down" for NBA 6170's soft problem-solution tone |
| Abstract "hit rate" not specified | Made concrete: **≥85% controlled / ≥70% production Hit Rate** as primary KPI |
| Guardrails not emphasized | Full 4-layer guardrail architecture in `docs/SECURITY_THREATS.md` addressing indirect prompt injection threat |
| Prompts as fixed strings | Versioned `PromptTemplates.swift` with iteration-driven A/B harness |
| Evaluation not specified | Full `EvalService` with golden set + adversarial corpus + stability eval + hallucination checker |

The conceptual spine (cross-source RAG for personal memory) is preserved. The NBA 6170 execution adds everything the rubric demands: measurable KPI, explicit success criteria, guardrails, evaluation, feedback loops, longitudinal monitoring.

## Revision Log

| Date | Change |
|---|---|
| 2026-04-08 | Transcribed from `/Users/yizhi/Documents/25spring/4280/report.pdf`, annotated with NBA 6170 evolution notes |
