# Rubric Alignment Matrix

> Living document. Every PR-sized change that touches a rubric-relevant criterion updates this file.
> Status legend: ⚪ not started · 🟡 in progress · 🟢 done · 🔴 blocked

This table maps every rubric criterion from `docs/CONTEXT.md` §3 and §4 to the specific plan element that earns a Level 5 score, plus the file(s) that hold the evidence. This is the single source of truth for "are we on track for full marks?"

---

## Business Objective (50%)

| Criterion | Plan Element | Evidence File(s) | Status |
|---|---|---|---|
| Clear, specific, measurable, actionable, ethically justified with explicit success criteria | `PLAN.md §1.3` — Hit Rate primary KPI (≥85% controlled / ≥70% production), time-to-hit ≤5s secondary, query frequency leading indicator, ethical framing via local-first | `docs/PLAN.md`, `docs/REPORT_REFERENCE.md` | 🟢 (plan-level) ⚪ (implementation) |

## Deployment & Control (20%)

| Criterion | Plan Element | Evidence File(s) | Status |
|---|---|---|---|
| Confusion matrix framing — hallucinations as FP, refusals as FN | `PLAN.md §9.4` + `EvalService.runFull` reports FP and FN rates as a 2x2 | `Sources/CatchMeUp/Eval/HallucinationChecker.swift` (Phase 3) | ⚪ |
| Business / user metrics (engagement, satisfaction, ROI, retention) | `PLAN.md §1.3` — production hit rate via 👍/👎, query frequency trend; feedback loop in `PLAN.md §9.7` | `Sources/CatchMeUp/Security/AuditLog.swift`, Settings → Eval → Production tab (Phase 3) | ⚪ |
| Threshold adjustments for moderation / safety filters | `PLAN.md §8` — `GuardrailGate` with tunable injection detector sensitivity | `Sources/CatchMeUp/Security/GuardrailGate.swift` (Phase 3) | ⚪ |
| A/B testing with vs without generative support | `PLAN.md §9.7` + `ABTestHarness` | `Sources/CatchMeUp/Eval/ABTestHarness.swift` (Phase 3) | ⚪ |
| Longitudinal monitoring (hallucination rate, bias, satisfaction) | `PLAN.md §9.5` — eval archive with timestamped JSONs | `~/Library/Application Support/CatchMeUp/eval/` + Settings → Eval (Phase 3) | ⚪ |
| Feedback loops → prompt/filter adjustments | `PLAN.md §9.7` — versioned `PromptTemplates` + weekly production hit rate → template promotion | `docs/PROMPT_LIBRARY.md`, `Sources/CatchMeUp/AI/PromptTemplates.swift` (Phase 2) | ⚪ |
| User-controlled data scope | `PLAN.md §8.2` — `ConsentLedger` per-source consent + Settings → Sources | `Sources/CatchMeUp/Security/ConsentLedger.swift` (Phase 2) | ⚪ |
| Audit log of data access | `PLAN.md §8.2` — `AuditLog` append-only JSONL | `Sources/CatchMeUp/Security/AuditLog.swift`, Settings → Audit tab (Phase 3) | ⚪ |

## Stage 1 — Data Preprocessing (~10% of the 30%)

| Criterion | Plan Element | Evidence File(s) | Status |
|---|---|---|---|
| Pre-trained model fit — foundation model rationale | `PLAN.md §2 D3` — Claude Opus 4.6 chosen, rationale documented; `LLMClient` protocol abstracts swappability; README model comparison table (Phase 4) | `docs/PROMPT_LIBRARY.md`, `README.md` (Phase 4) | ⚪ |
| Legal & ethical — licensing, copyright, ethical use of base model + adaptation data | `PLAN.md §1.3` ethical framing + `docs/SECURITY_THREATS.md` licensing section | `docs/SECURITY_THREATS.md`, `docs/CONTEXT.md §8` | 🟡 |
| Confidentiality & compliance — guardrails for sensitive data leakage | `PLAN.md §8` four-stage defense + `SensitiveDataSanitizer` for credential patterns in output | `docs/SECURITY_THREATS.md`, `Sources/CatchMeUp/Security/*.swift` (Phase 3) | 🟡 |
| Data gaps — representative eval sets | `PLAN.md §9.1` — 30-query golden set with 5 categories (factual, cross-source, temporal, negative, pre-meeting) | `docs/eval/golden_set.json` (Phase 3) | ⚪ |
| Outliers / adversarial eval prompts | `PLAN.md §9.2` — 6-prompt `AdversarialPromptCorpus` | `docs/eval/adversarial_corpus.json` (Phase 3) | ⚪ |
| Normalization — standardized prompts | `PLAN.md §2 D6` — versioned `PromptTemplates` as `static let` constants | `docs/PROMPT_LIBRARY.md`, `Sources/CatchMeUp/AI/PromptTemplates.swift` (Phase 2) | ⚪ |
| Feature engineering = RAG + prompt tuning | `PLAN.md §2 D2` — `CrossRefEngine` cross-source fusion; explicit RAG-vs-LoRA rationale | `Sources/CatchMeUp/RAG/CrossRefEngine.swift` (Phase 2), `docs/PROMPT_LIBRARY.md` | ⚪ |
| Relevant / representative data | `PLAN.md §9.1` — golden set drawn from user's actual 30-day corpus | `docs/eval/golden_set.json` (Phase 3) | ⚪ |
| Class distribution — diverse prompt categories | `PLAN.md §9.1` — 5 categories × 6 queries each | `docs/eval/golden_set.json` (Phase 3) | ⚪ |
| Multicollinearity — prompt sensitivity monitoring | `PLAN.md §9.3` — stability eval, 5 phrasings, Jaccard + BLEU, threshold ≥0.75 | `Sources/CatchMeUp/Eval/StabilityEval.swift` (Phase 3) | ⚪ |

