# Implementation Plan v0.1.1

> Based on PROPOSAL.md (Meta review 2026-04-21). CLI-only, zero NullClaw.
> Corroborated with Meta AI. 8 fixes applied.

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
- `serde` + `serde_json` — JSON procedures + dream_runs.report

**Layout**:
```
src/
  main.rs          — clap entrypoint
  cli.rs           — command definitions (init, config, run, dream, skill, sql, cron, link)
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
- Execute all CREATE TABLE statements (config, memories, dream_signals, skills, skill_triggers, dream_runs, session_analytics, schema_migrations)
- `skill_triggers` has composite primary key: `PRIMARY KEY(skill_name, phrase)` — prevents collision
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
| `typhoon sql "<query>"` | Execute raw SQL, print results |

**Config safety** (`src/config.rs`):
- `config set` validates value against the `type` column before commit
- `type='float'` + `value='abc'` → rejected
- `type='cron'` + invalid cron expression → rejected
- SQL CHECK constraint as defense-in-depth

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
- `capture(key, snippet, source)` → INSERT INTO dream_signals
- Sources: `tool_call`, `user_correction`, `session_end`
- Hook into REPL: every command → `signal::capture`

### 2.3 Decay mechanics

`src/memory.rs`:
- Recency score = `2^(-age / half_life_days)` where half_life from config
- Prune runs on `typhoon dream` or manually
- `recall_count` and `unique_queries` update on every recall

**Phase 2 done when**: Can store a memory, recall it, see recall_count increment, prune old ones.

---

## Phase 3: Dream Cycle

Goal: `typhoon dream` runs light → REM → deep pipeline.

### 3.1 Dream orchestrator

`src/dream.rs`:
- `run_dream()` → execute all three phases sequentially
- Log to `dream_runs` with phase, promoted count, report

### 3.2 Light phase

`src/dream/light.rs`:
- SELECT all dream_signals
- Deduplicate by key + snippet similarity
- Group by source
- Output: cleaned signal set

### 3.3 REM phase

`src/dream/rem.rs`:
- Cluster signals by concept tags
- Detect recurring phrases/patterns
- Score each cluster:
  - Frequency: 0.24
  - Relevance: 0.30
  - Diversity: 0.15
  - Recency: 0.15
  - Consolidation: 0.10
  - Conceptual: 0.06
- Output: candidate list with scores

### 3.4 Deep phase

`src/dream/deep.rs`:
- Filter candidates: score >= min_score, recall_count >= min_recall, unique_queries >= min_unique_queries
- Promote to `memories` table
- Optionally propose skill (if pattern matches self-growth triggers)
- Optionally propose soul update (UPDATE config for tone, needs approval flag)
- Delete processed signals

### 3.5 Cron daemon + catchup

`src/cron.rs`:
- Read `dream.cron` from config
- `tokio-cron-scheduler` to call `dream::run_dream()` on schedule
- `typhoon cron` starts the daemon
- `typhoon dream --catchup` — runs if >25h since last `dream_runs` entry (laptop was asleep at 3am)

**Phase 3 done when**: `typhoon dream` processes signals, promotes to memories, logs the run. `--catchup` auto-runs when overdue.

---

## Phase 4: Skill Forge

Goal: Detect patterns, auto-generate skills, trigger-match on user input.

### 4.1 Pattern detection

`src/forge.rs`:
- Query `dream_signals` and `session_analytics` for triggers:
  - 5+ tool calls in one session
  - Error → fix sequence
  - User correction (source = `user_correction`)
  - Novel workflow (no matching skill trigger)
- Extract procedure template from signal history

### 4.2 Skill creation (hardened procedures)

`src/skill.rs`:
- `create(name, description, procedure, triggers)` → INSERT INTO skills + skill_triggers
- **`procedure` stored as JSON steps, not freeform markdown**:
  ```json
  [{"step": "Check vercel.json exists"}, {"step": "Run npm build"}]
  ```
  Reason: freeform markdown lets skill-forge inject `; rm -rf /`. JSON steps are parsed, not executed. You control execution.
- Validate procedure JSON on INSERT — reject if not a `[{step: string}]` array
- `created_from` tracks origin session

### 4.3 Skill execution (collision-safe trigger matching)

`src/skill.rs`:
- `match_skill(input)` → longest match wins, then most used:
  ```sql
  SELECT skill_name FROM skill_triggers
  WHERE ? LIKE '%'||phrase||'%'
  ORDER BY LENGTH(phrase) DESC, use_count DESC
  LIMIT 1
  ```
- `run_skill(name)` → parse JSON procedure, step through it
- Increment `use_count` and `success_count`

### 4.4 CLI integration

| Command | What it does |
|---------|-------------|
| `typhoon skill list` | SELECT name, use_count, success_count FROM skills |
| `typhoon skill run <name>` | Execute skill procedure |

**Phase 4 done when**: A repeated pattern auto-generates a skill, `typhoon skill run` executes it.

---

## Phase 5: Session Analytics + Soul

Goal: Track sessions, detect personality drift, propose soul updates.

### 5.1 Session tracking

`src/analytics.rs`:
- On REPL start: INSERT INTO session_analytics (started_at)
- On REPL exit: UPDATE with ended_at, tool_calls, user_corrections, skills_used, summary
- Feed session data into dream_signals

### 5.2 Soul proposals

`src/soul.rs`:
- REM phase detects tone shifts (user says "be terse" 3x → proposal)
- Deep phase creates proposal: `INSERT INTO config (key='agent.tone', value='terse')` with approval flag
- Never auto-modify — show proposal on next REPL start, user confirms or rejects
- Approved proposals UPDATE config permanently

### 5.3 Debug tool

`typhoon sql "<query>"` — already built in Phase 1, confirm it works with all tables.

**Phase 5 done when**: Session ends log to analytics, soul proposals appear and require approval.

---

## Phase 6: WASM + Distribution

Goal: Compile to `typhoon.wasm`, run on wasmtime and edge runtimes.

### 6.1 WIT definition (pure exports only)

`wit/typhoon.wit`:
```wit
package typhoon:core@0.1.0;

