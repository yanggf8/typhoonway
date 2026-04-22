# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Typhoon Way

A self-growing agent runtime in Rust with TursoDB/libSQL. Primary target is the native CLI binary; `wasm32-wasip2` + wasmtime is a secondary target for a portable artifact. Cloudflare Workers and browser were considered and rejected (see PROPOSAL §No-Go). All state (config, memory, signals, skills, proposals, analytics) lives in one SQL database — no YAML, no JSON config files, no Python.

**Agent-first**: every CLI command is shaped for agent consumption. Skills are plain-text procedures an agent interprets, not scripts the runtime executes.

**Self-growing with human approval**: the dream cycle mines signals for high-value patterns and writes them to `skill_proposals` / `soul_proposals`. Nothing takes effect until the user approves.

## Current State

**Pre-bootstrap / spec-stage.** The repo contains design docs only — no `Cargo.toml`, no `src/`, no compiled artifacts yet. The proposal itself is still being refined; scaffolding decisions and a new plan come after it settles.

Canonical doc:

- `PROPOSAL.md` — vision, tech-stack rationale, schema, self-growth loop, no-go list. **Single source of truth.**

**`OUTDATEDPLAN.md` and `OUTDATEDDESIGN.md`** (formerly `PLAN.md` / `DESIGN.md`) are kept for historical reference only. They describe an earlier scope (Cloudflare Workers, browser, `db-batch`) that has been rejected. Do not treat them as current; do not copy their patterns. A new plan and design will be written once the proposal settles.

## Planned CLI Surface

Once the crate is scaffolded, the following commands are the intended public interface (see `PROPOSAL.md` §"CLI Commands" for the full list):

```
typhoon init                        # Create ~/.typhoon/agent.db + seed (offline)
typhoon link --url URL --token TOK  # Add Turso cloud replica
typhoon run                         # Interactive REPL
typhoon dream [--catchup]           # Manual dream cycle; --catchup runs if >25h since last
typhoon cron                        # Scheduler daemon
typhoon skill {list|show|create|edit|disable|delete} ...
typhoon propose {list|show|approve|edit|reject|expire} ...
typhoon soul {list|show|approve|reject} ...
typhoon config {get|set|list|validate} ...
typhoon sql "<SELECT ...>"          # Debug, SELECT-only
```

WASM build target (optional, Phase 6): `cargo build --target wasm32-wasip2 --release`, output `target/wasm32-wasip2/release/typhoon.wasm` (size budget <3MB). Runs under wasmtime with a host that supplies `log`, `time-now`, `db-exec`, `db-query`, `db-batch` backed by a local libSQL connection.

## Architecture (high-level)

```
  clap entry ── cli/* ── config / memory / skill / soul
                              │          │
                           signal ──► dream (light → REM → deep)
                                        │
                                  analytics + grow
                                        │
                           ┌──────── db (libsql) ────────┐
                           │                             │
                     native (direct)              wasm (host imports)
```

_Module layout TBD — the file-by-file mapping will be drawn up when a new plan is written against the current PROPOSAL.md. Do not treat the old `OUTDATEDPLAN.md` phase/module layout as binding._

## Non-Negotiable Invariants

These are scattered across the three docs; violating any of them is a regression. Check against these before landing anything in their area:

- **Offline-first `init`**: `typhoon init` must create the DB with no network. Cloud replication is added later by `typhoon link`.
- **Seed idempotency**: seeding is gated on `schema_migrations` version; re-running `init` is a no-op.
- **All status columns are `NOT NULL` with `CHECK`** — `skills.status`, `skill_proposals.status`, `soul_proposals.status`. No NULL bypass of the state machine.
- **`skill_triggers` uses composite PK** `(skill_name, phrase)` with `ON DELETE CASCADE`.
- **Every proposal approval is wrapped in `BEGIN IMMEDIATE … COMMIT`.** Skill approval inserts the skill, inserts triggers, and stamps `skill_proposals.created_skill` atomically. The unique index on `created_skill` makes re-approval a no-op.
- **Soul approval atomicity**: config update and `soul_proposals.status='approved'` in one transaction.
- **Stop proposing after 3 rejections per `config_key`** (soul). Check `SUM(rejection_count)` before creating a new proposal for that key.
- **Stale signal prune**: delete `dream_signals` rows older than 7 days even if never promoted.
- **Concurrent dream runs are prevented by a file lock.**
- **`typhoon sql` accepts SELECT only.** Reject INSERT/UPDATE/DELETE/DROP/ALTER/CREATE.
- **`config set` validates against the row's declared `type`** (`string|int|float|bool|cron`) before writing; float scores clamped to `0.0..=1.0`. SQL `CHECK` is defense-in-depth.
- **Skills are plain text, never executable.** The runtime retrieves a procedure on trigger match and hands it to the agent as context. The agent picks tools and executes.
- **Only `status='approved'` skills match.** Draft/disabled are invisible to the matcher. Trigger resolution: longest `phrase` wins, then highest `use_count`.
- **wasmtime host must implement `db-batch` as `BEGIN IMMEDIATE … COMMIT` with rollback on error.** Never partial-apply. Native builds go through `libsql::Transaction` directly; the wasmtime path goes through the three host imports backed by the same local libSQL connection.

## Scoring Thresholds (don't drift these without updating docs)

- Memory promotion (deep phase): `score >= dream.min_score` (default 0.8), `recall_count >= dream.min_recall` (3), `unique_queries >= dream.min_unique_queries` (3).
  Weights: Frequency 0.24 · Relevance 0.30 · Diversity 0.15 · Recency 0.15 · Consolidation 0.10 · Conceptual 0.06.
- Skill proposal: `value_score >= 0.7` AND `frequency >= 5`.
  Weights: Frequency 0.30 · Success Rate 0.25 · Sequence Length 0.20 · Time Span 0.15 · Low Corrections 0.10.
- Recency decay: `2^(-age_days / dream.recency_half_life_days)` (default half-life 14d). Max age 30d.

## Acceptance Gate

TBD — the v0.2.0 success-criteria checklist in `OUTDATEDPLAN.md` is no longer authoritative. A new one will be written with the new plan.
