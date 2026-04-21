# Implementation Plan v0.2.0

> Based on PROPOSAL.md (revised 2026-04-21). Human-in-the-loop self-growth model.
> Agent-first: skills are plain text instructions for agents, not executable scripts.

---

## Phase 1: Foundation

Goal: `typhoon init` creates DB offline, `typhoon config get/set` validates, `typhoon run` starts a REPL.

### 1.1 Cargo project scaffold

```
cargo init --name typhoon
```

**Dependencies** (`Cargo.toml`):
- `libsql` — TursoDB/local libSQL client
- `clap` (derive) — CLI parser
- `tokio` (full) — async runtime
- `anyhow` — error handling
- `serde` + `serde_json` — dream_runs.report serialization

**Layout**:
```
src/
  main.rs          — clap entrypoint
  cli.rs           — command definitions (init, config, run, dream, skill, propose, sql, cron, link)
  db.rs            — connection pool, migration runner
  seed.rs          — CREATE TABLE + default config inserts
  config.rs        — get/set/validate from config table
  repl.rs          — interactive REPL loop
  error.rs         — anyhow wrappers
```

### 1.2 Schema + seed (offline-first)

`src/db.rs` + `src/seed.rs`:
- `typhoon init` works with **no internet** — local file only:
  ```rust
  let db = Builder::new_local("~/.typhoon/agent.db").build().await?;
  ```
- `typhoon link` adds cloud sync later (Phase 6.4)
- Execute all CREATE TABLE statements:
  - `config`, `memories`, `dream_signals`, `skills`, `skill_triggers`
  - `skill_proposals`, `soul_proposals`, `dream_runs`, `session_analytics`, `schema_migrations`
- All status columns must be NOT NULL with CHECK constraints
- `skill_triggers` has composite primary key: `PRIMARY KEY(skill_name, phrase)`
- INSERT default config rows:
  - `agent.name` = `Typhoon`
  - `dream.cron` = `0 3 * * *`
  - `dream.min_score` = `0.8`
  - `dream.min_recall` = `3`
  - `dream.min_unique_queries` = `3`
  - `dream.recency_half_life_days` = `14`
  - `dream.max_age_days` = `30`
  - `agent.tone` = `concise`
- INSERT `schema_migrations` version `1`
- Guard: skip if `schema_migrations` already has version `1`

### 1.3 CLI commands

| Command | What it does |
|---------|-------------|
| `typhoon init` | Create `~/.typhoon/agent.db` locally, run seed (no internet) |
| `typhoon config get <key>` | `SELECT value FROM config WHERE key = ?` |
| `typhoon config set <key> <value>` | Validate type, then `INSERT OR REPLACE INTO config` |
| `typhoon config list` | `SELECT key, value, type FROM config` (debug convenience) |
| `typhoon config validate` | Check all config rows match their declared type |
| `typhoon run` | Start REPL |
| `typhoon sql "<query>"` | Execute raw SQL (SELECT only for safety) |

**Config safety** (`src/config.rs`):
- `config set` validates value against the `type` column before commit
- `type='float'` + `value='abc'` → rejected
- `type='cron'` + invalid cron expression → rejected
- Float values for scores must be 0.0-1.0
- SQL CHECK constraint as defense-in-depth

**SQL safety** (`src/cli.rs`):
- `typhoon sql` only allows SELECT statements
- Reject INSERT, UPDATE, DELETE, DROP, ALTER, CREATE

### 1.4 REPL loop

`src/repl.rs`:
- Read input line
- For now: echo back with `agent.name` prefix
- Quit on `exit` / `ctrl-d`
- Later phases plug in memory search, skill match, signal capture

**Phase 1 done when**: `typhoon init` works offline && `typhoon config get dream.cron` prints `0 3 * * *` && `config set bad_key abc` with type=float is rejected.

---

## Phase 2: Memory System

Goal: Store memories, capture signals, recall with decay.

### 2.1 Memory CRUD

`src/memory.rs`:
- `store(key, content, tags)` → INSERT OR REPLACE INTO memories
- `recall(key)` → SELECT + UPDATE recall_count++, append query hash
- `search(query)` → SQL LIKE on content + concept_tags, return ranked results
- `prune(max_age_days)` → DELETE memories older than threshold with low recall

### 2.2 Signal capture

`src/signal.rs`:
- `capture(key, snippet, source, session_id, sequence_num)` → INSERT INTO dream_signals
- Sources: `tool_call`, `user_correction`, `session_end`
- Hook into REPL: every command → `signal::capture`
- Track sequence within session for pattern detection

