# Typhoon Way: Self-Growing Agent — Rust + TursoDB

> Reviewed with Meta AI on 2026-04-21. Key decisions locked.

## Vision

A self-growing agent system built in Rust with TursoDB. Compiles to WASM. Runs anywhere — CLI, browser, Cloudflare Workers, edge. No YAML, no JSON config files, no Python. Everything lives in SQL.

The agent dreams, remembers, and forges new skills from experience. All state is one TursoDB instance (local libsql or cloud replica).

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ typhoon (Rust)                                      │
│ ┌─────────────┐ ┌──────────────┐ ┌────────────┐    │
│ │ dream-cortex│ │ memory-weaver│ │ skill-forge│    │
│ │ (cron)      │ │ (recall)     │ │ (create)   │    │
│ └──────┬──────┘ └──────┬───────┘ └─────┬──────┘    │
│        │               │               │           │
│        └────────────────┼───────────────┘           │
│                        │                           │
│               ┌────────▼────────┐                   │
│               │    TursoDB      │                   │
│               │ libsql:// local │                   │
│               │ or cloud replica│                   │
│               └─────────────────┘                   │
└─────────────────────────────────────────────────────┘
         │
    ┌────┴────┬──────────┬───────────┐
    │         │          │           │
 wasmtime   CLI     browser    Cloudflare
            (REPL)  extension   Workers
```

---

## Tech Stack

| Layer     | Choice            | Why                                      |
|-----------|-------------------|------------------------------------------|
| Language  | Rust 2021         | Speed, safety, WASM, no GC pauses at 3am |
| DB        | TursoDB / libSQL  | Edge replication, embedded, SQL, vectors later |
| Async     | tokio             | Mature, cron, sqlx-like patterns         |
| CLI       | clap              | Derive macros, good help text            |
| WASM      | wasip2 + wit-bindgen | Component model, runs anywhere        |
| Config    | SQL table         | Zero files, self-modify, transactional   |
| No        | YAML, JSON files, Python, Node | Complexity, parsing bugs, size |

---

## Database Schema

All state in one TursoDB instance. Zero config files. Seeded on `typhoon init`.

### Config

```sql
CREATE TABLE config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('string','int','float','bool','cron')),
  description TEXT,
  updated_at INT DEFAULT (unixepoch())
);

-- Seeded defaults:
-- agent.name         = 'Typhoon'
-- dream.cron         = '0 3 * * *'
-- dream.min_score    = 0.8
-- dream.min_recall   = 3
-- dream.min_unique_queries = 3
-- dream.recency_half_life_days = 14
-- dream.max_age_days = 30
-- agent.tone         = 'concise'
```

### Memories

```sql
CREATE TABLE memories (
  key TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  recall_count INT DEFAULT 0,
  unique_queries INT DEFAULT 0,
  last_recalled INT DEFAULT (unixepoch()),
  created_at INT DEFAULT (unixepoch()),
  concept_tags TEXT,    -- CSV: "ui,theme,preference"
  query_hashes TEXT     -- CSV: "abc123,def456"
);
CREATE INDEX idx_memories_score ON memories(recall_count, last_recalled);
```

### Dream Signals (short-term before promotion)

```sql
CREATE TABLE dream_signals (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL,
  snippet TEXT NOT NULL,
  source TEXT,           -- 'tool_call', 'user_correction', 'session_end'
  captured_at INT DEFAULT (unixepoch())
);
```

### Skills

```sql
CREATE TABLE skills (
  name TEXT PRIMARY KEY,
  description TEXT,
  procedure TEXT NOT NULL,  -- markdown body, no frontmatter
  created_from TEXT,        -- 'session:2026-04-21' or 'user'
  created_at INT DEFAULT (unixepoch()),
  use_count INT DEFAULT 0,
  success_count INT DEFAULT 0
);

CREATE TABLE skill_triggers (
  skill_name TEXT,
  phrase TEXT,
  FOREIGN KEY(skill_name) REFERENCES skills(name) ON DELETE CASCADE
);
```

### Dream Runs + Analytics

```sql
CREATE TABLE dream_runs (
  id INTEGER PRIMARY KEY,
  started_at INT DEFAULT (unixepoch()),
  phase TEXT,             -- 'light', 'rem', 'deep'
  promoted_count INT DEFAULT 0,
  report TEXT             -- summary JSON for debug
);

CREATE TABLE session_analytics (
  id INTEGER PRIMARY KEY,
  started_at INT,
  ended_at INT,
  tool_calls INT,
  user_corrections INT,
  skills_used TEXT,       -- CSV
  summary TEXT
);

CREATE TABLE schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at INT DEFAULT (unixepoch())
);
```

---

## The Self-Growth Loop

```
┌──────────────────────────────────────────────┐
│ 1. EXPERIENCE                                │
│ Every tool call → INSERT INTO dream_signals  │
│ Every memory hit → UPDATE recall_count++     │
└──────────────┬───────────────────────────────┘
               │
       ┌───────▼────────┐  3am cron or manual
       │ 2. LIGHT DREAM  │  Sort signals, dedupe
       └───────┬────────┘
               │
       ┌───────▼────────┐
       │ 3. REM DREAM    │  Cluster themes, detect patterns
       └───────┬────────┘  "user says 'be terse' 3x"
               │
       ┌───────▼────────┐
       │ 4. DEEP DREAM   │  Score candidates, promote to memories
       └───┬────────┬───┘  score > 0.8 → INSERT INTO memories
           │        │
           │        └─────▶ 5a. SOUL UPDATE
           │               UPDATE config SET value='terse'
           │               WHERE key='agent.tone' (needs approval)
           │
           └───────────────▶ 5b. SKILL FORGE
                           If 5+ tool calls or error→fix pattern:
                           INSERT INTO skills + skill_triggers
               │
       ┌───────▼────────────────────────────────┐
       │ 6. APPLY                               │
       │ Next session: SELECT * FROM skills     │
       │ WHERE trigger MATCH user input         │
       └────────────────────────────────────────┘
