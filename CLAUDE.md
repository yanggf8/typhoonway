# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Typhoon Way

A self-growing agent runtime in Rust backed by TursoDB/libSQL. One binary, multiple processes (channel gateway, scheduler, dream batch, one-shot CLIs); one cloud TursoDB owns durable state; tool binaries live under `~/.typhoon/bin/`. Cloudflare Workers and browser were considered and rejected (PROPOSAL §No-Go).

**Agent-first.** Every CLI command accepts and emits JSON, exits with structured codes, and is safe to compose into pipelines. The same calls an interactive operator types are the calls an external agent issues.

**Self-growing with human approval.** The dream cycle mines signals for high-value patterns, drafts proposal briefs into `cli_proposals` / `persona_proposals`, an admin drives a forge workflow to harden each brief (for tools), and an admin (or persona owner, for persona proposals) ratifies. Nothing takes effect until ratification.

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

- **Tools, not skills.** The artifact is a forged or admin-promoted CLI installed under `~/.typhoon/bin/`. Tables: `cli_proposals`, tool registry rows, `~/.typhoon/bin/` binaries. The old "skills as plain-text procedures" model is gone.
- **Forge.** Admin-driven implementation step that turns a dream proposal brief into hardened requirements + source + tests + correctness argument. v0.1 is manual; a forge CLI may assist later. Typhoon does not synthesize source itself.
- **User and persona, not canonical user.** Typhoon shares its TursoDB cloud database with **persona-core**, which owns the `user` and `persona` schema. A **user** is an OAuth-authenticated human (one row in `user`, with `role` ∈ `{admin, author}`). A **persona** is a writer/agent identity *owned by a user*, keyed by `slug`, holding the attribute bundle (`expression`, `mental_models`, `heuristics`, `antipatterns`, `limits`) that makes the agent behave as that persona. **One user → many personas.** Per-X data (signals, memory, persona-attribute proposals) is keyed by `persona_slug`. Tools are shared across all personas. The `admin` role gates ratification.
- **Channel binding.** v0.1 maps `(channel, bot_account_id, peer_id) → user_id` via a verified binding row, plus one Telegram bot account → one persona via configuration. Bot credentials select the active persona; admin uses an explicit `--persona` flag on the external-agent channel when not the primary one.
- **Persona proposals (was: soul proposals).** Dream-driven mutations to a persona row's attribute bundle, ratified through `typhoon persona approve`. Old "soul" terminology is retired.
- **Use plane / management plane.** Runtime split. Use plane = routes through core, records signals (gateway worker loop, scheduler use targets, the two use-plane CLI subcommands `typhoon signal record` and `typhoon memory query`). Management plane = operates directly on state, no signals (tool manager, persona manager, dream, bootstrap, health, inspection, and all the other one-shot CLI subcommands). The gateway edge loop is adapter-side ingress/egress: it talks to Telegram and the durable channel queue, never to core. Same binary serves all roles; subcommand decides. The two use-plane CLI subcommands are not a separate module — they invoke Core directly through normal CLI dispatch, with `--persona` defaulting to the admin's primary persona.
- **Subsystems S1–S5.** HLD §2.4 names the DLD chapter boundaries: S1 Platform, S2 Channels & dispatch, S3 Self-growth (dream), S4 Registry management, S5 Data access & adapters. S5 has four component groups: S5A APIs, S5B storage adapters, S5C service adapters, S5D transaction/lock primitives.

## Planned CLI Surface

Authoritative list in HLD §2.2 catalog and PROPOSAL §"CLI Commands". Key surfaces:

```
typhoon init --url URL --token TOK   # Apply Typhoon migrations on persona-core DB; mark deploying user as admin (idempotent)
typhoon gateway                      # Channel daemon; edge loop talks Telegram, worker loop consumes queue and invokes core
typhoon cron                         # Scheduler daemon
typhoon dream                        # File-locked batch
typhoon tool {propose,list,show,diff,history,disable,enable,
              rollback,delete,purge,promote,sync,check-deps}
typhoon persona {list,show,approve,reject}   # Persona-attribute proposals
typhoon signal record                # External-agent: report a tool call
typhoon memory query                 # External-agent: pull retrieval context
typhoon health                       # Daemon liveness (gateway + cron) and queue backlog
typhoon config {get,set,list,validate}
typhoon sql "<SELECT ...>"           # SELECT-only inspection
```

Removed since earlier drafts: `typhoon link` (folded into `init`), `typhoon run` (REPL dropped — `26c87ea`), `typhoon skill ...` (replaced by `typhoon tool ...`), `typhoon propose ...` (folded into `typhoon tool propose ...`), `typhoon soul ...` (renamed `typhoon persona ...`).