### 2.3 Decay mechanics

`src/memory.rs`:
- Recency score = `2^(-age / half_life_days)` where half_life from config
- Prune runs on `typhoon dream` or manually
- `recall_count` and `unique_queries` update on every recall
- Delete signals older than 7 days even if not promoted (prevent unbounded growth)

**Phase 2 done when**: Can store a memory, recall it, see recall_count increment, prune old ones.

---

## Phase 3: Dream Cycle

Goal: `typhoon dream` runs light → REM → deep pipeline.

### 3.1 Dream orchestrator

`src/dream.rs`:
- `run_dream()` → execute all three phases sequentially
- Wrap entire dream cycle in transaction for consistency
- Log to `dream_runs` with phase, promoted count, proposals created, report

### 3.2 Light phase

`src/dream/light.rs`:
- SELECT all dream_signals
- Deduplicate by key + snippet similarity
- Group by source
- Output: cleaned signal set

### 3.3 REM phase

`src/dream/rem.rs`:
- Cluster signals by concept tags and session patterns
- Detect recurring tool sequences across sessions
- Score each cluster for memory promotion:
  - Frequency: 0.24
  - Relevance: 0.30
  - Diversity: 0.15
  - Recency: 0.15
  - Consolidation: 0.10
  - Conceptual: 0.06
- Score patterns for skill proposal (value scoring):
  - Frequency: 0.30
  - Success Rate: 0.25
  - Sequence Length: 0.20
  - Time Span: 0.15
  - Low Corrections: 0.10
- Output: memory candidates + skill proposal candidates

### 3.4 Deep phase

`src/dream/deep.rs`:
- Filter memory candidates: score >= min_score, recall_count >= min_recall, unique_queries >= min_unique_queries
- Promote to `memories` table
- Filter skill candidates: value_score >= 0.7, frequency >= 5
- Create skill proposals (status='pending')
- Optionally create soul proposal in `soul_proposals` (status='pending')
- Delete processed signals

### 3.5 Cron daemon + catchup

`src/cron.rs`:
- Read `dream.cron` from config
- `tokio-cron-scheduler` to call `dream::run_dream()` on schedule
- `typhoon cron` starts the daemon
- `typhoon dream --catchup` — runs ONE dream if >25h since last `dream_runs` entry
- Use file lock to prevent concurrent dream runs

**Phase 3 done when**: `typhoon dream` processes signals, promotes to memories, creates proposals, logs the run. `--catchup` auto-runs when overdue.

---

## Phase 4: Skill Growth

Goal: Discover high-value patterns, propose skills, user approves, skills grow.

### 4.1 Session analytics

`src/analytics.rs`:
- On REPL start: INSERT INTO session_analytics (started_at)
- Track tool calls with sequence numbers
- On REPL exit: UPDATE with ended_at, tool_calls, tool_sequence, user_corrections, skills_used, success, summary
- Feed session data into dream_signals

### 4.2 Pattern detection

`src/grow.rs`:
- Query `session_analytics` for recurring tool sequences
- Identify high-value patterns:
  - Same tool sequence appears in 5+ sessions
  - High success rate (sessions ended without errors)
  - Spans multiple days (not just one-time workflow)
  - Low user corrections
- Calculate value_score from weighted signals

### 4.3 Proposal creation

`src/grow.rs`:
- Generate draft procedure from observed pattern (plain text description)
- Extract suggested trigger phrases from user inputs
- INSERT INTO skill_proposals with:
  - name (derived from pattern)
  - description
  - procedure (plain text instructions)
  - triggers (CSV)
  - evidence (summary of signals)
  - value_score, frequency, success_rate
  - status='pending'

### 4.4 Proposal CLI

| Command | What it does |
|---------|-------------|
| `typhoon propose list` | SELECT * FROM skill_proposals WHERE status='pending' |
| `typhoon propose show <id>` | Show proposal details + evidence |
| `typhoon propose approve <id>` | Create skill from proposal atomically (see 4.8) |
| `typhoon propose edit <id>` | Open editor to modify before approving |
| `typhoon propose reject <id>` | Set status='rejected' |
| `typhoon propose expire` | Set status='expired' for proposals older than 30 days |

### 4.5 Manual skill CRUD

