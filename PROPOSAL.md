# Typhoon Way: Self-Growing Agent — Rust + TursoDB

> Reviewed with Meta AI on 2026-04-21. Revised 2026-04-21: human-in-the-loop self-growth model.

## Vision

A self-growing agent system built in Rust with TursoDB. Compiles to WASM. Runs anywhere — CLI, browser, Cloudflare Workers, edge. No YAML, no JSON config files, no Python. Everything lives in SQL.

The agent dreams, remembers, and grows new skills from experience — with human approval. All state is one TursoDB instance (local libsql or cloud replica).

**Agent-first**: Every CLI command is designed for agent consumption. Skills are plain text instructions that agents interpret, not scripts that execute directly.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ typhoon (Rust)                                      │
│ ┌─────────────┐ ┌──────────────┐ ┌────────────┐    │
│ │ dream-cortex│ │ memory-weaver│ │ skill-grow │    │
│ │ (cron)      │ │ (recall)     │ │ (propose)  │    │
│ └──────┬──────┘ └──────┬───────┘ └─────┬──────┘    │
│        │               │               │           │
│        └───────────────┼───────────────┘           │
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
  session_id INT,        -- links to session_analytics.id
  sequence_num INT,      -- order within session for pattern detection
  captured_at INT DEFAULT (unixepoch())
);
CREATE INDEX idx_signals_session ON dream_signals(session_id, sequence_num);
```

### Skills

```sql
CREATE TABLE skills (
  name TEXT PRIMARY KEY,
  description TEXT,
  procedure TEXT NOT NULL,  -- plain text instructions for agent
  status TEXT NOT NULL DEFAULT 'approved' CHECK(status IN ('draft','approved','disabled')),
  created_from TEXT,        -- 'proposal:123' or 'user'
  created_at INT DEFAULT (unixepoch()),
  use_count INT DEFAULT 0,
  success_count INT DEFAULT 0
);

CREATE TABLE skill_triggers (
  skill_name TEXT NOT NULL,
  phrase TEXT NOT NULL,
  PRIMARY KEY(skill_name, phrase),
  FOREIGN KEY(skill_name) REFERENCES skills(name) ON DELETE CASCADE
);
```

### Skill Proposals (discovered patterns awaiting approval)

```sql
CREATE TABLE skill_proposals (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  procedure TEXT NOT NULL,       -- draft plain text instructions
  triggers TEXT,                 -- CSV of suggested trigger phrases
  evidence TEXT,                 -- summary of signals that led to this
  value_score REAL,              -- calculated ROI score
  frequency INT,                 -- how many times pattern occurred
  success_rate REAL,             -- ratio of successful completions
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','expired')),
  created_skill TEXT,            -- name of skill created on approval (for idempotency)
  proposed_at INT DEFAULT (unixepoch()),
  resolved_at INT
);
CREATE UNIQUE INDEX idx_proposals_created_skill ON skill_proposals(created_skill) WHERE created_skill IS NOT NULL;
```

### Soul Proposals (personality changes awaiting approval)

```sql
CREATE TABLE soul_proposals (
  id INTEGER PRIMARY KEY,
  config_key TEXT NOT NULL,      -- e.g., 'agent.tone'
  proposed_value TEXT NOT NULL,
  current_value TEXT,
  evidence TEXT,                 -- summary of signals that led to this
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
  rejection_count INT NOT NULL DEFAULT 0,
  proposed_at INT DEFAULT (unixepoch()),
  resolved_at INT
);
CREATE INDEX idx_soul_proposals_key ON soul_proposals(config_key, status);
```

### Dream Runs + Analytics

```sql
CREATE TABLE dream_runs (
  id INTEGER PRIMARY KEY,
  started_at INT DEFAULT (unixepoch()),
  ended_at INT,
  phase TEXT,             -- 'light', 'rem', 'deep'
  promoted_count INT DEFAULT 0,
  proposals_created INT DEFAULT 0,
  report TEXT             -- summary for debug
);

