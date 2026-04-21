# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Typhoon Way

A self-growing agent system in Rust with TursoDB. Compiles to WASM. Runs anywhere — CLI, browser, Cloudflare Workers, edge. All state lives in one TursoDB instance (local libsql or cloud replica).

**Agent-first**: Every CLI command is designed for agent consumption. Skills are plain text instructions that agents interpret, not scripts that execute directly.

**Self-growing with human approval**: The system discovers high-value patterns from usage, proposes them as skills, and the user approves. Nothing auto-executes.

## Tech Stack

- **Language**: Rust 2021
- **Database**: TursoDB / libSQL (edge replication, embedded, SQL)
- **Async**: tokio
- **CLI**: clap (derive)
- **WASM**: wasip2 + wit-bindgen
- **Config**: SQL table (zero files, self-modify, transactional)

## Build Commands

```bash
cargo build                    # Development build
cargo build --release          # Release build (optimized)
cargo test                     # Run all tests
cargo test <name>              # Run specific test
cargo run -- init              # Initialize DB at ~/.typhoon/agent.db
cargo run -- config get <key>  # Get config value
cargo run -- config set <k> <v> # Set config value
cargo run -- run               # Start REPL
cargo run -- dream             # Manual dream cycle
cargo run -- dream --catchup   # Run if >25h since last dream
cargo run -- skill list        # List approved skills
cargo run -- skill create <n>  # Create skill manually
cargo run -- propose list      # List pending skill proposals
cargo run -- propose approve <id>  # Approve proposal → create skill
cargo run -- soul list         # List pending soul proposals
cargo run -- soul approve <id> # Approve soul change
cargo run -- sql "<query>"     # Raw SQL debug (SELECT only)
```

### WASM Build

```bash
cargo build --target wasm32-wasip2 --release
# Output: target/wasm32-wasip2/release/typhoon.wasm (~3MB)
wasmtime run typhoon.wasm dream-tick
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ typhoon (Rust)                                      │
│ ┌─────────────┐ ┌──────────────┐ ┌────────────┐    │
│ │ dream-cortex│ │ memory-weaver│ │ skill-grow │    │
│ │ (cron)      │ │ (recall)     │ │ (propose)  │    │
│ └──────┬──────┘ └──────┬───────┘ └─────┬──────┘    │
│        └───────────────┼───────────────┘           │
│                        ▼                           │
│               ┌─────────────────┐                   │
│               │    TursoDB      │                   │
│               └─────────────────┘                   │
└─────────────────────────────────────────────────────┘
```

### Code Layout

```
src/
  main.rs        — clap entrypoint
  cli.rs         — command definitions
  db.rs          — connection pool, migrations
  seed.rs        — CREATE TABLE + defaults
  config.rs      — get/set/validate config
  memory.rs      — store/recall/search/prune
  signal.rs      — capture dream_signals
  dream.rs       — orchestrator: light → REM → deep
  dream/
    light.rs     — sort + deduplicate
    rem.rs       — pattern recognition, scoring
    deep.rs      — promotion + proposals
  skill.rs       — CRUD + trigger matching
  grow.rs        — pattern detection, proposal creation
  analytics.rs   — session tracking
  soul.rs        — personality proposals
  cron.rs        — tokio-cron-scheduler
  repl.rs        — interactive REPL
wit/
  typhoon.wit    — WASM component interface
```

## Self-Growth Loop

```
Experience → Dream → Propose → Approve → Grow → Better Experience
```

1. **Experience**: tool calls → signals, memories get recalled
2. **Dream** (3am or manual): Light → REM → Deep phases
3. **Propose**: High-value patterns surface as skill/soul proposals
4. **Approve**: User reviews, edits, approves
5. **Grow**: Approved skills improve future sessions

### Value Scoring (High ROI Detection)

| Signal | Weight |
|--------|--------|
| Frequency | 0.30 |
| Success Rate | 0.25 |
| Sequence Length | 0.20 |
| Time Span | 0.15 |
| Low Corrections | 0.10 |

Threshold: `value_score >= 0.7`, `frequency >= 5`

## Agent-First Execution

Skills are **plain text instructions** for agents:

```
Check if the git working directory is clean.
Run the test suite and ensure all tests pass.
Build the project in release mode.
Deploy to preview using vercel --preview.
```

The agent reads, interprets, decides tools, executes with its own safety. User sees everything, can interrupt.

## Database Tables

- `config` — key/value settings with type validation
- `memories` — declarative memory with recall tracking
- `dream_signals` — short-term signals with session tracking
- `skills` — procedures (plain text) + status NOT NULL (draft/approved/disabled)
- `skill_triggers` — phrase → skill mapping (composite PK, NOT NULL)
- `skill_proposals` — discovered patterns awaiting approval + created_skill for idempotency
- `soul_proposals` — personality changes awaiting approval + rejection_count
- `dream_runs` — dream cycle logs
- `session_analytics` — session metrics + tool sequences
- `schema_migrations` — version tracking

## WASM Deployment

| Target | DB Access | Notes |
|--------|-----------|-------|
| Native CLI | libsql crate direct | File at `~/.typhoon/agent.db` |
| wasmtime | Host libSQL adapter | Host owns file permissions and calls libSQL |
| Cloudflare Workers | Host Turso HTTP adapter | Cloud-only, no local file |
| Browser | Host browser/Turso adapter | Cloud-only or browser-compatible storage |

WIT interface imports `db-exec(sql, params)` and `db-query(sql, params)` so each host owns its storage and network permissions.

## Atomicity Requirements

All proposal approvals wrapped in `BEGIN IMMEDIATE ... COMMIT`:
- Skill approval creates skill + triggers atomically
- `created_skill` column prevents double-approval
- Soul approval updates config atomically
- Rejection increments `rejection_count`
- Stop proposing after 3 total rejections per config_key

## Implementation Phases

1. **Foundation**: init, config, REPL, migrations
2. **Memory**: CRUD, signals, decay, search
3. **Dream Cycle**: light/REM/deep, cron daemon
4. **Skill Growth**: analytics, pattern detection, proposals, approval (atomic)
5. **Soul**: personality proposals with rejection tracking
6. **WASM**: wit-bindgen with host DB imports, wasmtime, cloud link
