# Typhoon PLAN — v0.1

This document is the v0.1 build plan. It defines what is in scope, the work breakdown, the sequence, the runtime cost envelope, the test cases that decide when v0.1 is done, and the risks with their keepers.

It defers schema definitions, SQL DDL, module layout, and scoring weights to `DESIGN.md`.

---

## 1. Scope

### 1.1 In scope (v0.1)

- Typhoon Rust runtime — single binary
- TursoDB (operator-provided account) as the sole state store
- Schema migrations + seed, both run at `typhoon init --url $URL --token $TOK`
- Config CRUD with type validation, read-only `typhoon sql`
- Use-plane CLI subcommands (`typhoon signal record`, `typhoon memory query`) — agent-invoked one-shots that invoke Core directly through normal CLI dispatch; the same path covers development shakedown via shell scripts
- Signal capture: tool calls, corrections, outcomes, session boundaries, success tagging
- Dream cycle (light / REM / deep / prune) — organizes signals and writes **proposal briefs**, not requirements and not code; coordinated through a `dream_runs` lease row with heartbeat, cooperative cancel, bounded runtime, status query, and ETA
- Memory extraction (mem0-style) inside the dream cycle; bounded retrieval (Top-K + similarity)
- Operator hand-off: `typhoon tool propose submit <id> --requirements <file> --tool-doc <tool.md> --source <file> [--tests <file>]`
- Hardcoded-path lint (cross-platform, regex)
- Atomic approve / install / rollback via `.history/`
- CLI lifecycle management (list, show, disable, enable, rollback, delete, purge, promote, check-deps)
- Replacement flow with diff + atomic swap
- 3-strike rejection tracking for both patterns and replacements
- Persona proposals for persona-attribute changes (always require approval)
- Cron scheduler (`typhoon cron`) with `--catchup`
- Queued channel path (`typhoon gateway`) with Telegram adapter — primary user interface in v0.1; one daemon hosts an edge loop and a queue-consuming worker loop, while durable Turso-backed inbox/outbox rows decouple external channel I/O from Typhoon Way's agent loop
- Observability keepers: `typhoon health`, `typhoon dream stats`, per-CLI health metrics

### 1.2 Out of scope (v0.1)

- Automated forge invocation (operator forges manually, out-of-band, with their own tooling)
- Automated forge backends / integrations (manual operator choice of Codex, Claude Code CLI, Cursor, or similar remains in scope)
- Auto-install for pure-tier CLIs (every CLI needs operator approval in v0.1)
- Multi-runtime sync (one Typhoon runtime instance owns one TursoDB database; TursoDB may still be used from other machines for operator/forge workflows)
- `wasm32-wasip2` target + wasmtime host
- Binary-pinned artifact distribution
- Browser / Cloudflare Workers targets (permanently rejected — §6 of PROPOSAL.md)

---

## 2. Work Breakdown Structure

**Effort unit: Agentic Unit (AU).** One AU = one focused agentic coding session — frame the task, agent implements, operator reviews, commit. Sizes:

- **S** = 1 AU
- **M** = 2–3 AU
- **L** = 4–6 AU
- **XL** = 7+ AU → split before starting

### 2.1 Work items

