# CatchMeUp — Course Context

> This file is the authoritative snapshot of the academic context the project is graded against.
> If course materials change, update this file within 24 hours and reference the source.

---

## 1. Course

**Course code**: NBA 6170 — AI Solutions
**Institution**: Cornell (MBA program, weekend format)
**Instructor**: Lutz Finger ([lutzfinger.com](https://www.lutzfinger.com) / Cornell faculty / ex-LinkedIn, Snapchat, Google)
**Delivery format**: weekend intensives with recap → topic → hands-on pattern. Weekend 2 (where this project is graded) covers:
1. PM Launch Checklist
2. Logistic Regression
3. **Agentic Workflows** ← directly relevant
4. **RAG & State & Data Assets** ← directly relevant
5. Neural Networks
6. Generative AI
7. Data (acquisition, quality, legal/ethical)

CatchMeUp sits at the intersection of the Agentic Workflows and RAG topics. Every design decision should reinforce that framing.

## 2. Grading Model

The project is graded on a **published rubric** (see §3 below) *and* **peer-voted on a pitch demonstration** by MBA classmates with real industry experience. This is important: the competition is not naive, the audience has already shipped products, and a gimmicky or shallow demo will be identified within 30 seconds.

**Rubric weighting** (from `AI_Model_Rubric.docx`):

| Area | Weight |
|---|---|
| Business Objective | **50%** |
| Deployment & Control | **20%** |
| Data Preprocessing, Model Development, and Model Quality (split equally) | **30%** |

Any decision in this project that does not defensibly earn a specific rubric criterion is out of scope. See `docs/RUBRIC_ALIGNMENT.md` for the line-by-line mapping.

## 3. Rubric — Full Transcription

### 3.1 Business Objective (50%)

| Score | Criterion |
|---|---|
| 1 | No clear objective stated. |
| 2 | Objective is vague or unrealistic. |
| 3 | Objective stated, somewhat measurable, but limited clarity. |
| 4 | Clear and measurable objective, feasible and actionable. |
| **5** | **Fully clear, specific, measurable, actionable, ethically justified, with explicit success criteria.** |

CatchMeUp's target: 5/5 via the Hit Rate KPI. See `docs/PLAN.md` §1.3.

### 3.2 Stage 1 — Data Preprocessing and Preparation (portion of the 30%)

Each criterion scored 1–5. 5 requires the stated bar below.

| Criterion | Level 5 (genAI) |
|---|---|
| Legal & Ethical Concerns | Statement addressing licensing, provenance of fine-tuning data, and ethical appropriateness. |
| Confidentiality & Compliance | Guardrails and policies described to prevent leakage of sensitive data. |

### 3.3 Stage 2 — Model Development (portion of the 30%)

| Criterion | Level 5 (genAI) |
|---|---|
| Model Selection | Explicit rationale for choosing a foundation model, with trade-offs. |
| Adaptation / Fine-Tuning | Clear adaptation (LoRA, RAG, prompt tuning) justified. |

### 3.4 Stage 3 — Model Quality (portion of the 30%)

| Criterion | Level 5 (genAI) |
|---|---|
| Residual and Error Analysis | Outputs tested across multiple runs and varied prompts. |
| Factuality and Hallucination Detection | Clear method for hallucination detection (fact-checking, reference grounding). |

### 3.5 Stage 4 — Deployment & Control (20%)

| Criterion | Level 5 (genAI) |
|---|---|
| Confusion Matrix / Error Categories | Hallucinations (FP) vs. refusals (FN) explained in context. |
| Business and User Metrics | Engagement, satisfaction, ROI, retention explicitly linked. |

## 4. Extended genAI Checklist

From `Course - Checklist for AI Models.docx` (the full genAI manual). These are the criteria Lutz actually uses when grading generative AI projects. Every one is defensible in the plan; mapping in `docs/RUBRIC_ALIGNMENT.md`.

### 4.1 Stage 1 (Data)

- **Pre-Trained Model Fit**: Confirm foundation model fits use case. Assess risks with closed-source models (opaque training data, hidden biases, licensing limits).
- **Legal & Ethical Concerns**: Check compliance of BOTH the base model AND adaptation data with licensing, copyright, ethical use.
- **Confidentiality & Compliance**: Verify prompts and outputs don't leak sensitive data; apply guardrails and access controls.
- **Data Gaps**: Address coverage gaps in evaluation prompts or domain examples by curating representative sets.
- **Outliers / Anomalies**: Include adversarial or edge-case prompts in evaluation sets.
- **Normalization / Standardization**: Standardize prompts (clear, consistent, reproducible).
- **Data Types and Encoding**: Ensure prompt formats (JSON, markdown, NL) and outputs align with downstream requirements.
- **Feature Engineering / Domain Adaptation**: Adapt models with **LoRA, prompt tuning, or RAG** for domain-specific use.
- **Relevant and Representative Data**: Build evaluation sets that reflect real-world usage scenarios.
- **Class Distribution / Balance**: Ensure evaluation prompts cover diverse categories, demographics, and edge cases.
- **Multicollinearity / Dependence**: Monitor prompt sensitivity where small changes produce unstable outputs.

### 4.2 Stage 2 (Model Development)

- **Linearity Assumption**: N/A for genAI; validate logical consistency of prompt-task pairs instead.
- **Data Split / Size**: Replace random splits with curated evaluation datasets — golden sets, adversarial prompts, synthetic or benchmark corpora.
- **Model Selection**: Compare foundation models (GPT, Claude, Gemini, Llama) by accuracy, reliability, licensing, cost-performance.
- **Adaptation and Fine-Tuning**: Apply LoRA, adapters, prompt tuning, or RAG; fine-tune with domain-specific data if needed.
- **Workflows and Guardrails**: Build workflows around the base model — chaining, safety filters, policy enforcement, compliance checks.
- **Evaluation Data**: Use curated prompt sets, golden annotations, and adversarial stress tests.
- **Iterative Orchestration**: Iterate across model choice, fine-tuning, retrieval, guardrails, and monitoring.

### 4.3 Stage 3 (Model Quality)

- **Residual / Error Analysis**: Consistency checks across multiple runs; stability across prompt variations.
- **Appropriate Scale and Range**: Standardize prompts and tasks to make evaluations comparable.
- **Coefficients / Feature Importance**: Check outputs for alignment with factual correctness, safe tone, and domain context.
- **Interpretability**: Provide grounding (citations in RAG), rationales, or transparent system prompts.
- **Instruction Following**: Validate compliance with user intent.
- **Factuality and Hallucination Detection**: Cross-check outputs against ground truth; track hallucination rates.
- **Robustness Across Inputs**: Stress test with diverse, adversarial, or edge-case prompts.
- **Human Evaluation**: Human ratings for fluency, coherence, creativity, relevance; pairwise preference tests.

### 4.4 Stage 4 (Deployment & Control)

- **Confusion Matrix (Deployment Lens)**: Treat hallucinations as FP, refusals as FN; balance between missed utility and safety.
- **Accuracy, Precision, Recall, F1**: Define equivalents (factual accuracy, safe vs. unsafe outputs, coverage of user needs).
- **Threshold Adjustments**: Adjust moderation strictness, safety filters, or confidence thresholds.
- **Business and User Metrics**: Monitor user satisfaction, engagement, conversions/ROI, retention, and trust.
- **A/B Testing**: Compare experience and outcomes with vs. without generative support.
- **Longitudinal Monitoring**: Track hallucination rates, bias, safety compliance, and user satisfaction over time.
- **Feedback Loops**: Integrate user feedback, ratings, and corrections to adjust prompts, fine-tuning, or filters.

## 5. Lutz Finger's Framework

Published by the professor as a cross-cutting lens for evaluating any AI product decision:

**Feasible / Actionable / Feedback / Ethical**

Every design decision in this project must be explicable under all four. The plan applies the framework explicitly in `docs/PLAN.md` §1.3.

## 6. Prior Homework Reference (what Lutz values visually)

A prior homework in the Lutz Finger track (NBA6870 HW1: "Workflow for Meeting Booking AI Agent" by Aditya Mahesh Chandak) was graded on the *quality of the workflow diagram itself* — boxes, branches, conditions, tool calls, error paths, all rendered explicitly. The instructor values **sophisticated, readable, decision-rich workflow visualizations** as evidence of thinking through an agent end-to-end.

**Implication for CatchMeUp**: Phase 4's pitch deck must include at least one large, detailed agentic workflow diagram showing how CrossRefEngine fans out, how GuardrailGate intercepts, how BriefingService composes the final answer, how the feedback loop closes. This is not decoration — it is graded content.

## 7. Peer-Grading Context

Classmates are MBA students with real industry experience. This changes several things:

1. **Shallow features get called out fast.** "It's a chatbot" won't pass. The audience has built chatbots.
2. **Business model matters, even though we're not raising money.** A pitch without a clear "who pays, why, how much" will feel incomplete. The ethical framing (local-first, not data-harvesting) is part of the business model story.
3. **Demo reliability matters more than breadth.** Three scenes that work flawlessly beat seven scenes where one fails on stage. See `docs/PLAN.md` §10 for the five committed demo scenes.
4. **Differentiation against real competitors is expected.** The plan cites Rewind/Limitless, Notion AI, Granola, Otter, Read.ai, Fireflies, Mem, Reflect. Every competitor is named and the wedge against them is explicit.

## 8. Key Reference Reading

- **AI Agents Under Threat: A Survey of Key Security Challenges and Future Pathways** (Deng et al., Swinburne + Tianjin + Ant Group, arXiv:2406.02630, June 2024). The 4-gap threat model (unpredictable inputs / internal execution complexity / environment variability / untrusted external entities) is the backbone of `docs/SECURITY_THREATS.md`. Gap 1 and Gap 4 are most relevant to CatchMeUp.
- **LEANN: A Low-Storage Vector Index** (Wang et al., Berkeley Sky Computing Lab, arXiv:2506.08276, 2025). The paper behind LEANN's 97% storage reduction. Cited in the pitch for the local-first + low-footprint story.
- **NBA 6145 "Catch Me Up" report** (the user's own 10-page report for a different course — NBA 6145). Full text in `docs/REPORT_REFERENCE.md`. This is the source material for the pitch script.
- **The Lutz Finger course materials** at `/Users/yizhi/Downloads/` (PDFs and .docx files for NBA 6170 Weekend 2). Transcribed portions are in §3 and §4 above; the originals are not tracked in this repo to keep the repo lean.

## 9. What's NOT in scope for grading

Things that matter for the project but are not directly rewarded by the rubric (don't over-invest):

- Visual polish beyond what sells the demo on camera (the UI is already good enough)
- Cross-platform support (macOS only is fine)
- Account system, billing, multi-user support
- Mobile app
- Shareable briefings

These are documented in `docs/PLAN.md` §11 Phase 5 as "post-pitch runway" items.

## 10. Revision Log

| Date | Change | Source |
|---|---|---|
| 2026-04-08 | Initial version created during Phase 0 planning | — |