## Stage 2 — Model Development (~10% of the 30%)

| Criterion | Plan Element | Evidence File(s) | Status |
|---|---|---|---|
| Model selection rationale — compare GPT / Claude / Gemini / Llama | `PLAN.md §2 D3` + README comparison table (Phase 4) | `README.md` (Phase 4), `docs/PROMPT_LIBRARY.md` | ⚪ |
| Adaptation — LoRA / RAG / prompt tuning justified | `PLAN.md §2 D2` + explicit RAG-vs-LoRA rationale paragraph | `docs/PROMPT_LIBRARY.md` RAG section | ⚪ |
| Workflows & guardrails — chaining, safety filters, policy enforcement | `PLAN.md §8` four-stage defense architecture | `docs/SECURITY_THREATS.md`, `Sources/CatchMeUp/Security/*.swift` (Phase 3) | ⚪ |
| Iterative orchestration | `PLAN.md §9.7` — versioned templates + `ABTestHarness` | `docs/PROMPT_LIBRARY.md`, `Sources/CatchMeUp/Eval/ABTestHarness.swift` (Phase 3) | ⚪ |

## Stage 3 — Model Quality (~10% of the 30%)

| Criterion | Plan Element | Evidence File(s) | Status |
|---|---|---|---|
| Consistency across runs | `PLAN.md §9.3` — stability eval with 5 phrasings | `Sources/CatchMeUp/Eval/StabilityEval.swift` (Phase 3) | ⚪ |
| Output alignment — factual correctness, safe tone, domain context | `GuardrailGate.validateOutput` + system prompt explicit instruction | `Sources/CatchMeUp/Security/GuardrailGate.swift`, `Sources/CatchMeUp/AI/PromptTemplates.swift` (Phase 2–3) | ⚪ |
| Interpretability — citations in RAG, rationales, transparent system prompts | `PLAN.md §5.2` — citation chips on every answer; shipped prompts as readable constants | `Sources/CatchMeUp/UI/Briefing/CitationChip.swift` (Phase 2), `docs/PROMPT_LIBRARY.md` | ⚪ |
| Instruction following validation | Golden set category checks | `docs/eval/golden_set.json` (Phase 3) | ⚪ |
| Factuality & hallucination detection | `PLAN.md §9.4` — `HallucinationChecker` with 7-gram support test + citation existence check + production 👍/👎 | `Sources/CatchMeUp/Eval/HallucinationChecker.swift` (Phase 3) | ⚪ |
| Robustness across inputs | `PLAN.md §9.2` — `AdversarialPromptCorpus` + §8 guardrail layers | `docs/eval/adversarial_corpus.json` (Phase 3) | ⚪ |
| Human evaluation | Inline 👍/👎/wrong-source feedback on every answer; weekly production hit rate trend | `Sources/CatchMeUp/UI/Briefing/AgentMessageBubble.swift` (Phase 2) | ⚪ |

---

## Status Roll-Up

- **Plan-level** (spec'd in `docs/PLAN.md`): 🟢 all criteria addressed
- **Documentation-level** (this file + sibling `docs/*.md`): 🟡 Phase 0 in progress
- **Code-level**: ⚪ Phases 1–4 not started yet

## Next Review

This file is re-verified at the end of each phase's acceptance script (see `docs/PLAN.md` §15). If any criterion slips from 🟢 back to 🟡, flag it in the changelog.

## Revision Log

| Date | Change |
|---|---|
| 2026-04-08 | Initial matrix created during Phase 0 |