| ID | Item | Inputs | Outputs | Size |
|---|---|---|---|---|
| W1 | Cargo crate, clap skeleton, logging, error types | — | `typhoon --help` runs | S |
| W2 | TursoDB client, migrations, seed (needs URL + token at init) | W1 | `typhoon init` creates schema + seed rows | M |
| W3 | `config get / set / list`, type validation (`string/int/float/bool/cron`) | W2 | Config CRUD with CHECK enforcement | S |
| W4 | `typhoon sql` — SELECT-only guard | W2 | SELECT works; writes rejected | S |
| W5 | Use-plane CLI subcommands (`typhoon signal record`, `typhoon memory query`) wired into Core, recorder path, session model, tool-call signal capture | W2 | Hand-run shell script routes through runtime/recorder and produces `dream_signals` rows | M |
| W6 | Success tagging (exit 0 + no next-turn correction) | W5 | Signals carry `success` flag correctly | S |
| W7 | Stale-signal prune (7d); dream `dream_runs` lease (acquire / heartbeat / stale-takeover); cooperative cancel handlers per phase; max-runtime enforcement; `typhoon dream status` (with EWMA-or-static ETA) and `typhoon dream cancel [--wait]` | W5 | Re-running dream is safe (lease takeover); admin can query phase / ETA and request graceful shutdown; old signals cleaned | M |
| W8 | Dream LLM client (cheap batch model), `dream_runs` logging | W5 | Dream can make LLM calls; runs logged | M |
| W9 | Memory extraction (mem0-style) inside dream | W8 | `memories` table populated from signals | M |
| W10 | Bounded retrieval (Top-K + similarity + scope) | W9 | `typhoon memory query` next-session shows relevant memories within budget | M |
| W11 | REM phase — cluster successful chains, detect repeats, collision check | W8, W6 | Clusters emerge from seeded signals | M |
| W12 | DEEP phase — organize clustered signals into proposal briefs (problem / repeated workflow / likely interface sketch / rough acceptance hints / rough tier / evidence / ROI) | W11 | `awaiting_forge` proposal brief row appears | L |
| W13 | Persona proposal flow | W8 | Persona-attribute changes routed through approval queue | S |
| W14 | `typhoon tool propose submit <id> --requirements <file> --tool-doc <tool.md> --source <file> [--tests <file>]` | W12 | Operator can hand hardened requirement + LLM-facing tool descriptor + source back | M |
| W15 | Hardcoded-path lint | W14 | Obvious absolute paths rejected | S |
| W16 | Atomic approve (binary + registry + reviewed `tool.md` + seed memory in one tx) | W14, W15 | Approve is all-or-nothing | M |
| W17 | CLI lifecycle commands — list, show, diff, history, disable, enable, rollback, delete, purge, promote, check-deps | W16 | Full management surface | M |
| W18 | Replacement flow + `.history/` archival + atomic swap | W16 | Replacement approval swaps cleanly | M |
| W19 | 3-strike rejection tracking (patterns + replacements) | W12, W18 | Dream stops re-proposing rejected patterns | S |
| W20 | Cron scheduler (`typhoon cron`) + `--catchup` | W12 | Nightly dream fires; catchup handles >25h gap | S |
| W21 | Telegram channel (`typhoon gateway`) | W10, W6 | Real user interaction flows Telegram → gateway edge loop → channel inbox → gateway worker loop → core → channel outbox → Telegram, and lands in signals | L |
| W22 | Keepers — `typhoon health`, `typhoon dream stats`, CLI health metrics in `typhoon tool show` | W20 | Observability wired | M |
| W23 | Test harness for all TC-* cases — runnable from one command | W17, W21 | `make test` runs the whole suite | M |

### 2.2 Critical path

`W1 → W2 → W5 → W6 → W8 → W11 → W12 → W14 → W16 → W21`

Side branches (W3, W4, W7, W9, W10, W13, W15, W17, W18, W19, W20, W22, W23) attach to the spine as inputs are satisfied. None of them are on the critical path.

---

## 3. Timeline & Milestones

**Sequence only.** Calendar dates depend on operator availability and agent throughput; the sequence does not. Each milestone groups the work items that must complete before its test cases can run.

- **M1 — Foundation**: W1, W2, W3, W4
- **M2 — Signal substrate**: W5, W6, W7
- **M3 — Dream has a brain**: W8, W9, W10
- **M4 — Proposal briefs emerge**: W11, W12, W13
- **M5 — First CLI lives**: W14, W15, W16, W17, W18, W19
- **M6 — Autonomous cadence**: W20
- **M7 — Telegram + observability + acceptance**: W21, W22, W23

Each milestone is demoable — a concrete thing you can run from the command line and show. If a milestone isn't demoable, it's not a milestone.

---

## 4. Cost / Efficiency

Runtime costs (post-ship), not build costs. Build cost is operator time measured in AU (§2).

### 4.1 LLM budget

| Lane | Model class | Work | Expected cost (single-user) |
|---|---|---|---|
| Dream (batch, overnight) | Cheap batch (e.g. Haiku 4.5, MiniMax M2.7) | 1 run/night × memory extraction + clustering + proposal-brief drafting | **$3–7 / month** |
| Online (Telegram + external-agent) | Frontier (Claude Sonnet 4.6, GPT-5, GLM 5.1) | Pay-per-turn on Telegram path; external-agent path uses the agent's own LLM bill | **$10–40 / month (Telegram path only)** |