`src/skill.rs`:
| Command | What it does |
|---------|-------------|
| `typhoon skill list` | SELECT name, use_count, success_count, status FROM skills |
| `typhoon skill show <name>` | Show full procedure + triggers + stats |
| `typhoon skill create <name>` | Open editor to write procedure, add triggers |
| `typhoon skill edit <name>` | Edit existing procedure |
| `typhoon skill disable <name>` | Set status='disabled' |
| `typhoon skill delete <name>` | DELETE FROM skills |

### 4.6 Skill trigger matching

`src/skill.rs`:
- `match_skill(input)` → longest match wins, then most used:
  ```sql
  SELECT skill_name FROM skill_triggers
  WHERE ? LIKE '%'||phrase||'%'
  AND skill_name IN (SELECT name FROM skills WHERE status='approved')
  ORDER BY LENGTH(phrase) DESC,
           (SELECT use_count FROM skills WHERE name=skill_name) DESC
  LIMIT 1
  ```
- Only match against approved skills
- Increment `use_count` on match
- Increment `success_count` on successful session completion

### 4.7 Agent-first execution

Skills are NOT executed by typhoon. They are:
1. Retrieved by trigger match
2. Passed to the agent as context/instructions
3. Agent interprets and executes using its own tools
4. Agent's safety checks apply
5. User can interrupt

Example flow:
```
User: "deploy preview"
Typhoon: matches trigger "deploy" → retrieves skill procedure
Agent: reads procedure, decides to run git status, npm build, vercel --preview
User: sees agent actions, can interrupt
```

### 4.8 Atomicity and idempotency

Proposal approval must be atomic and idempotent:

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

- If any step fails, transaction rolls back
- `created_skill` column with unique index prevents double-approval
- Retry of approved proposal is a no-op (already approved)

**Phase 4 done when**: High-value patterns surface as proposals, user can approve/reject, approved skills match on input, approval is atomic and idempotent.

---

## Phase 5: Session Analytics + Soul

Goal: Track sessions, detect personality drift, propose soul updates.

### 5.1 Session tracking

`src/analytics.rs`:
- Already implemented in Phase 4.1
- Additional tracking:
  - Count user corrections (when user says "no", "wrong", "actually...")
  - Track which skills were used
  - Capture session summary

### 5.2 Soul proposals

`src/soul.rs`:
- REM phase detects tone shifts (user says "be terse" 3x → proposal)
- Deep phase creates proposal: INSERT INTO soul_proposals (status='pending')
- Never auto-modify — show proposal on next REPL start, user confirms or rejects
- Track rejection count — stop proposing after 3 rejections for same config_key
- Approved proposals UPDATE config permanently

**Soul proposals schema** (see PROPOSAL.md):
- `soul_proposals` table with config_key, proposed_value, current_value, evidence
- `status TEXT NOT NULL` with CHECK constraint
- `rejection_count INT NOT NULL DEFAULT 0`

### 5.3 Soul CLI

| Command | What it does |
|---------|-------------|
| `typhoon soul list` | SELECT * FROM soul_proposals WHERE status='pending' |
| `typhoon soul show <id>` | Show proposal details + evidence |
| `typhoon soul approve <id>` | Update config, set status='approved' |
| `typhoon soul reject <id>` | Set status='rejected', increment rejection_count |

### 5.4 Atomicity requirements

All approvals must be atomic (wrapped in transaction):

```sql
BEGIN IMMEDIATE;
-- Check proposal is still pending
SELECT id FROM soul_proposals WHERE id = ? AND status = 'pending';
-- Update config
UPDATE config SET value = ?, updated_at = unixepoch() WHERE key = ?;
-- Mark approved
UPDATE soul_proposals SET status = 'approved', resolved_at = unixepoch()
WHERE id = ? AND status = 'pending';
COMMIT;
```

Before creating new soul proposal, check rejection history:
```sql
SELECT SUM(rejection_count) FROM soul_proposals WHERE config_key = ?;
-- If >= 3, do not create new proposal
```

### 5.5 Debug tool

`typhoon sql "<query>"` — SELECT only, verify works with all tables.

**Phase 5 done when**: Session ends log to analytics, soul proposals appear and require approval, rejections are tracked, total rejections >= 3 stops new proposals.

---

## Phase 6: WASM + Distribution

Goal: Compile to `typhoon.wasm`, run on wasmtime and edge runtimes.

### 6.1 WIT definition

