# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Typhoon Way

A self-growing agent runtime in Rust backed by TursoDB/libSQL. One binary, multiple processes (gateways, scheduler, dream batch, one-shot CLIs); one cloud TursoDB owns durable state; tool binaries live under `~/.typhoon/bin/`. Cloudflare Workers and browser were considered and rejected (PROPOSAL §No-Go).

**Agent-first.** Every CLI command accepts and emits JSON, exits with structured codes, and is safe to compose into pipelines. The same calls an interactive operator types are the calls an external agent issues.

**Self-growing with human approval.** The dream cycle mines signals for high-value patterns, drafts proposal briefs into `cli_proposals` / `soul_proposals`, the operator drives a forge workflow to harden each brief, and the operator ratifies. Nothing takes effect until ratification.

## Current State

**Spec-stage.** Design docs only — no `Cargo.toml`, no `src/`, no compiled artifacts.

| Doc | Role |
|---|---|
| `PROPOSAL.md` | Vision, tech-stack rationale, no-go list. Source of truth for **direction**. |
| `PLAN.md` | v0.1 work breakdown, milestones, test cases, risks, decisions deferred to DESIGN. Source of truth for **scope/budget**. |
| `HLD.html` | v0.1 high-level design (layer / logical / process / subsystem views, project layout, state machines). Source of truth for **architecture**. |
| `DLD_Notes.md` | Parked planning for the DLD: structure outline, per-chapter template, open decisions. Not the DLD itself. |
| `DESIGN-HLD-WIP.md` | Historical planning notes for HLD. Not authoritative. |
| `OUTDATEDPLAN.md`, `OUTDATEDDESIGN.md` | Earlier scope (Cloudflare Workers, browser, skills, `db-batch`). **Historical only**; do not copy patterns. |

When in doubt about architecture, the most-recent commits to `HLD.html` are the freshest source of truth.

## Vocabulary (terms changed — read against current docs, not OUTDATED*)

- **Tools, not skills.** The artifact is a forged or operator-promoted CLI installed under `~/.typhoon/bin/`. Tables: `cli_proposals`, tool registry rows, `~/.typhoon/bin/` binaries. The old "skills as plain-text procedures" model is gone.
- **Forge.** Operator-driven implementation step that turns a dream proposal brief into hardened requirements + source + tests + correctness argument. v0.1 is manual; a forge CLI may assist later. Typhoon does not synthesize source itself.
- **Canonical user.** Stable per-person identity (`canonical_user_id`). Two roles: **operator** (ratifies, manages tools, runs admin commands) and **user** (sends signals, consumes memory and tools). Channels (Telegram, etc.) bind to canonical users.
- **Use plane / management plane.** Runtime split. Use plane = routes through core, records signals (gateways, scheduler use targets, external-agent endpoints). Management plane = operates directly on state, no signals (tool manager, soul manager, dream, bootstrap, health, inspection). Same binary serves both; subcommand decides.
- **Subsystems S1–S5.** HLD §2.4 names the DLD chapter boundaries: S1 Platform, S2 Channels & dispatch, S3 Self-growth (dream), S4 Registry management, S5 Data access & adapters. S5 has four component groups: S5A APIs, S5B storage adapters, S5C service adapters, S5D transaction/lock primitives.

## Planned CLI Surface

Authoritative list in HLD §2.2 catalog and PROPOSAL §"CLI Commands". Key surfaces:

```
typhoon init --url URL --token TOK   # Schema migrations + seed operator (idempotent)
typhoon gateway --telegram           # Long-poll daemon
typhoon cron                         # Scheduler daemon
typhoon dream                        # File-locked batch
typhoon tool {propose,list,show,diff,history,disable,enable,
              rollback,delete,purge,promote,sync,check-deps}
typhoon soul {list,show,approve,reject}
typhoon signal record                # External-agent: report a tool call
typhoon memory query                 # External-agent: pull retrieval context
typhoon health                       # Daemon liveness (gateway + cron only)
typhoon config {get,set,list,validate}
typhoon sql "<SELECT ...>"           # SELECT-only inspection
```

Removed since the older proposal: `typhoon link` (folded into `init`), `typhoon run` (REPL dropped — `26c87ea`), `typhoon skill ...` (replaced by `typhoon tool ...`), `typhoon propose ...` (folded into `typhoon tool propose ...`).

WASM build target (optional, secondary): `cargo build --target wasm32-wasip2 --release`. Runs under wasmtime via host imports. Size budget <3MB. Not load-bearing for v0.1.

## Architecture (high-level)

HLD.html §2 is authoritative. Mental model:

- **Layer view (§2.1, matrix):** Presentation/interaction → Application/core → Integration (Service adapters | Data access) → Data store. Foundation and External services as side columns. External services attach only to Service adapters.
- **Logical view (§2.2):** ~16 modules across Application and Integration layers, plus three adapter modules.
- **Process view (§2.3):** Two long-running daemons (gateway, scheduler), one file-locked transient (dream), several one-shots. **No inter-process IPC** — coordination is TursoDB transactions and filesystem locks only. Six sequence diagrams for channel turn / external-agent / scheduled / dream / registry mutation / health.
- **Subsystem view (§2.4):** S1–S5 partition; cross-subsystem coupling goes through S5.

## Non-Negotiable Invariants

Spread across PROPOSAL/PLAN/HLD; violating any is a regression.

- **Bootstrap connects to operator-provided TursoDB.** `typhoon init --url URL --token TOK`. No local SQLite. Re-runs idempotent (gated on `schema_migrations` version).
- **Tools are shared; per-user data is isolated.** One tool registry serves every canonical user. Signals, memory, soul (per-user config) are `canonical_user_id`-tagged. Per-user isolation is enforced by data-access APIs, not by partitioned tables. Cross-user reads are a privacy bug. Dream is the deliberate exception — it scans across users so cross-user pattern overlap can motivate a shared tool.
- **Core dispatches; recorder records; only core drives the recorder.** Every "use" path routes through core. Anything bypassing core produces no signal.
- **Dream is a file-locked single writer.** `~/.typhoon/dream.lock`. Concurrent invocations fail fast. Lock released on process exit (even crash).
- **All status columns are `NOT NULL` with `CHECK`** — `cli_proposals.status`, `soul_proposals.status`, tool registry status. No NULL bypass of the state machine.
- **Every multi-row mutation is wrapped in `BEGIN IMMEDIATE … COMMIT`.** Tool approval = registry insert/update + seed memory + proposal status flip atomically. Soul approval = config row update + proposal status flip atomically. Forge submission = requirements/source/tests/path-lint + proposal status flip atomically.
- **Filesystem mutations follow the registry mutation protocol** (HLD §2.3): DB transaction + per-tool filesystem lock + staging path + checksum + atomic `rename(2)` + commit. DB is source of truth. `tool sync` repairs crash leftovers.
- **3-strike rejection is a dream-side guard, not a state.** Stop proposing after 3 rejections — CLI proposals per pattern; soul proposals per `(canonical_user_id, config_key)`.
- **Stale signals pruned after 7 days** even if never promoted.
- **`typhoon sql` accepts SELECT only.** INSERT/UPDATE/DELETE/DDL hard-rejected.
- **`config set` validates against the declared `type`** (`string|int|float|bool|cron`). Float scores clamped to `0.0..=1.0`. SQL CHECK is defense-in-depth.
- **Operator role required for every mutating `typhoon tool` / `typhoon soul approve` subcommand.** Users may invoke read-only listing and may approve their own soul proposals.
- **Identity is checked at boundaries, not deep inside libraries.** Gateway resolves binding (or runs onboarding) before invoking core; external-agent endpoints default to operator in v0.1; data-access libraries trust the `canonical_user_id` they receive.

## Scoring Thresholds (don't drift these without updating docs)

Placeholders to tune in the first two weeks (PLAN §8). Do not change without a doc update.

- **Memory promotion (deep phase):** `score >= dream.min_score` (0.8), `recall_count >= dream.min_recall` (3), `unique_queries >= dream.min_unique_queries` (3). Weights: Frequency 0.24 · Relevance 0.30 · Diversity 0.15 · Recency 0.15 · Consolidation 0.10 · Conceptual 0.06.
- **Tool proposal:** `value_score >= 0.7` AND `frequency >= 5`. Weights: Frequency 0.30 · Success Rate 0.25 · Sequence Length 0.20 · Time Span 0.15 · Low Corrections 0.10.
- **Recency decay:** `2^(-age_days / dream.recency_half_life_days)` (half-life 14d). Max age 30d.

## Acceptance Gate

PLAN §5.9 "v0.1 is done when" is the current criteria checklist. HLD review approval gates DLD drafting; DLD_Notes.md captures the DLD structure to use once HLD is signed off.

## Working with this repo

- **No code yet.** Edits target Markdown / HTML design docs.
- **HLD edits must stay self-consistent.** §2.1 layer view, §2.2 modules, §2.3 process sequences, §2.4 subsystems, §3 state machines reference each other. After any change, check the cross-references.
- **PROPOSAL / PLAN are living scope docs.** Revise in place; don't append.
- **OUTDATEDPLAN.md / OUTDATEDDESIGN.md are frozen.** Never modify.
- **DLD_Notes.md is WIP planning, not the DLD.** Updated alongside HLD when subsystem partitioning changes.