**Alert threshold**: if monthly LLM spend exceeds $75 in a single-user workload, investigate. Likely causes: dream retries on LLM errors, runaway memory retrieval injection, online-LLM tool-call loops.

### 4.2 Infrastructure

- TursoDB: free tier sufficient for single-user (well under limits)
- Host: $5–10 VPS, any Linux. Needs static outbound IP or long-poll Telegram (no inbound required)
- Storage: DB < 100 MB for ≥ 12 months of single-user signals; `.history/` grows with forged CLIs, bounded by cleanup policy

### 4.3 Operator time

**Forge burden is the bottleneck.** Expected v0.1 rhythm:

- Dream produces ~2–5 proposal briefs per week (tunable via `dream.min_frequency` and `dream.min_score`)
- Each forge session: ~20–40 min with a chosen coding agent (read brief, harden requirement, iterate on source, run forge's own tests, submit)
- **Total operator forge time: ~1–3 hours/week**

If this exceeds 5 hours/week sustained, v0.2 forge automation moves up in priority.

### 4.4 Storage

- `~/.typhoon/bin/` — few KB per CLI; 100 CLIs ≈ 10 MB
- `~/.typhoon/bin/.history/` — retains superseded versions; prune policy deferred to post-v0.1

---

## 5. Quality — Test Cases

v0.1 is done **when all TC-* below pass on a clean install**. There is no subjective gate; tests decide.

Each test case is a command (or short script) with an observable pass criterion. All test cases are part of W23's suite and re-runnable.

### 5.1 M1 — Foundation

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M1-01 | `typhoon init --url $URL --token $TOK` on fresh DB | Exit 0; `config` table has seed rows including `agent.name` |
| TC-M1-02 | Second `typhoon init …` on same DB | Exit 0; `schema_migrations` row count unchanged |
| TC-M1-03 | `typhoon init` with invalid token | Exit ≠ 0; stderr contains auth error |
| TC-M1-04 | `typhoon config set dream.min_score notanumber` | Exit ≠ 0; error references type `float` |
| TC-M1-05 | `typhoon config set dream.min_score 1.5` | Exit ≠ 0; clamped/rejected (range 0.0..=1.0) |
| TC-M1-06 | `typhoon sql "SELECT * FROM config"` | Exit 0; rows printed |
| TC-M1-07 | `typhoon sql "INSERT INTO config VALUES (…)"` | Exit ≠ 0; error "SELECT only" |
| TC-M1-08 | `typhoon sql "DROP TABLE config"` | Exit ≠ 0 |

### 5.2 M2 — Signal substrate

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M2-01 | Shell script invokes `typhoon signal record` once with a synthetic tool call | `dream_signals` has ≥ 1 row with correct `session_id`, `source='tool_call'`, non-empty snippet |
| TC-M2-02 | Tool call exits 0, next user turn is non-correction | Resulting signal chain tagged `success=1` |
| TC-M2-03 | Tool call exits 0, next user turn is "no, do X instead" | Signal chain tagged `success=0` |
| TC-M2-04 | Two shell scripts each invoke `typhoon signal record` with distinct session IDs | Signals from each carry distinct `session_id` |
| TC-M2-05 | Seed a signal dated 8 days ago, run dream | Signal deleted from `dream_signals` |

### 5.3 M3 — Dream has a brain

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M3-01 | Seed 3 signal chains mentioning "deploy to preview"; run `typhoon dream` | `memories` table has ≥ 1 row referencing that concept |
| TC-M3-02 | Subsequent `typhoon memory query "how do I deploy?"` | Returned context includes that memory |
| TC-M3-03 | Seed unrelated memories; query unrelated topic | Retrieved memory count ≤ `retrieval.top_k` (no overflow) |
| TC-M3-04 | Query with similarity below threshold | No memories retrieved |
| TC-M3-05 | Seed 100 memories; issue a vague query that matches many | Total tokens of retrieved memories ≤ `retrieval.max_tokens`; Top-K not exceeded regardless of match count |

### 5.4 M4 — Proposal briefs emerge

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M4-01 | Seed 5 identical successful signal chains matching pattern P; run dream | `cli_proposals` has 1 row with `status='awaiting_forge'`, `frequency=5`, non-empty problem description, repeated workflow summary, likely interface sketch, rough acceptance hints, rough tier claim, evidence, ROI score |
| TC-M4-02 | Seed 5 chains with `success=0` | No CLI proposal created |
| TC-M4-03 | Seed 4 successful chains (below `min_frequency=5`) | No CLI proposal created |
| TC-M4-04 | Pre-install CLI `foo`; seed signals overlapping `foo`'s origin | Proposal carries `replaces='foo'` |
| TC-M4-05 | Seed persona-attribute pattern signals (user repeatedly edits a persona's `heuristics`) | `persona_proposals` row appears |
| TC-M4-06 | Run `typhoon dream` concurrently from two shells | Second invocation exits ≠ 0 with lock error; first completes cleanly |

### 5.5 M5 — First CLI lives

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M5-01 | `typhoon tool propose submit <id> --requirements req.md --tool-doc tool.md --source cli.sh --tests test.sh` | Proposal stores hardened requirement + `tool.md` + source + tests and flips `awaiting_forge → awaiting_user` |
| TC-M5-02 | Submit source without `--requirements` or `--tool-doc` | Exit ≠ 0; proposal remains `awaiting_forge` |
| TC-M5-03 | Submit source containing `/home/yanggf/project` | Exit ≠ 0; lint rejects hardcoded path |
| TC-M5-04 | `typhoon tool propose approve <id>` on clean proposal | Binary in `~/.typhoon/bin/<name>`; `tool.md` in registry/artifact metadata; `cli_artifacts` row; seed memory written — all in one transaction |
| TC-M5-05 | Approve where binary write fails (inject fault) | No partial state: no registry row, no memory, no binary |
| TC-M5-06 | `typhoon tool disable foo` | Binary removed from PATH; registry row retained with `status='disabled'` |
| TC-M5-07 | `typhoon tool rollback foo` after replacement | Previous version restored from `.history/`; current version archived |
| TC-M5-08 | Approve replacement proposal | Old binary → `.history/<name>.<ts>`; new binary active; registry lineage updated; all atomic |
| TC-M5-09 | Reject same pattern 3 times | Fourth dream run produces no proposal for that pattern |
| TC-M5-10 | `typhoon tool promote /usr/local/bin/myscript --tool-doc tool.md` | Registry row created with `approved_by='user'`, reviewed `tool.md`, no origin proposal |
| TC-M5-11 | `typhoon tool check-deps` with a CLI needing missing `jq` | Warns; install path would block if attempted |

### 5.6 M6 — Autonomous cadence

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M6-01 | `typhoon cron` started; clock advances past `dream.cron` | `dream_runs` has new row within 60s of trigger |
| TC-M6-02 | Kill cron, wait >25h, start with `typhoon dream --catchup` | Dream fires once immediately |
| TC-M6-03 | Kill `typhoon cron` mid-dream | `dream_runs.ended_at IS NULL` cleanly; next start recovers without duplication |

### 5.7 M7 — Telegram + observability

| ID | What runs | Pass criterion |
|---|---|---|
| TC-M7-01 | `typhoon gateway` with valid bot token | Connects; bot is reachable in Telegram; inbound Telegram update creates a `channel_inbox` row |
| TC-M7-02 | `typhoon gateway` running, send message to bot | Gateway worker loop claims inbox row; signal appears in `dream_signals` with Telegram-sourced `session_id`; reply lands in `channel_outbox` |
| TC-M7-03 | Send message from a peer with no verified binding | Gateway worker loop marks inbound row `dead_letter` with reason `binding_missing`; no `dream_signals` row and no `channel_outbox` row are created |
| TC-M7-04 | Message triggers a forged CLI via memory retrieval | Bot reply contains the CLI's output after the gateway edge loop delivers the outbox row; `use_count` increments |
| TC-M7-05 | `typhoon health` | Output includes DB latency, channel queue backlog/oldest age, gateway/cron liveness, last successful write timestamp, recorder health, and last dream run status |
| TC-M7-06 | `typhoon dream stats` after several runs | Output includes: clusters detected, graduated to proposal, approved, rejected, expired-unforged |
| TC-M7-07 | `typhoon tool show <name>` for active CLI | Output includes `use_count`, `success_count`, `last_used`, recent errors |

### 5.8 Cross-cutting invariants

| ID | What runs | Pass criterion |
|---|---|---|
| TC-XC-01 | Attempt any write via `typhoon sql` | Always rejected |
| TC-XC-02 | Approve any proposal; inject failure mid-transaction | No partial write survives |
| TC-XC-03 | `typhoon sql "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'skill%'"` | Returns 0 rows (no `skills`, `skill_triggers`, or `skill_proposals` tables) |
| TC-XC-04 | Insert into `config` with `type='float'`, value `'abc'` | CHECK constraint rejects |
| TC-XC-05 | `typhoon skill list` | Exit ≠ 0; command does not exist |

### 5.9 v0.1 is done when

All TC-M1-* through TC-M7-* and TC-XC-* pass in a single `make test` run against a freshly-initialized TursoDB instance. Zero subjective criteria.

---

## 6. Risks & Keepers

Each risk has a trigger (how we notice early), a built-in mitigation (designed into v0.1), a keeper (ongoing instrument), and a fallback (what to do if trigger fires).

| Risk | Trigger | Mitigation (built-in) | Keeper | Fallback |
|---|---|---|---|---|
| **R1. Dream produces noisy proposal briefs** | Rejection rate > 50% over 4 weeks | `dream.min_frequency=5`, `dream.min_score=0.7`; REM clusters only successful chains; forge hardens requirements before implementation | `typhoon dream stats` funnel (clusters → proposals → approved) | Tune thresholds up; improve brief template; suspend dream with `dream.enabled=false` |
| **R2. Signals aren't a behavioral contract (accepted limitation)** | — | Admitted in §3 of PROPOSAL.md; forge owns correctness, not Typhoon | Per-CLI `success_count/use_count` ratio in `typhoon tool show` | `typhoon tool rollback` is always available; dream auto-proposes replacement on rising error rate |
| **R3. Hardcoded-path lint over-rejects useful source** | Path-lint rejection rate > 20% of submissions or repeated operator complaints | False positives are accepted in v0.1; forge revises source and resubmits | `typhoon dream stats` / proposal stats show lint rejection counts and reasons | Tune regex after examples accumulate; allow explicit operator override in a later version |
| **R4. Telegram signal volume too sparse** | 7-day rolling average < 20 signals/day | External-agent channel runs in parallel; Telegram is primary but not only — operator-driven activity through external agent CLIs also produces signals | `typhoon dream stats` shows 7-day signal volume per channel; `typhoon health` shows channel queue backlog so sparse signals are not confused with stuck delivery | Lower `dream.min_frequency`; add lightweight `/useful` Telegram command for explicit positive tagging |
| **R5. Operator forge burden heavier than forecast** | Expired-unforged ratio > 50% over 2 weeks | Thresholds tunable to throttle proposal rate | `typhoon dream stats` shows forge queue depth + expired rate | Raise thresholds; bring forward v0.2 forge automation |
| **R6. TursoDB concurrency / availability** | Transaction errors in logs; dream hangs | Single-writer task inside Typhoon; `BEGIN IMMEDIATE` for all approval transactions; `dream_runs` lease row + heartbeat + cooperative cancel for dream | `typhoon health` pings DB, reports latency + last-successful-write; rolls up dream lease state | Retry with exponential backoff; trust Turso SLA; if sustained, consider local libSQL fallback (v0.2 decision) |
| **R7. Forge's correctness claim mismatches reality** | Forged CLI passes forge's tests but behaves wrong in real use | Tier review intensity is operator-calibrated; mutate tier requires line-by-line review; forge submits a hardened requirement + test plan for review | Post-install `use_count` / `success_count` ratio per CLI | `typhoon tool rollback`; dream proposes replacement; tighten future forge requirements and test plans |
| **R8. Success tagging false-positives from abandoned tasks** | Operator notices CLIs proposed for workflows they didn't actually complete; dream quality degrades despite threshold tuning | Simple heuristic for v0.1: exit 0 + no next-turn correction. Known limitation. | `typhoon dream stats` exposes proposal origin breakdown: chains with explicit positive signal vs. chains tagged successful by heuristic only | Add explicit `/good` Telegram command for positive tagging; in v0.2, consider LLM-based correction detection |

---

## 7. Cross-Cutting Invariants

These apply throughout the project. Each phase must not violate them. See `CLAUDE.md` for the canonical list.

1. **Single binary for Typhoon.** No Python, no Node in the runtime. Generated CLIs may use any language.
2. **Every proposal approval is atomic** — `BEGIN IMMEDIATE … COMMIT`, rollback on any failure.
3. **`typhoon sql` is SELECT-only.** DDL and DML are hard-rejected.
4. **`config set` validates type.** Float scores clamp to `[0.0, 1.0]`. SQL CHECK is belt-and-braces.
5. **Skills are not a concept.** No `skills`, `skill_triggers`, or `skill_proposals` tables. No `typhoon skill *` commands. CLIs are the only artifact.
6. **Typhoon does not write code.** Forge writes code; Typhoon writes proposal briefs and catalogs deliveries.
7. **Typhoon does not verify correctness.** Hardcoded-path lint and metadata capture are the only submit-time checks Typhoon performs. Correctness is the forge's responsibility, accepted or rejected by the operator.
8. **One runtime instance = one TursoDB database (shared with persona-core), serving multiple users with multiple personas.** Typhoon shares a TursoDB cloud database with persona-core. persona-core owns the `user` / `persona` / `audit_log` schema (migrations 001–006, schema-version row `('persona-core', N)`); Typhoon adds its own migrations on top (channel inbox/outbox queue, signal store, memory store, tool registry, proposal queues, daemon state; schema-version row `('typhoon', M)`). One Typhoon runtime instance owns one DB; the same DB can help admins work across machines for forge/review, but a second Typhoon runtime writer is not supported. The DB serves multiple users (auth-bearing humans, OAuth via persona-core — one admin seeded at init, plus authors who join via channel binding) and multiple personas (writer/agent identities owned by users; one user → many personas). Per-persona data (signals, memory, persona-attribute proposals) is scoped by `persona_slug`; tools are shared across all personas; the `role='admin'` user gate enforces ratification and tool-registry mutation; v0.1 maps one Telegram bot account to one persona. External channel I/O is decoupled from Typhoon Way's agent loop through durable queue rows, not an in-memory channel.

---

## 8. Decisions Still Open for DESIGN.md

These are design-doc concerns, not plan concerns, but flagging so they don't ambush:

1. **Session definition across channels** — Telegram thread vs. external-agent invocation grouping. Affects W5, W6, W21.
2. **Signal capture mechanism** — agent-library instrumentation vs. shell-script wrapper that calls `typhoon signal record`. Affects W5.
3. **Dream LLM choice** — Haiku 4.5 vs. MiniMax M2.7 vs. other. Affects W8; bake-off recommended before locking.
4. **Online LLM choice** — Claude Sonnet 4.6 vs. GPT-5 vs. GLM 5.1. Affects W21.
5. **Telegram execution permissions** — does a forged tool triggered via Telegram run with the same privileges as one triggered via external-agent CLI? v0.1 default: yes (the binary is trusted equally regardless of trigger). Document explicitly so it's not an accidental choice.
6. **Success-tagging edge cases** — what counts as a "correction"? Regex match? LLM classifier? Explicit `/good` command? Affects W6.
7. **Retrieval budget knobs** — exact `top_k`, similarity threshold, per-turn token budget. Affects W10.
8. **Replacement similarity thresholds** — embedding similarity and signal-overlap cutoffs. Affects W18.
9. **Forge delivery schema** — exact shape of the hardened requirement, `tool.md`, correctness argument, dependency metadata, and tests submitted via `typhoon tool propose submit`. Affects W14.
10. **Initial threshold values are placeholders.** `dream.min_frequency=5` and `dream.min_score=0.7` are guesses; expect to re-tune in the first two weeks of real signal capture. Not a design decision so much as an operating expectation — plan for the knobs to move.

Each of these has a default "make something work" answer that unblocks the phase; the design doc picks the real answer.