`wit/typhoon.wit`:
```wit
package typhoon:core@0.1.0;

record db-statement {
  sql: string,
  params: list<string>,
}

world typhoon {
  // Host provides
  import log: func(msg: string);
  import time-now: func() -> s64;
  import db-exec: func(sql: string, params: list<string>) -> result;
  import db-query: func(sql: string, params: list<string>) -> result<list<list<string>>>;
  import db-batch: func(statements: list<db-statement>) -> result;

  // Module exports
  export dream-tick: func() -> result;
  export memory-search: func(query: string) -> list<string>;
  export skill-match: func(input: string) -> option<string>;
  export pending-proposals: func() -> list<string>;
}
```

DB access per target:
| Target | DB Access | Notes |
|--------|-----------|-------|
| Native CLI | libsql crate direct | File at `~/.typhoon/agent.db` |
| wasmtime | Host libSQL adapter | Host owns file permissions and calls libSQL |
| Cloudflare Workers | Host Turso HTTP adapter | Cloud-only, no local file |
| Browser | Host browser/Turso adapter | Cloud-only or browser-compatible storage |

Native builds call the `libsql` crate directly. WASM builds call `db-exec`, `db-query`, and atomic `db-batch`; each host decides how those imports are backed.

### 6.2 WASM compile

- Add `wit-bindgen` dependency
- Target: `wasm32-wasip2`
- `Cargo.toml` crate-type: `["cdylib"]`
- Release profile: opt-level "z", LTO true, codegen-units 1, panic abort, strip true
- Verify size < 3MB after build

### 6.3 Host bindings

`src/host_wasmtime.rs`:
- wasmtime host that provides `log`, `time-now`, `db-exec`, `db-query`, and `db-batch` imports
- DB: host opens libSQL and exposes query/exec operations to the module
- Calls exported `dream-tick`, `memory-search`, `skill-match`, `pending-proposals`

### 6.4 Turso cloud link

`typhoon link --url URL --token TOKEN`:
- Store credentials in config table (encrypted or env var)
- Sync local → cloud replica

### 6.5 Distribution

- `curl | sh` installer script
- GitHub Release with binary for linux/mac/windows + wasm

**Phase 6 done when**: `wasmtime run typhoon.wasm` executes dream-tick against a Turso cloud DB.

---

## Dependency Graph

```
Phase 1 (Foundation)
  ├── Phase 2 (Memory) ───── depends on 1.2 schema, 1.3 config
  ├── Phase 3 (Dream Cycle) ─ depends on 2.1 memories, 2.2 signals
  │     ├── Phase 4 (Skill Growth) ─ depends on 3.3 value scoring
  │     └── Phase 5 (Soul) ─ depends on 3.3 REM scoring + 4.1 analytics
  └── Phase 6 (WASM) ────── depends on all phases, compile last
```

## Success Criteria (v0.2.0)

- [ ] `typhoon init` works offline, creates `~/.typhoon/agent.db`
- [ ] All status columns are NOT NULL with CHECK constraints (no NULL bypass)
- [ ] `typhoon config get dream.cron` returns `0 3 * * *`
- [ ] `typhoon config set` rejects invalid values (type mismatch, out of range)
- [ ] `typhoon sql` only allows SELECT statements
- [ ] `typhoon dream --catchup` runs if >25h since last run
- [ ] Deep-phase mutations wrapped in transactions for consistency
- [ ] Stale signals (>7 days) pruned even if not promoted
- [ ] High-value patterns (frequency >= 5, value_score >= 0.7) surface as proposals
- [ ] `typhoon propose approve` creates skill from proposal atomically
- [ ] `typhoon propose reject` marks proposal rejected
- [ ] Proposal approval is idempotent (retry returns existing created skill)
- [ ] Skills are plain text instructions, not executable code
- [ ] Skill trigger matching: longest match wins, then most used
- [ ] Only approved skills match (draft/disabled ignored)
- [ ] Soul proposals stored in `soul_proposals` table (not direct config mutation)
- [ ] Soul proposals require user approval before applying
- [ ] Soul proposals stop after 3 total rejections per config_key
- [ ] `typhoon soul approve/reject` commands work
- [ ] `typhoon cron` daemon runs dreams on schedule
- [ ] Concurrent dream runs prevented by file lock
- [ ] `typhoon link` syncs to Turso cloud
- [ ] `typhoon.wasm` < 3MB, `wasmtime run typhoon.wasm dream-tick` works
- [ ] WASM host implements `db-batch` atomically or rejects the batch
- [ ] Agent runs 30 days, laptop sleeps 8h/night, no missed dreams, DB < 10MB