world typhoon {
  import log: func(msg: string) -> ();
  import time-now: func() -> s64;

  export dream-tick: func() -> result;
  export memory-search: func(query: string) -> list<string>;
  export skill-match: func(input: string) -> option<string>;
}
```

No `sqlite-query` import. DB access:
- Native: `libsql` crate directly
- WASM: `@libsql/client-wasm` via wasm-bindgen, or host provides it through the runtime

WIT only exports pure functions. All DB happens inside the module.

### 6.2 WASM compile

- Add `wit-bindgen` dependency
- Target: `wasm32-wasip2`
- `Cargo.toml` crate-type: `["cdylib"]`
- Release profile: opt-level "z", LTO true, codegen-units 1, panic abort, strip true

### 6.3 Host bindings

`src/host_wasmtime.rs`:
- wasmtime host that provides `log`, `time-now` imports
- DB: native host opens libsql, passes results into module via shared memory or stdin/stdout
- Calls exported `dream-tick`, `memory-search`, `skill-match`

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
  │     ├── Phase 4 (Skill Forge) ─ depends on 3.3 REM scoring
  │     └── Phase 5 (Soul) ─ depends on 3.3 REM scoring + 2.1 memories
  └── Phase 6 (WASM) ────── depends on all phases, compile last
```

## Success Criteria (v0.1.0)

- [ ] `typhoon init` works offline, creates `~/.typhoon/agent.db` with zero files on disk
- [ ] `typhoon config get dream.cron` returns `0 3 * * *`
- [ ] `typhoon config set` rejects invalid values (type mismatch)
- [ ] `typhoon dream --catchup` runs if >25h since last run
- [ ] Skill-forge cannot write `DROP TABLE` to procedures — rejected by JSON validation
- [ ] `typhoon skill run` executes JSON steps, not shell
- [ ] Trigger collisions resolved: longest match wins, then most used
- [ ] Soul proposals require user approval before applying
- [ ] `typhoon cron` daemon runs dreams on schedule
- [ ] `typhoon link` syncs to Turso cloud
- [ ] `typhoon.wasm` < 3MB, `wasmtime run typhoon.wasm dream-tick` works
- [ ] Agent runs 30 days, laptop sleeps 8h/night, no missed dreams, DB < 10MB