```

### Promotion Scoring

| Signal        | Weight | Why                    |
|---------------|--------|------------------------|
| Frequency     | 0.24   | How often recalled     |
| Relevance     | 0.30   | Retrieval quality      |
| Diversity     | 0.15   | Distinct query contexts|
| Recency       | 0.15   | Time-decayed freshness |
| Consolidation | 0.10   | Multi-day recurrence   |
| Conceptual    | 0.06   | Concept-tag density    |

Thresholds: `minScore: 0.8`, `minRecallCount: 3`, `minUniqueQueries: 3`

---

## CLI Commands

```bash
typhoon init                      # Create ~/.typhoon/agent.db + seed
typhoon link --url URL --token TOKEN  # Add Turso cloud replica
typhoon run                       # Interactive REPL
typhoon dream                     # Manual dream-tick
typhoon cron                      # Daemon: run scheduled jobs
typhoon skill list                # SELECT * FROM skills
typhoon skill run <name>          # Execute procedure
typhoon config get <key>          # SELECT value FROM config
typhoon config set <key> <value>  # UPDATE config
typhoon sql "<query>"             # Debug escape hatch
```

### Bootstrap

```bash
TURSO_URL="libsql://..." TURSO_TOKEN="..." typhoon init
```

Seed creates tables + inserts default config. `schema_migrations` prevents double-seed.

---

## WASM Deployment

```
typhoon-core (Rust)
  ├── libsql crate → Turso cloud + local replica
  ├── dream-cortex: SQL does scoring, Rust does orchestration
  ├── memory-weaver: writes to libsql, syncs on cron
  └── skill-forge: generates new rows in skills table
Compile → typhoon.wasm ~3MB
Deploy: wasmtime, browser, Cloudflare Workers, NullClaw skill
```

| Target              | Limit       | 3MB Rust | Status |
|---------------------|-------------|----------|--------|
| Cloudflare Worker   | 10MB        | OK       | Easy   |
| Lambda              | 250MB       | OK       | Easy   |
| Browser             | ~5MB ideal  | OK       | Fine   |
| ESP32-S3            | 8MB flash   | OK       | Fits   |
| ESP32-C3            | 4MB flash   | Tight    | Risky  |
| NullClaw skill      | No limit    | OK       | Easy   |

### Release Profile

```toml
[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- Cargo project setup, clap CLI
- TursoDB connection + seed script
- `typhoon init`, `typhoon config get/set`
- Schema migrations system
- Basic REPL loop (`typhoon run`)

### Phase 2: Memory System (Week 2)
- `memories` table CRUD
- `dream_signals` capture (tool call → INSERT)
- Recall tracking (hit → UPDATE recall_count++)
- Decay mechanics (recency half-life, max age pruning)
- `memory_search` via SQL queries

### Phase 3: Dream Cycle (Week 3)
- `dream-cortex` orchestrator
- Light phase: sort + deduplicate signals
- REM phase: pattern recognition, theme clustering
- Deep phase: promotion scoring, INSERT INTO memories
- `dream_runs` logging
- `typhoon dream` manual trigger
- `typhoon cron` daemon with tokio-cron-scheduler

### Phase 4: Skill Forge (Week 4)
- Background review trigger (5+ tool calls, error recovery, user correction)
- Skill generation from patterns → INSERT INTO skills
- Skill trigger matching (phrase → skill lookup)
- `typhoon skill list/run`
- Success/failure tracking (use_count, success_count)
- Security: no code execution, procedures are declarative steps

### Phase 5: Session Analytics + Soul (Week 5)
- `session_analytics` capture
- Signal feeding into dream system
- REM phase detects personality patterns
- Soul update proposals (UPDATE config WHERE key='agent.tone')
- User approval flow (never auto-modify tone)
- `typhoon sql` debug escape hatch

### Phase 6: WASM + Distribution (Week 6)
- wit-bindgen world definition
- Compile to wasm32-wasip2
- wasmtime host CLI
- `typhoon link` for cloud replica
- Browser host (optional)
- Distribution: `curl | sh` installer

---

## WASM Component Interface (wit)

```wit
package typhoon:core@0.1.0;

world typhoon {
  import log: func(msg: string);
  import sqlite-query: func(sql: string) -> list<list<string>>;
  import time-now: func() -> s64;

  export dream-tick: func() -> result;
  export memory-search: func(query: string) -> list<string>;
  export skill-match: func(input: string) -> option<string>;
}
```

---

## No-Go Decisions

| Rejected          | Why                                             |
|-------------------|-------------------------------------------------|
| NullClaw skills   | Constrained by runtime, no cron, no own daemon  |
| Zig               | No WASM Component Model, no libsql crate, team size |
| SQLite files      | No replication, no edge sync                    |
| YAML/JSON config  | Parsing hell, self-modify is fragile            |
| Python/Node       | 30-100x slower, binary size 50MB+, no WASM      |
| Separate services | Single binary, single DB, zero ops              |
