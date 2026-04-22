# DESIGN HLD — WIP Notes

Parked planning for the v0.1 high-level design document. Not the HLD itself — the agreed-upon outline, section contents, and open decisions to resume from.

---

## Scope split: HLD vs. DLD

Two documents instead of one monolithic DESIGN.md.

| Doc | Purpose | Length target | Audience |
|---|---|---|---|
| HLD (this plan) | Architectural decisions, subsystem contracts, reasoning | ~400–580 lines / 9–13 pages | Reviewer — "understand without implementing" |
| DLD (later) | DDL, LLM prompts, pseudocode, exact thresholds | ~500–900 lines (no page ceiling) | Implementer — reference material |

HLD is purely technical — no metadata, no audience statement, no scope preamble. The file's existence alongside PROPOSAL.md and PLAN.md implies its scope; no need to restate.

## HLD structure (four sections)

```
1. System overview
2. Solution
3. Architecture
   3.1 Components / subsystems
```

HLD stops after §3.1. Anything beyond (config tables, invariants list, alternatives archive, DDL, prompts, SQL) either moves to DLD or doesn't exist.

### §1 System overview

- One architecture diagram — component boxes with labeled boundary arrows
- One-paragraph description per component: Typhoon runtime, TursoDB, dream LLM, online LLM, Telegram bot, external forge, filesystem, operator
- Ownership map table — which component owns what

Target: 80–120 lines / 2–3 pages.

### §2 Solution

The technical answer to how the parts solve the problem.

- **Core loop** — collect → reason → forge → ratify, as a pipeline with data crossing each arrow
- **Division of responsibility** — Typhoon writes requests + catalogs deliveries; forge writes code + attests correctness; operator ratifies
- **State machine overview** — proposal, CLI, soul lifecycles as diagrams with allowed transitions
- **Key mechanisms** (architectural rules, not implementation):
  - Tier claim honesty → sandbox runtime check
  - Cross-machine portability → hardcoded-path lint
  - Rejection drift → 3-strike rule
  - Concurrency → single-writer task + file lock
  - Atomicity → `BEGIN IMMEDIATE … COMMIT`
  - Retrieval bounded → Top-K + similarity + token budget

Target: 120–180 lines / 3–4 pages.

### §3 Architecture

Structural breakdown into subsystems.

#### §3.1 Components / subsystems (7)

Each carries: purpose (1 sentence) · inputs/outputs · key rules · dependencies.

1. **Storage** — TursoDB schema at conceptual level (tables + relationships + invariants, no DDL)
2. **Signal capture** — what a signal is, session definition, success-tagging rule
3. **Dream cycle** — three phases with input/output contracts; no prompts
4. **Forge handoff** — request format contract, submit protocol, platform-contract checks
5. **CLI lifecycle** — installation, replacement, rollback, deprecation rules
6. **Online channels** — REPL and Telegram as adapters with shared session-mapping contract
7. **Observability** — what keepers report, not how

Seven chosen over five because it aligns with PLAN.md §2 work-breakdown grouping.

Target: 200–280 lines / 4–6 pages.

## Deliberately excluded from HLD

- Metadata (title / status / author) — file's git history covers this
- Scope / audience preamble — redundant given PROPOSAL + PLAN already exist
- Configuration key list — DLD reference
- Full invariants list — folded into §2 mechanisms and §3 subsystem rules
- Alternatives archive — already in PROPOSAL §6 and conversation threads; no duplication
- DDL, LLM prompts, scoring formulas, sandbox invocation, test-case list — all DLD

## Decisions needed before drafting HLD

These appear as facts in HLD, so they must be settled before writing:

1. **Session definition** — Telegram thread + per-REPL-invocation, or different rule?
2. **Signal capture mechanism** — shell wrapper or agent-library instrumentation?
3. **Dream-LLM choice** — Haiku 4.5 / MiniMax M2.7 / GLM something / other?
4. **Online-LLM choice** — Claude Sonnet 4.6 / GPT-5 / GLM 5.1 / other?

"TBD" in HLD is a smell. Pick best-current-knowledge values; DLD refines.

## Decisions deferred to DLD

From PLAN §8 — each has a "make it work" default; DLD picks the real answer:

1. Sandbox mechanism specifics (bwrap config, seccomp filters, resource limits)
2. Sandbox interaction with AppArmor/SELinux (require disabled, ship profiles, or document)
3. Telegram execution permissions (v0.1 default: forged CLI runs same privileges as REPL)
4. Success-tagging edge cases (what counts as "correction"?)
5. Retrieval budget knobs (exact top_k, similarity threshold, per-turn token budget)
6. Replacement similarity thresholds
7. Initial threshold values (`dream.min_frequency`, `dream.min_score`) — placeholders, tune in first two weeks

## Review feedback already applied to PROPOSAL / PLAN

During planning, Gemini's review surfaced three items that landed in PLAN.md:

- **TC-M3-05** — token budget test (not just Top-K count)
- **R8** — success-tagging false-positive risk (abandoned tasks)
- **§8 items 6 + 7** — sandbox/AppArmor interaction, Telegram execution permissions

Proposal's correctness-framing was corrected: Typhoon does not verify correctness; forge attests, operator ratifies. Replay-test-as-gate concept removed. Tier check reframed as platform-contract honesty, not correctness.

## Next action

Resolve the four tier-1 decisions, then draft `DESIGN.md` (HLD) against the structure above.

DLD drafting comes after HLD is reviewed and stable.