CREATE TABLE session_analytics (
  id INTEGER PRIMARY KEY,
  started_at INT,
  ended_at INT,
  tool_calls INT,
  tool_sequence TEXT,     -- CSV of tool names in order
  user_corrections INT,
  skills_used TEXT,       -- CSV
  success INT DEFAULT 1,  -- 1 if session ended without errors
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
┌──────────────────────────────────────────────────┐
│ 1. EXPERIENCE                                    │
│ Every tool call → INSERT INTO dream_signals      │
│ Every memory hit → UPDATE recall_count++         │
│ Session end → INSERT INTO session_analytics      │
└──────────────┬───────────────────────────────────┘
               │
       ┌───────▼────────┐  3am cron or manual
       │ 2. LIGHT DREAM  │  Sort signals, dedupe
       └───────┬────────┘
               │
       ┌───────▼────────┐
       │ 3. REM DREAM    │  Cluster themes, detect patterns
       └───────┬────────┘  Score by value (frequency × success × span)
               │
       ┌───────▼────────┐
       │ 4. DEEP DREAM   │  Promote memories, create proposals
       └───┬────────┬───┘
           │        │
           │        └─────▶ 4a. MEMORY PROMOTION
           │               score > 0.8 → INSERT INTO memories
           │
           └──────────────▶ 4b. SKILL PROPOSAL
                           High-value pattern detected →
                           INSERT INTO skill_proposals (status='pending')
               │
       ┌───────▼────────┐
       │ 5. PROPOSE      │  Surface proposals to user
       └───────┬────────┘  "Deploy pattern detected 8x, 100% success"
               │
       ┌───────▼────────┐
       │ 6. APPROVE      │  User reviews, edits, approves
       └───────┬────────┘  INSERT INTO skills (status='approved')
               │
       ┌───────▼────────────────────────────────────┐
       │ 7. GROW                                    │
       │ Next session: skill triggers, agent uses   │
       │ Better performance → better signals → loop │
       └────────────────────────────────────────────┘
```

### Value Scoring (High ROI Detection)

| Signal        | Weight | Indicates High Value              |
|---------------|--------|-----------------------------------|
| Frequency     | 0.30   | Pattern occurs 5+ times           |
| Success Rate  | 0.25   | Completions without errors        |
| Sequence Len  | 0.20   | 3+ steps = automation candidate   |
| Time Span     | 0.15   | Repeats across days, not one session |
| Low Corrections | 0.10 | User didn't need to fix agent     |

Threshold for proposal: `value_score >= 0.7`, `frequency >= 5`

### Memory Promotion Scoring

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

# Dream & Growth
typhoon dream                     # Manual dream-tick
typhoon dream --catchup           # Run if >25h since last dream
typhoon cron                      # Daemon: run scheduled jobs

# Skills
typhoon skill list                # List all approved skills
typhoon skill show <name>         # Show procedure + stats
typhoon skill create <name>       # Create skill manually (opens editor)
typhoon skill edit <name>         # Edit existing skill
typhoon skill disable <name>      # Disable without deleting
typhoon skill delete <name>       # Delete skill

# Skill Proposals (discovered patterns)
typhoon propose list              # List pending skill proposals
typhoon propose show <id>         # Show proposal details + evidence
typhoon propose approve <id>      # Approve and create skill
typhoon propose edit <id>         # Edit before approving
typhoon propose reject <id>       # Reject proposal
typhoon propose expire            # Mark old proposals as expired

# Soul Proposals (personality changes)
typhoon soul list                 # List pending soul proposals
typhoon soul show <id>            # Show proposal details
typhoon soul approve <id>         # Approve and update config
typhoon soul reject <id>          # Reject proposal

# Config & Debug
typhoon config get <key>          # SELECT value FROM config
typhoon config set <key> <value>  # UPDATE config
typhoon sql "<query>"             # Debug escape hatch (SELECT only)
```

### Bootstrap

```bash
TURSO_URL="libsql://..." TURSO_TOKEN="..." typhoon init
```

Seed creates tables + inserts default config. `schema_migrations` prevents double-seed.

---

## Agent-First Execution Model

Skills are **plain text instructions** for agents, not executable scripts.

Example skill procedure:
```
Check if the git working directory is clean.
Run the test suite and ensure all tests pass.
Build the project in release mode.
Deploy to the preview environment using vercel --preview.
Copy the preview URL to clipboard and report to user.
```

The agent:
1. Reads the procedure as context
2. Decides which tools to use
3. Executes with its own safety checks
4. User can interrupt or redirect

This is safe because:
- No direct shell execution
- Agent mediates all actions
- User sees what agent does
- Natural language is flexible, not brittle

---

## WASM Deployment

Each target has different DB access requirements:

| Target | DB Access Method | Notes |
|--------|------------------|-------|
| Native CLI | libsql crate direct | File at `~/.typhoon/agent.db` |
| wasmtime | Host libSQL adapter | Host owns file permissions and calls libSQL |
| Cloudflare Workers | Host Turso HTTP adapter | Cloud-only, no local file |
| Browser | Host browser/Turso adapter | Cloud-only or browser-compatible storage |

### WIT Interface

The WIT interface is **stateless**. Native builds use the `libsql` crate directly; WASM components receive explicit host-provided DB operations:

```wit
package typhoon:core@0.1.0;

world typhoon {
  // Host provides
  import log: func(msg: string);
  import time-now: func() -> s64;
  import db-exec: func(sql: string, params: list<string>) -> result;
  import db-query: func(sql: string, params: list<string>) -> result<list<list<string>>>;

  // Module exports
  export dream-tick: func() -> result;
  export memory-search: func(query: string) -> list<string>;
  export skill-match: func(input: string) -> option<string>;
  export pending-proposals: func() -> list<string>;
}
```

WASM hosts decide how `db-exec` and `db-query` are implemented: local libSQL for wasmtime, Turso HTTP for Cloudflare Workers, or a browser-compatible storage adapter.

### Binary Variants

```
typhoon-core (Rust)
  ├── native: libsql crate direct
  ├── wasm: host-provided db-exec/db-query imports
  ├── dream-cortex: SQL does scoring, Rust does orchestration
  ├── memory-weaver: writes to libsql, syncs on cron
  └── skill-grow: discovers patterns, creates proposals
```

| Target              | Binary | DB Mode | Size |
|---------------------|--------|---------|------|
| Native CLI | `typhoon` | Local file | ~5MB |
| wasmtime | `typhoon.wasm` | Host libSQL adapter | ~3MB |
| Cloudflare Worker | `typhoon.wasm` | Host Turso HTTP adapter | ~3MB |
| Browser | `typhoon.wasm` | Host browser/Turso adapter | ~3MB |

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

## Atomicity and Idempotency

### Proposal Approval

Approval must be atomic and idempotent:

```sql
BEGIN IMMEDIATE;

-- Check proposal is still pending
SELECT id FROM skill_proposals WHERE id = ? AND status = 'pending';

-- Create skill (fails if name exists)
INSERT INTO skills (name, description, procedure, status, created_from)
VALUES (?, ?, ?, 'approved', 'proposal:' || ?);

-- Create triggers
INSERT INTO skill_triggers (skill_name, phrase) VALUES (?, ?);

-- Mark proposal approved with reference to created skill
UPDATE skill_proposals
SET status = 'approved', created_skill = ?, resolved_at = unixepoch()
WHERE id = ? AND status = 'pending';

COMMIT;
```

If any step fails, the transaction rolls back. The `created_skill` column with unique index prevents double-approval from creating duplicate skills.

### Soul Approval

```sql
BEGIN IMMEDIATE;

-- Check proposal is still pending
SELECT id FROM soul_proposals WHERE id = ? AND status = 'pending';

-- Update config
UPDATE config SET value = ?, updated_at = unixepoch() WHERE key = ?;

-- Mark proposal approved
UPDATE soul_proposals
SET status = 'approved', resolved_at = unixepoch()
WHERE id = ? AND status = 'pending';

COMMIT;
```

### Soul Rejection Tracking

Stop proposing after 3 rejections for the same config key:

```sql
-- On rejection
UPDATE soul_proposals
SET status = 'rejected', rejection_count = rejection_count + 1, resolved_at = unixepoch()
WHERE id = ?;

-- Before creating new proposal, check rejection history
SELECT SUM(rejection_count) as total_rejections
FROM soul_proposals
WHERE config_key = ?;
-- If total_rejections >= 3, do not create new proposal
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
- REM phase: pattern recognition, value scoring
- Deep phase: promotion scoring, INSERT INTO memories
- `dream_runs` logging
- `typhoon dream` manual trigger
- `typhoon cron` daemon with tokio-cron-scheduler

### Phase 4: Skill Growth (Week 4)
- Session analytics with tool sequence tracking
- Value scoring for pattern detection
- Proposal generation from high-value patterns
- `skill_proposals` table + CLI (`propose list/show/approve/reject`)
- Manual skill CRUD (`skill create/edit/delete`)
- Skill trigger matching (phrase → skill lookup)
- Success/failure tracking (use_count, success_count)

### Phase 5: Session Analytics + Soul (Week 5)
- `session_analytics` capture with success tracking
- Signal feeding into dream system
- REM phase detects personality patterns
- `soul_proposals` table + CLI (`soul list/show/approve/reject`)
- Rejection tracking (stop after 3 rejections per key)
- User approval flow (never auto-modify config)

### Phase 6: WASM + Distribution (Week 6)
- wit-bindgen world definition with host DB imports
- Compile to wasm32-wasip2
- wasmtime host CLI with libSQL adapter
- Cloudflare Worker with Turso HTTP adapter
- `typhoon link` for cloud replica
- Distribution: `curl | sh` installer

---

## No-Go Decisions

| Rejected          | Why                                             |
|-------------------|-------------------------------------------------|
| Auto-execute skills | Unsafe, user must see agent actions            |
| JSON/YAML procedures | Parsing complexity, agent interprets plain text |
| Silent skill creation | User must approve all new skills              |
| Silent soul changes | User must approve all personality changes       |
| NullClaw skills   | Constrained by runtime, no cron, no own daemon  |
| Zig               | No WASM Component Model, no libsql crate, team size |
| Raw file DB       | No replication, no edge sync — use TursoDB      |
| YAML/JSON config  | Parsing hell, self-modify is fragile            |
| Python/Node       | 30-100x slower, binary size 50MB+, no WASM      |
| Separate services | Single binary, single DB, zero ops              |