WASM build target (optional, secondary): `cargo build --target wasm32-wasip2 --release`. Runs under wasmtime via host imports. Size budget <3MB. Not load-bearing for v0.1.

## Architecture (high-level)

HLD.html §2 is authoritative. Mental model:

- **Layer view (§2.1, matrix):** Presentation/interaction → Application/core → Integration (Service adapters | Data access) → Data store. Foundation and External services as side columns. External services attach only to Service adapters.
- **Logical view (§2.2):** ~16 modules across Application and Integration layers, plus three adapter modules.
- **Process view (§2.3):** Two long-running daemons (channel gateway, scheduler), one file-locked transient (dream), several one-shots. The gateway edge and worker loops are decoupled by a durable Turso-backed channel queue, not an in-memory channel. Six sequence diagrams: channel edge delivery / queued gateway worker turn / scheduled / dream / registry mutation / health. The use-plane CLI subcommands (`typhoon signal record` / `typhoon memory query`) invoke Core directly through normal CLI dispatch and have no sequence diagram of their own.
- **Subsystem view (§2.4):** S1–S5 partition; cross-subsystem coupling goes through S5.

## Non-Negotiable Invariants

Spread across PROPOSAL/PLAN/HLD; violating any is a regression.

- **Bootstrap connects to a persona-core-managed TursoDB.** `typhoon init --url URL --token TOK`. The DB is shared with persona-core (which owns `user` / `persona` schema, migrations 001–006); Typhoon adds its own migrations on top. Bootstrap marks the deploying user as `admin` in persona-core's `user` table, then seeds Typhoon's system-scoped config. No local SQLite. Re-runs idempotent (gated on `('typhoon', N)` schema-version row).
- **Tools are shared; per-persona data is isolated.** One tool registry serves every persona. Signals, memory, persona-attribute proposals are `persona_slug`-tagged. Per-persona isolation is enforced by data-access APIs, not by partitioned tables. Cross-persona reads are a privacy bug. Dream is the deliberate exception — it scans across personas so cross-persona pattern overlap can motivate a shared tool.
- **Core dispatches; recorder records; only core drives the recorder.** Every "use" path routes through core. In channel turns, the LLM chooses tool calls from the manifest core provides; core mediates execution and records the result, but does not choose the tool. Scheduled use entries may target a specific tool/subcommand directly. The gateway edge loop only enqueues/dequeues external messages and never records signals. Anything bypassing core produces no signal.
- **Dream is a file-locked single writer.** `~/.typhoon/dream.lock`. Concurrent invocations fail fast. Lock released on process exit (even crash).
- **All status columns are `NOT NULL` with `CHECK`** — `cli_proposals.status`, `persona_proposals.status`, tool registry status. No NULL bypass of the state machine.
- **Every multi-row mutation is wrapped in `BEGIN IMMEDIATE … COMMIT`.** Tool approval = registry insert/update + seed memory + proposal status flip atomically. Persona approval = persona row attribute-column update + proposal status flip atomically. Forge submission = requirements/source/tests/path-lint + proposal status flip atomically.
- **Filesystem mutations follow the registry mutation protocol** (HLD §2.3): DB transaction + per-tool filesystem lock + staging path + checksum + atomic `rename(2)` + commit. DB is source of truth. `tool sync` repairs crash leftovers.
- **3-strike rejection is a dream-side guard, not a state.** Stop proposing after 3 rejections — CLI proposals per pattern; persona proposals per `(persona_slug, attribute_column)`.
- **Stale signals pruned after 7 days** even if never promoted.
- **`typhoon sql` accepts SELECT only.** INSERT/UPDATE/DELETE/DDL hard-rejected.
- **`config set` validates against the declared `type`** (`string|int|float|bool|cron`). Float scores clamped to `0.0..=1.0`. SQL CHECK is defense-in-depth. Note: this is Typhoon's *system-scoped* config, not per-persona behavior — that lives in the persona row.
- **`admin` role required for every mutating `typhoon tool` subcommand.** A persona's owning user may approve `typhoon persona` proposals targeting that persona; an admin may approve any. Non-admin users may invoke read-only listings.
- **Identity-and-persona is resolved at boundaries, not deep inside libraries.** The gateway worker loop resolves `(channel, bot_account_id, peer_id) → (user_id, persona_slug)` before invoking core; if no verified binding exists, it dead-letters the inbound queue row with `binding_missing` and does not enqueue a default reply. The use-plane CLI subcommands default `persona_slug` to the admin's primary persona in v0.1; data-access libraries trust the `persona_slug` they receive.
- **Typhoon writes the persona row only through approved persona proposals.** persona-core's web SPA / CLI may also write directly; both paths share the same `persona` row but Typhoon's path requires ratification.

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
