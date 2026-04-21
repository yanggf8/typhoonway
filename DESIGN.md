# Typhoon Way - Technical Design Document

> Version 1.0 | 2026-04-22

---

## 1. Module Architecture

### 1.1 Dependency Graph

```
                    ┌─────────────┐
                    │   main.rs   │
                    │   (clap)    │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   cli/*     │
                    │  (commands) │
                    └──────┬──────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
   ┌─────────┐      ┌───────────┐      ┌───────────┐
   │ config  │      │  memory   │      │   skill   │
   └────┬────┘      └─────┬─────┘      └─────┬─────┘
        │                 │                  │
        │           ┌─────▼─────┐            │
        │           │  signal   │            │
        │           └─────┬─────┘            │
        │                 │                  │
        │           ┌─────▼─────┐      ┌─────▼─────┐
        │           │   dream   │      │   soul    │
        │           └─────┬─────┘      └───────────┘
        │                 │
        │           ┌─────▼─────┐
        │           │ analytics │
        │           └───────────┘
        │
        └──────────────────┬──────────────────┐
                           │                  │
                    ┌──────▼──────┐    ┌──────▼──────┐
                    │     db      │    │    wasm    │
                    │ (libsql)    │    │ (wit-bind) │
                    └─────────────┘    └─────────────┘
```

### 1.2 Module Responsibilities

| Module | Responsibility | Public API |
|--------|----------------|------------|
| `db` | Connection, migrations, transactions | `Database`, `with_transaction()` |
| `config` | Config CRUD with type validation | `get()`, `set()`, `list()`, `validate()` |
| `memory` | Memory storage, recall, search, decay | `store()`, `recall()`, `search()`, `prune()` |
| `signal` | Signal capture and session tracking | `capture()`, `start_session()`, `end_session()` |
| `dream` | Dream cycle orchestration | `run_dream()`, `needs_catchup()` |
| `skill` | Skill CRUD and trigger matching | `create()`, `match_trigger()`, `increment_use()` |
| `soul` | Soul proposal management | `create_proposal()`, `approve()`, `reject()` |
| `analytics` | Session metrics and pattern detection | `track_tool()`, `get_patterns()` |
| `cli` | Command implementations | One function per subcommand |
| `wasm` | WASM bindings abstraction | `DbAdapter` trait |

---

## 2. Data Types

### 2.1 Core Enums

```rust
/// Configuration value types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConfigType {
    String,
    Int,
    Float,
    Bool,
    Cron,
}

/// Signal sources
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SignalSource {
    ToolCall,
    UserCorrection,
    SessionEnd,
}

/// Skill lifecycle states
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SkillStatus {
    Draft,
    Approved,
    Disabled,
}

/// Proposal lifecycle states
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProposalStatus {
    Pending,
    Approved,
    Rejected,
    Expired,  // skill_proposals only
}

/// Dream phases
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DreamPhase {
    Light,
    Rem,
    Deep,
}
```

### 2.2 Domain Structs

```rust
/// Config entry
pub struct ConfigEntry {
    pub key: String,
    pub value: String,
    pub config_type: ConfigType,
    pub description: Option<String>,
    pub updated_at: i64,
}

/// Memory record
pub struct Memory {
    pub key: String,
    pub content: String,
    pub recall_count: i32,
    pub unique_queries: i32,
    pub last_recalled: i64,
    pub created_at: i64,
    pub concept_tags: Vec<String>,   // Stored as CSV
    pub query_hashes: Vec<String>,   // Stored as CSV
}

/// Dream signal
pub struct DreamSignal {
    pub id: i64,
    pub key: String,
    pub snippet: String,
    pub source: SignalSource,
    pub session_id: Option<i64>,
    pub sequence_num: Option<i32>,
    pub captured_at: i64,
}

/// Skill definition
pub struct Skill {
    pub name: String,
    pub description: Option<String>,
    pub procedure: String,           // Plain text instructions
    pub status: SkillStatus,
    pub created_from: Option<String>,
    pub created_at: i64,
    pub use_count: i32,
    pub success_count: i32,
}

/// Skill trigger phrase
pub struct SkillTrigger {
    pub skill_name: String,
    pub phrase: String,
}

/// Skill proposal
pub struct SkillProposal {
    pub id: i64,
    pub name: String,
    pub description: Option<String>,
    pub procedure: String,
    pub triggers: Vec<String>,       // Stored as CSV
    pub evidence: Option<String>,
    pub value_score: f64,
    pub frequency: i32,
    pub success_rate: f64,
    pub status: ProposalStatus,
    pub created_skill: Option<String>,
    pub proposed_at: i64,
    pub resolved_at: Option<i64>,
}

/// Soul proposal
pub struct SoulProposal {
    pub id: i64,
    pub config_key: String,
    pub proposed_value: String,
    pub current_value: Option<String>,
    pub evidence: Option<String>,
    pub status: ProposalStatus,
    pub rejection_count: i32,
    pub proposed_at: i64,
    pub resolved_at: Option<i64>,
}

/// Dream run log
pub struct DreamRun {
    pub id: i64,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub phase: Option<DreamPhase>,
    pub status: String,             // running/completed/failed
    pub promoted_count: i32,
    pub proposals_created: i32,
    pub report: Option<String>,
}

/// Session analytics
pub struct SessionAnalytics {
    pub id: i64,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub tool_calls: i32,
    pub tool_sequence: Vec<String>,  // Stored as CSV
    pub user_corrections: i32,
    pub skills_used: Vec<String>,    // Stored as CSV
    pub success: bool,
    pub summary: Option<String>,
}
```

### 2.3 Scoring Configuration

```rust
/// Memory promotion scoring weights
pub struct MemoryScoreConfig {
    pub frequency_weight: f64,      // 0.24
    pub relevance_weight: f64,      // 0.30
    pub diversity_weight: f64,      // 0.15
    pub recency_weight: f64,        // 0.15
    pub consolidation_weight: f64,  // 0.10
    pub conceptual_weight: f64,     // 0.06
}

impl Default for MemoryScoreConfig {
    fn default() -> Self {
        Self {
            frequency_weight: 0.24,
            relevance_weight: 0.30,
            diversity_weight: 0.15,
            recency_weight: 0.15,
            consolidation_weight: 0.10,
            conceptual_weight: 0.06,
        }
    }
}

/// Skill value scoring weights
pub struct ValueScoreConfig {
    pub frequency_weight: f64,       // 0.30
    pub success_rate_weight: f64,    // 0.25
    pub sequence_len_weight: f64,    // 0.20
    pub time_span_weight: f64,       // 0.15
    pub low_corrections_weight: f64, // 0.10
}

impl Default for ValueScoreConfig {
    fn default() -> Self {
        Self {
            frequency_weight: 0.30,
            success_rate_weight: 0.25,
            sequence_len_weight: 0.20,
            time_span_weight: 0.15,
            low_corrections_weight: 0.10,
        }
    }
}
```

### 2.4 Dream Intermediate Types

```rust
/// Memory candidate for promotion
pub struct MemoryCandidate {
    pub key: String,
    pub content: String,
    pub concept_tags: Vec<String>,
    pub score: f64,
    pub recall_count: i32,
    pub unique_queries: i32,
}

/// Skill candidate for proposal
pub struct SkillCandidate {
    pub name: String,
    pub description: String,
    pub procedure: String,
    pub triggers: Vec<String>,
    pub evidence: String,
    pub value_score: f64,
    pub frequency: i32,
    pub success_rate: f64,
}

/// Soul candidate for proposal
pub struct SoulCandidate {
    pub config_key: String,
    pub proposed_value: String,
    pub evidence: String,
}

/// Light phase output
pub struct LightPhaseResult {
    pub deduplicated_signals: Vec<DreamSignal>,
    pub signal_groups: HashMap<SignalSource, Vec<DreamSignal>>,
}

/// REM phase output
pub struct RemPhaseResult {
    pub memory_candidates: Vec<MemoryCandidate>,
    pub skill_candidates: Vec<SkillCandidate>,
    pub soul_candidates: Vec<SoulCandidate>,
}

/// Deep phase output
pub struct DeepPhaseResult {
    pub promoted_memories: i32,
    pub skill_proposals_created: i32,
    pub soul_proposals_created: i32,
    pub signals_cleaned: i32,
}

/// Full dream run report
pub struct DreamReport {
    pub run_id: i64,
    pub duration_ms: i64,
    pub light: LightPhaseResult,
    pub rem: RemPhaseResult,
    pub deep: DeepPhaseResult,
}
```

---

## 3. Database Layer

### 3.1 Connection Types

```rust
/// Database configuration
pub enum DbConfig {
    /// Local file only (offline-first)
    LocalFile { path: PathBuf },

    /// Remote Turso only (cloud)
    Remote { url: String, token: String },

    /// Embedded replica (local + sync)
    EmbeddedReplica {
        local_path: PathBuf,
        url: String,
        token: String,
    },
}

/// Database wrapper
pub struct Database {
    conn: libsql::Connection,
    config: DbConfig,
}
```

### 3.2 Connection API

```rust
impl Database {
    /// Connect based on configuration
    pub async fn connect(config: DbConfig) -> Result<Self>;

    /// Get connection reference
    pub fn conn(&self) -> &libsql::Connection;

    /// Start immediate transaction (write lock)
    pub async fn begin_immediate(&self) -> Result<Transaction>;

    /// Sync embedded replica with remote
    pub async fn sync(&self) -> Result<()>;

    /// Check if database is initialized
    pub async fn is_initialized(&self) -> Result<bool>;

    /// Get default database path
    pub fn default_path() -> PathBuf {
        dirs::home_dir()
            .unwrap_or_default()
            .join(".typhoon")
            .join("agent.db")
    }
}
```

### 3.3 Transaction Helper

```rust
/// Execute closure within transaction, rollback on error
pub async fn with_transaction<F, T, Fut>(db: &Database, f: F) -> Result<T>
where
    F: FnOnce(&Transaction) -> Fut,
    Fut: Future<Output = Result<T>>,
{
    let tx = db.begin_immediate().await?;
    match f(&tx).await {
        Ok(result) => {
            tx.commit().await?;
            Ok(result)
        }
        Err(e) => {
            tx.rollback().await?;
            Err(e)
        }
    }
}
```

### 3.4 Migration System

```rust
/// Single migration
pub struct Migration {
    pub version: &'static str,
    pub up: &'static str,
}

/// Migration runner
pub struct MigrationRunner<'a> {
    db: &'a Database,
    migrations: &'static [Migration],
}

impl<'a> MigrationRunner<'a> {
    /// Run all pending migrations
    /// Returns list of newly applied version strings
    pub async fn run(&self) -> Result<Vec<&'static str>>;

    /// Get current schema version
    pub async fn current_version(&self) -> Result<Option<String>>;

    /// Check if specific version is applied
    pub async fn is_applied(&self, version: &str) -> Result<bool>;
}

/// Static migrations list
pub static MIGRATIONS: &[Migration] = &[
    Migration {
        version: "001",
        up: include_str!("../migrations/001_initial.sql"),
    },
];
```

### 3.5 Query Helpers

```rust
/// Trait for converting database rows to structs
pub trait FromRow: Sized {
    fn from_row(row: &libsql::Row) -> Result<Self>;
}

/// Parse CSV string to Vec<String>
pub fn parse_csv(csv: &str) -> Vec<String> {
    if csv.is_empty() {
        Vec::new()
    } else {
        csv.split(',').map(|s| s.trim().to_string()).collect()
    }
}

/// Convert Vec<String> to CSV string
pub fn to_csv(items: &[String]) -> String {
    items.join(",")
}
```

---

## 4. Config Module

### 4.1 API

```rust
impl Config {
    /// Get config value by key
    pub async fn get(db: &Database, key: &str) -> Result<ConfigEntry>;

    /// Set config value with type validation
    pub async fn set(db: &Database, key: &str, value: &str) -> Result<()>;

    /// List all config entries
    pub async fn list(db: &Database) -> Result<Vec<ConfigEntry>>;

    /// Validate all config entries match their declared types
    pub async fn validate(db: &Database) -> Result<Vec<ValidationError>>;

    /// Get typed config value
    pub async fn get_string(db: &Database, key: &str) -> Result<String>;
    pub async fn get_int(db: &Database, key: &str) -> Result<i64>;
    pub async fn get_float(db: &Database, key: &str) -> Result<f64>;
    pub async fn get_bool(db: &Database, key: &str) -> Result<bool>;
}
```

### 4.2 Validation Rules

```rust
/// Validate value against config type
pub fn validate_config_value(key: &str, value: &str, config_type: ConfigType) -> Result<()> {
    match config_type {
        ConfigType::String => Ok(()),
        ConfigType::Int => {
            value.parse::<i64>()
                .map(|_| ())
                .map_err(|_| Error::ConfigValidation(
                    format!("'{}' is not a valid integer", value)
                ))
        }
        ConfigType::Float => {
            let f: f64 = value.parse()
                .map_err(|_| Error::ConfigValidation(
                    format!("'{}' is not a valid float", value)
                ))?;
            // Score values must be 0.0-1.0
            if key.contains("score") && !(0.0..=1.0).contains(&f) {
                return Err(Error::ConfigValidation(
                    format!("{} must be between 0.0 and 1.0, got {}", key, f)
                ));
            }
            Ok(())
        }
        ConfigType::Bool => {
            match value.to_lowercase().as_str() {
                "true" | "false" | "1" | "0" => Ok(()),
                _ => Err(Error::ConfigValidation(
                    format!("'{}' is not a valid boolean", value)
                ))
            }
        }
        ConfigType::Cron => {
            // Validate cron expression (5 fields)
            let parts: Vec<&str> = value.split_whitespace().collect();
            if parts.len() != 5 {
                return Err(Error::ConfigValidation(
                    format!("cron expression must have 5 fields, got {}", parts.len())
                ));
            }
            // Basic validation - each field should be valid
            for (i, part) in parts.iter().enumerate() {
                if !is_valid_cron_field(part, i) {
                    return Err(Error::ConfigValidation(
                        format!("invalid cron field {}: '{}'", i + 1, part)
                    ));
                }
            }
            Ok(())
        }
    }
}
```

---

## 5. Memory Module

### 5.1 API

```rust
impl Memory {
    /// Store or update a memory
    pub async fn store(
        db: &Database,
        key: &str,
        content: &str,
        tags: &[String],
    ) -> Result<()>;

    /// Recall a memory by key (increments recall_count)
    pub async fn recall(db: &Database, key: &str, query_hash: &str) -> Result<Memory>;

    /// Search memories by content and tags
    pub async fn search(
        db: &Database,
        query: &str,
        limit: usize,
    ) -> Result<Vec<Memory>>;

    /// Prune old memories with low recall
    pub async fn prune(
        db: &Database,
        max_age_days: i32,
        min_recall_count: i32,
    ) -> Result<i32>;  // Returns count deleted

    /// Get memory by key without incrementing recall
    pub async fn get(db: &Database, key: &str) -> Result<Option<Memory>>;

    /// Delete memory by key
    pub async fn delete(db: &Database, key: &str) -> Result<bool>;
}
```

### 5.2 Recall Logic

```rust
/// Recall increments recall_count and tracks unique queries
pub async fn recall(db: &Database, key: &str, query_hash: &str) -> Result<Memory> {
    let mut memory = Self::get(db, key).await?
        .ok_or_else(|| Error::MemoryNotFound(key.to_string()))?;

    // Check if this query hash is new
    let is_new_query = !memory.query_hashes.contains(&query_hash.to_string());

    // Update recall tracking
    let new_hashes = if is_new_query {
        memory.query_hashes.push(query_hash.to_string());
        to_csv(&memory.query_hashes)
    } else {
        to_csv(&memory.query_hashes)
    };

    db.conn().execute(
        "UPDATE memories SET
            recall_count = recall_count + 1,
            unique_queries = unique_queries + ?1,
            last_recalled = unixepoch(),
            query_hashes = ?2
         WHERE key = ?3",
        (if is_new_query { 1 } else { 0 }, new_hashes, key),
    ).await?;

    // Return updated memory
    Self::get(db, key).await?.ok_or_else(|| Error::MemoryNotFound(key.to_string()))
}
```

### 5.3 Search Algorithm

```rust
/// Search using SQL LIKE on content and concept_tags
pub async fn search(
    db: &Database,
    query: &str,
    limit: usize,
) -> Result<Vec<Memory>> {
    let pattern = format!("%{}%", query.to_lowercase());

    let rows = db.conn().query(
        "SELECT * FROM memories
         WHERE LOWER(content) LIKE ?1
            OR LOWER(concept_tags) LIKE ?1
         ORDER BY recall_count DESC, last_recalled DESC
         LIMIT ?2",
        (pattern, limit as i32),
    ).await?;

    let mut results = Vec::new();
    while let Some(row) = rows.next().await? {
        results.push(Memory::from_row(&row)?);
    }
    Ok(results)
}
```

### 5.4 Decay Formula

```rust
/// Calculate recency score with exponential decay
/// score = 2^(-age_days / half_life_days)
pub fn recency_score(last_recalled: i64, half_life_days: f64) -> f64 {
    let now = chrono::Utc::now().timestamp();
    let age_seconds = (now - last_recalled).max(0) as f64;
    let age_days = age_seconds / 86400.0;

    2.0_f64.powf(-age_days / half_life_days)
}
```

---

## 6. Signal Module

### 6.1 API

```rust
impl Signal {
    /// Capture a new signal
    pub async fn capture(
        db: &Database,
        key: &str,
        snippet: &str,
        source: SignalSource,
        session_id: Option<i64>,
        sequence_num: Option<i32>,
    ) -> Result<i64>;  // Returns signal id

    /// Get all signals (for dream processing)
    pub async fn get_all(db: &Database) -> Result<Vec<DreamSignal>>;

    /// Get signals by session
    pub async fn get_by_session(db: &Database, session_id: i64) -> Result<Vec<DreamSignal>>;

    /// Delete signals older than max_age_days
    pub async fn prune(db: &Database, max_age_days: i32) -> Result<i32>;

    /// Delete specific signals by id
    pub async fn delete_batch(db: &Database, ids: &[i64]) -> Result<i32>;
}
```

### 6.2 Session Tracking

```rust
impl Session {
    /// Start a new session
    pub async fn start(db: &Database) -> Result<i64>;  // Returns session_id

    /// Track a tool call within session
    pub async fn track_tool(
        db: &Database,
        session_id: i64,
        tool_name: &str,
    ) -> Result<i32>;  // Returns sequence_num

    /// Track a user correction
    pub async fn track_correction(db: &Database, session_id: i64) -> Result<()>;

    /// Track skill usage
    pub async fn track_skill(db: &Database, session_id: i64, skill_name: &str) -> Result<()>;

    /// End session with summary
    pub async fn end(
        db: &Database,
        session_id: i64,
        success: bool,
        summary: Option<&str>,
    ) -> Result<()>;

    /// Get session by id
    pub async fn get(db: &Database, session_id: i64) -> Result<Option<SessionAnalytics>>;
}
```

---

## 7. Dream Module

### 7.1 Orchestrator API

```rust
impl Dream {
    /// Run complete dream cycle
    pub async fn run(db: &Database) -> Result<DreamReport>;

    /// Check if catchup run is needed (>25h since last)
    pub async fn needs_catchup(db: &Database) -> Result<bool>;

    /// Get last dream run
    pub async fn last_run(db: &Database) -> Result<Option<DreamRun>>;
}
```

### 7.2 Orchestrator Flow

Dream run audit rows are written outside the deep-phase transaction so failures remain visible. Mutating dream work (memory promotion, proposal creation, signal cleanup, and final counters) is wrapped in one transaction. If light or REM fails, the run is marked `failed`; if deep fails, its transaction rolls back and the run is marked `failed`.

```rust
pub async fn run(db: &Database) -> Result<DreamReport> {
    let start = std::time::Instant::now();

    // Create dream run record
    let run_id = create_run(db).await?;

    let result = async {
        // Load config thresholds
        let min_score = Config::get_float(db, "dream.min_score").await?;
        let min_recall = Config::get_int(db, "dream.min_recall").await? as i32;
        let min_unique = Config::get_int(db, "dream.min_unique_queries").await? as i32;
        let half_life = Config::get_float(db, "dream.recency_half_life_days").await?;

        // Phase 1: Light
        update_phase(db, run_id, DreamPhase::Light).await?;
        let light = light::process(db).await?;

        // Phase 2: REM
        update_phase(db, run_id, DreamPhase::Rem).await?;
        let rem = rem::process(db, &light, half_life).await?;

        // Phase 3: Deep mutations and final counters are atomic
        update_phase(db, run_id, DreamPhase::Deep).await?;
        let deep = with_transaction(db, |tx| async {
            let deep = deep::process(tx, &rem, min_score, min_recall, min_unique).await?;
            finalize_run_tx(tx, run_id, &deep).await?;
            Ok(deep)
        }).await?;

        let duration_ms = start.elapsed().as_millis() as i64;
        Ok(DreamReport { run_id, duration_ms, light, rem, deep })
    }.await;

    if result.is_err() {
        mark_run_failed(db, run_id).await?;
    }

    result
}
```

### 7.3 Light Phase Algorithm

```rust
/// Light phase: deduplicate and group signals
pub async fn process(db: &Database) -> Result<LightPhaseResult> {
    let signals = Signal::get_all(db).await?;

    // Deduplicate by key + snippet similarity
    let deduplicated = deduplicate_signals(&signals);

    // Group by source
    let mut groups: HashMap<SignalSource, Vec<DreamSignal>> = HashMap::new();
    for signal in &deduplicated {
        groups.entry(signal.source).or_default().push(signal.clone());
    }

    Ok(LightPhaseResult {
        deduplicated_signals: deduplicated,
        signal_groups: groups,
    })
}

/// Deduplicate signals using Jaccard similarity
fn deduplicate_signals(signals: &[DreamSignal]) -> Vec<DreamSignal> {
    let mut unique: Vec<DreamSignal> = Vec::new();

    for signal in signals {
        let is_duplicate = unique.iter().any(|existing| {
            existing.key == signal.key &&
            jaccard_similarity(&existing.snippet, &signal.snippet) > 0.8
        });

        if !is_duplicate {
            unique.push(signal.clone());
        }
    }

    unique
}

/// Jaccard similarity between two strings (word-level)
fn jaccard_similarity(a: &str, b: &str) -> f64 {
    let set_a: HashSet<&str> = a.split_whitespace().collect();
    let set_b: HashSet<&str> = b.split_whitespace().collect();

    let intersection = set_a.intersection(&set_b).count();
    let union = set_a.union(&set_b).count();

    if union == 0 {
        0.0
    } else {
        intersection as f64 / union as f64
    }
}
```

### 7.4 REM Phase Algorithm

```rust
/// REM phase: cluster, detect patterns, score candidates
pub async fn process(
    db: &Database,
    light: &LightPhaseResult,
    half_life_days: f64,
) -> Result<RemPhaseResult> {
    // Score memory candidates
    let memory_candidates = score_memory_candidates(
        db,
        &light.deduplicated_signals,
        half_life_days,
    ).await?;

    // Detect tool sequence patterns from session_analytics
    let skill_candidates = detect_skill_patterns(db).await?;

    // Detect personality patterns from user corrections
    let soul_candidates = detect_soul_patterns(
        &light.signal_groups.get(&SignalSource::UserCorrection).unwrap_or(&vec![])
    );

    Ok(RemPhaseResult {
        memory_candidates,
        skill_candidates,
        soul_candidates,
    })
}
```

### 7.5 Memory Scoring Algorithm

```rust
/// Calculate memory promotion score
pub fn calculate_memory_score(
    signal_count: i32,
    recall_count: i32,
    unique_queries: i32,
    recency_score: f64,
    days_span: i32,
    concept_tag_count: i32,
    config: &MemoryScoreConfig,
) -> f64 {
    // Frequency: normalize by log scale
    let frequency = (signal_count as f64).ln_1p() / 10.0;
    let frequency_score = frequency.min(1.0);

    // Relevance: based on recall count
    let relevance = (recall_count as f64).ln_1p() / 5.0;
    let relevance_score = relevance.min(1.0);

    // Diversity: based on unique queries
    let diversity = (unique_queries as f64).ln_1p() / 3.0;
    let diversity_score = diversity.min(1.0);

    // Recency: already calculated as 2^(-age/half_life)
    let recency_normalized = recency_score;

    // Consolidation: based on days span
    let consolidation = (days_span as f64).ln_1p() / 4.0;
    let consolidation_score = consolidation.min(1.0);

    // Conceptual: based on tag density
    let conceptual = (concept_tag_count as f64) / 5.0;
    let conceptual_score = conceptual.min(1.0);

    // Weighted sum
    config.frequency_weight * frequency_score
        + config.relevance_weight * relevance_score
        + config.diversity_weight * diversity_score
        + config.recency_weight * recency_normalized
        + config.consolidation_weight * consolidation_score
        + config.conceptual_weight * conceptual_score
}
```

### 7.6 Skill Pattern Detection

```rust
#[derive(Default)]
pub struct SequenceStats {
    pub sequence: String,
    pub count: i32,
    pub success_count: i32,
    pub total_corrections: i32,
    pub first_seen: i64,
    pub last_seen: i64,
}

impl SequenceStats {
    pub fn success_rate(&self) -> f64 {
        if self.count == 0 { 0.0 } else { self.success_count as f64 / self.count as f64 }
    }

    pub fn days_span(&self) -> i32 {
        ((self.last_seen - self.first_seen).max(0) / 86_400) as i32
    }
}

/// Detect recurring tool sequences from session_analytics
pub async fn detect_skill_patterns(db: &Database) -> Result<Vec<SkillCandidate>> {
    // Get all sessions from last 30 days
    let sessions = db.conn().query(
        "SELECT tool_sequence, user_corrections, success, started_at
         FROM session_analytics
         WHERE started_at > unixepoch() - 30*24*60*60
           AND tool_sequence IS NOT NULL
           AND tool_sequence != ''",
        (),
    ).await?;

    // Extract tool sequences
    let mut sequence_counts: HashMap<String, SequenceStats> = HashMap::new();
    while let Some(row) = sessions.next().await? {
        let sequence: String = row.get(0)?;
        let corrections: i32 = row.get(1)?;
        let success: bool = row.get::<i32>(2)? != 0;
        let started_at: i64 = row.get(3)?;

        let stats = sequence_counts.entry(sequence.clone()).or_default();
        if stats.count == 0 {
            stats.sequence = sequence.clone();
            stats.first_seen = started_at;
            stats.last_seen = started_at;
        } else {
            stats.first_seen = stats.first_seen.min(started_at);
            stats.last_seen = stats.last_seen.max(started_at);
        }
        stats.count += 1;
        stats.success_count += if success { 1 } else { 0 };
        stats.total_corrections += corrections;
    }

    // Filter and score patterns
    let config = ValueScoreConfig::default();
    let mut candidates = Vec::new();

    for (sequence, stats) in sequence_counts {
        if stats.count >= 5 {
            let value_score = calculate_value_score(&stats, &config);
            if value_score >= 0.7 {
                candidates.push(SkillCandidate {
                    name: derive_skill_name(&sequence),
                    description: derive_description(&sequence),
                    procedure: derive_procedure(&sequence),
                    triggers: derive_triggers(&sequence),
                    evidence: format!("Occurred {} times with {}% success",
                        stats.count, (stats.success_rate() * 100.0) as i32),
                    value_score,
                    frequency: stats.count,
                    success_rate: stats.success_rate(),
                });
            }
        }
    }

    Ok(candidates)
}
```

### 7.7 Value Scoring Algorithm

```rust
/// Calculate skill value score
pub fn calculate_value_score(
    stats: &SequenceStats,
    config: &ValueScoreConfig,
) -> f64 {
    // Frequency: normalize (5 = 0.5, 10+ = 1.0)
    let frequency_score = (stats.count as f64 / 10.0).min(1.0);

    // Success rate: direct ratio
    let success_score = stats.success_rate();

    // Sequence length: normalize (3 = 0.5, 6+ = 1.0)
    let tools: Vec<&str> = stats.sequence.split(',').collect();
    let sequence_score = (tools.len() as f64 / 6.0).min(1.0);

    // Time span: based on first/last occurrence days
    let span_score = (stats.days_span() as f64 / 7.0).min(1.0);

    // Low corrections: inverse of correction rate
    let correction_rate = stats.total_corrections as f64 / stats.count as f64;
    let low_corrections_score = 1.0 - (correction_rate / 3.0).min(1.0);

    // Weighted sum
    config.frequency_weight * frequency_score
        + config.success_rate_weight * success_score
        + config.sequence_len_weight * sequence_score
        + config.time_span_weight * span_score
        + config.low_corrections_weight * low_corrections_score
}
```

### 7.8 Deep Phase Algorithm

```rust
/// Deep phase: promote memories, create proposals
pub async fn process(
    tx: &Transaction,
    rem: &RemPhaseResult,
    min_score: f64,
    min_recall: i32,
    min_unique: i32,
) -> Result<DeepPhaseResult> {
    let mut promoted = 0;
    let mut skill_proposals = 0;
    let mut soul_proposals = 0;

    // Promote qualifying memories
    for candidate in &rem.memory_candidates {
        if candidate.score >= min_score
            && candidate.recall_count >= min_recall
            && candidate.unique_queries >= min_unique
        {
            promote_memory(tx, candidate).await?;
            promoted += 1;
        }
    }

    // Create skill proposals
    for candidate in &rem.skill_candidates {
        create_skill_proposal(tx, candidate).await?;
        skill_proposals += 1;
    }

    // Create soul proposals (with rejection check)
    for candidate in &rem.soul_candidates {
        if can_propose_soul(tx, &candidate.config_key).await? {
            create_soul_proposal(tx, candidate).await?;
            soul_proposals += 1;
        }
    }

    // Clean old signals (>7 days)
    let cleaned = tx.execute(
        "DELETE FROM dream_signals WHERE captured_at < unixepoch() - 7*24*60*60",
        (),
    ).await?;

    Ok(DeepPhaseResult {
        promoted_memories: promoted,
        skill_proposals_created: skill_proposals,
        soul_proposals_created: soul_proposals,
        signals_cleaned: cleaned as i32,
    })
}
```

---

## 8. Skill Module

### 8.1 API

```rust
impl Skill {
    /// Create a new skill
    pub async fn create(
        db: &Database,
        name: &str,
        description: Option<&str>,
        procedure: &str,
        status: SkillStatus,
        triggers: &[String],
        created_from: Option<&str>,
    ) -> Result<()>;

    /// Get skill by name
    pub async fn get(db: &Database, name: &str) -> Result<Option<Skill>>;

    /// List all skills
    pub async fn list(db: &Database, status: Option<SkillStatus>) -> Result<Vec<Skill>>;

    /// Update skill
    pub async fn update(
        db: &Database,
        name: &str,
        description: Option<&str>,
        procedure: &str,
    ) -> Result<()>;

    /// Change skill status
    pub async fn set_status(db: &Database, name: &str, status: SkillStatus) -> Result<()>;

    /// Delete skill
    pub async fn delete(db: &Database, name: &str) -> Result<bool>;

    /// Get triggers for skill
    pub async fn get_triggers(db: &Database, name: &str) -> Result<Vec<String>>;

    /// Add trigger to skill
    pub async fn add_trigger(db: &Database, name: &str, phrase: &str) -> Result<()>;

    /// Remove trigger from skill
    pub async fn remove_trigger(db: &Database, name: &str, phrase: &str) -> Result<bool>;

    /// Increment use count
    pub async fn increment_use(db: &Database, name: &str) -> Result<()>;

    /// Increment success count
    pub async fn increment_success(db: &Database, name: &str) -> Result<()>;
}
```

### 8.2 Trigger Matching Algorithm

```rust
/// Match input against skill triggers
/// Returns: (skill_name, matched_phrase) or None
pub async fn match_trigger(db: &Database, input: &str) -> Result<Option<(String, String)>> {
    let input_lower = input.to_lowercase();

    // Query: longest phrase match first, then by use_count
    let rows = db.conn().query(
        "SELECT st.skill_name, st.phrase
         FROM skill_triggers st
         JOIN skills s ON s.name = st.skill_name
         WHERE s.status = 'approved'
           AND LOWER(?1) LIKE '%' || LOWER(st.phrase) || '%'
         ORDER BY LENGTH(st.phrase) DESC, s.use_count DESC
         LIMIT 1",
        (input_lower,),
    ).await?;

    if let Some(row) = rows.next().await? {
        let name: String = row.get(0)?;
        let phrase: String = row.get(1)?;
        Ok(Some((name, phrase)))
    } else {
        Ok(None)
    }
}
```

### 8.3 Proposal Approval (Atomic)

```rust
/// Approve skill proposal atomically
pub async fn approve_proposal(db: &Database, proposal_id: i64) -> Result<String> {
    with_transaction(db, |tx| async move {
        // 1. Get proposal and handle idempotent retry
        let proposal = get_proposal(tx, proposal_id).await?
            .ok_or(Error::ProposalNotFound(proposal_id))?;

        match proposal.status {
            ProposalStatus::Approved => {
                return proposal.created_skill
                    .ok_or(Error::ProposalAlreadyResolved(proposal_id));
            }
            ProposalStatus::Pending => {}
            ProposalStatus::Rejected | ProposalStatus::Expired => {
                return Err(Error::ProposalAlreadyResolved(proposal_id));
            }
        }

        // 2. Create skill
        tx.execute(
            "INSERT INTO skills (name, description, procedure, status, created_from)
             VALUES (?1, ?2, ?3, 'approved', ?4)",
            (
                &proposal.name,
                &proposal.description,
                &proposal.procedure,
                format!("proposal:{}", proposal_id),
            ),
        ).await?;

        // 3. Create triggers
        for trigger in &proposal.triggers {
            tx.execute(
                "INSERT INTO skill_triggers (skill_name, phrase) VALUES (?1, ?2)",
                (&proposal.name, trigger),
            ).await?;
        }

        // 4. Mark proposal approved and verify the pending row was updated
        let affected = tx.execute(
            "UPDATE skill_proposals
             SET status = 'approved',
                 created_skill = ?1,
                 resolved_at = unixepoch()
             WHERE id = ?2 AND status = 'pending'",
            (&proposal.name, proposal_id),
        ).await?;

        if affected == 0 {
            return Err(Error::ProposalAlreadyResolved(proposal_id));
        }

        Ok(proposal.name)
    }).await
}
```

---

## 9. Soul Module

### 9.1 API

```rust
impl Soul {
    /// Create soul proposal
    pub async fn create_proposal(
        db: &Database,
        config_key: &str,
        proposed_value: &str,
        evidence: &str,
    ) -> Result<i64>;

    /// Check if can propose for this key (< 3 total rejections)
    pub async fn can_propose(db: &Database, config_key: &str) -> Result<bool>;

    /// Get pending proposals
    pub async fn list_pending(db: &Database) -> Result<Vec<SoulProposal>>;

    /// Get proposal by id
    pub async fn get(db: &Database, id: i64) -> Result<Option<SoulProposal>>;

    /// Approve proposal (atomic)
    pub async fn approve(db: &Database, id: i64) -> Result<()>;

    /// Reject proposal (increments rejection_count)
    pub async fn reject(db: &Database, id: i64) -> Result<()>;
}
```

### 9.2 Rejection Tracking

```rust
const MAX_REJECTIONS_PER_KEY: i32 = 3;

/// Check if we can create new proposal for this config key
pub async fn can_propose(db: &Database, config_key: &str) -> Result<bool> {
    let row = db.conn().query_row(
        "SELECT COALESCE(SUM(rejection_count), 0) as total
         FROM soul_proposals
         WHERE config_key = ?1",
        (config_key,),
    ).await?;

    let total: i32 = row.get(0)?;
    Ok(total < MAX_REJECTIONS_PER_KEY)
}

/// Reject proposal and increment rejection count
pub async fn reject(db: &Database, id: i64) -> Result<()> {
    let affected = db.conn().execute(
        "UPDATE soul_proposals
         SET status = 'rejected',
             rejection_count = rejection_count + 1,
             resolved_at = unixepoch()
         WHERE id = ?1 AND status = 'pending'",
        (id,),
    ).await?;

    if affected == 0 {
        return Err(Error::SoulProposalNotFound(id));
    }

    Ok(())
}
```

### 9.3 Approval (Atomic)

```rust
/// Approve soul proposal atomically
pub async fn approve(db: &Database, id: i64) -> Result<()> {
    with_transaction(db, |tx| async move {
        // 1. Get and verify proposal
        let proposal = get_pending(tx, id).await?
            .ok_or(Error::SoulProposalNotFound(id))?;

        if proposal.status != ProposalStatus::Pending {
            return Err(Error::ProposalAlreadyResolved(id));
        }

        // 2. Update config
        tx.execute(
            "UPDATE config SET value = ?1, updated_at = unixepoch() WHERE key = ?2",
            (&proposal.proposed_value, &proposal.config_key),
        ).await?;

        // 3. Mark approved
        tx.execute(
            "UPDATE soul_proposals
             SET status = 'approved', resolved_at = unixepoch()
             WHERE id = ?1 AND status = 'pending'",
            (id,),
        ).await?;

        Ok(())
    }).await
}
```

---

## 10. CLI Module

### 10.1 Command Structure

```rust
#[derive(Parser)]
#[command(name = "typhoon", version, about = "Self-growing agent system")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// Initialize database
    Init,

    /// Link to Turso cloud
    Link {
        #[arg(long)]
        url: String,
        #[arg(long)]
        token: String,
    },

    /// Start interactive REPL
    Run,

    /// Config management
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },

    /// Run dream cycle
    Dream {
        /// Run if >25h since last dream
        #[arg(long)]
        catchup: bool,
    },

    /// Start cron daemon
    Cron,

    /// Skill management
    Skill {
        #[command(subcommand)]
        action: SkillAction,
    },

    /// Skill proposal management
    Propose {
        #[command(subcommand)]
        action: ProposeAction,
    },

    /// Soul proposal management
    Soul {
        #[command(subcommand)]
        action: SoulAction,
    },

    /// Execute raw SQL (SELECT only)
    Sql {
        query: String,
    },
}

#[derive(Subcommand)]
pub enum ConfigAction {
    Get { key: String },
    Set { key: String, value: String },
    List,
    Validate,
}

#[derive(Subcommand)]
pub enum SkillAction {
    List,
    Show { name: String },
    Create { name: String },
    Edit { name: String },
    Disable { name: String },
    Delete { name: String },
}

#[derive(Subcommand)]
pub enum ProposeAction {
    List,
    Show { id: i64 },
    Approve { id: i64 },
    Edit { id: i64 },
    Reject { id: i64 },
    Expire,
}

#[derive(Subcommand)]
pub enum SoulAction {
    List,
    Show { id: i64 },
    Approve { id: i64 },
    Reject { id: i64 },
}
```

### 10.2 SQL Safety

```rust
/// Check if query is safe (SELECT only)
pub fn validate_sql_safety(query: &str) -> Result<(), SqlSafetyError> {
    let trimmed = query.trim();

    if trimmed.is_empty() {
        return Err(SqlSafetyError::EmptyQuery);
    }

    let upper = trimmed.to_uppercase();

    if !upper.starts_with("SELECT") {
        return Err(SqlSafetyError::NotSelect);
    }

    // Check for forbidden keywords
    let forbidden = ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "TRUNCATE"];
    for keyword in forbidden {
        // Check for keyword as whole word (not part of column name)
        if upper.split_whitespace().any(|w| w == keyword) {
            return Err(SqlSafetyError::ForbiddenKeyword(keyword.to_string()));
        }
    }

    Ok(())
}
```

### 10.3 Output Formatting

```rust
/// Format table output
pub fn print_table<T: Tabled>(items: &[T]) {
    if items.is_empty() {
        println!("No results.");
        return;
    }

    let table = Table::new(items)
        .with(Style::rounded())
        .to_string();

    println!("{}", table);
}

/// Format skill procedure
pub fn print_skill(skill: &Skill, triggers: &[String]) {
    println!("{}", "=".repeat(60));
    println!("Skill: {}", skill.name.bold());
    println!("{}", "=".repeat(60));

    if let Some(desc) = &skill.description {
        println!("Description: {}", desc);
    }

    println!("Status: {}", format!("{:?}", skill.status).to_lowercase());
    println!("Uses: {} (success: {})", skill.use_count, skill.success_count);
    println!("Triggers: {}", triggers.join(", "));
    println!();
    println!("Procedure:");
    println!("{}", "-".repeat(60));
    println!("{}", skill.procedure);
    println!("{}", "-".repeat(60));
}
```

---

## 11. WASM Abstraction

### 11.1 Database Adapter Trait

```rust
/// Trait for database operations (native vs WASM)
#[async_trait]
pub trait DbAdapter: Send + Sync {
    /// Execute statement (INSERT/UPDATE/DELETE)
    async fn execute(&self, sql: &str, params: &[&str]) -> Result<u64>;

    /// Query rows (SELECT)
    async fn query(&self, sql: &str, params: &[&str]) -> Result<Vec<Vec<String>>>;

    /// Execute multiple statements atomically.
    /// Hosts must run this as BEGIN IMMEDIATE ... COMMIT and rollback on error.
    async fn execute_batch(&self, statements: &[DbStatement]) -> Result<u64>;
}

pub struct DbStatement {
    pub sql: String,
    pub params: Vec<String>,
}
```

### 11.2 Native Adapter

```rust
/// Native adapter using libsql directly
pub struct NativeAdapter {
    conn: libsql::Connection,
}

#[async_trait]
impl DbAdapter for NativeAdapter {
    async fn execute(&self, sql: &str, params: &[&str]) -> Result<u64> {
        let params: Vec<libsql::Value> = params.iter()
            .map(|s| libsql::Value::Text(s.to_string()))
            .collect();
        Ok(self.conn.execute(sql, params).await? as u64)
    }

    async fn query(&self, sql: &str, params: &[&str]) -> Result<Vec<Vec<String>>> {
        let params: Vec<libsql::Value> = params.iter()
            .map(|s| libsql::Value::Text(s.to_string()))
            .collect();

        let rows = self.conn.query(sql, params).await?;
        let mut results = Vec::new();

        while let Some(row) = rows.next().await? {
            let mut values = Vec::new();
            for i in 0..row.column_count() {
                values.push(row.get::<String>(i)?);
            }
            results.push(values);
        }

        Ok(results)
    }

    async fn execute_batch(&self, statements: &[DbStatement]) -> Result<u64> {
        let tx = self.conn.transaction_with_behavior(TransactionBehavior::Immediate).await?;
        let mut affected = 0;

        for statement in statements {
            let params: Vec<libsql::Value> = statement.params.iter()
                .map(|s| libsql::Value::Text(s.clone()))
                .collect();
            affected += tx.execute(&statement.sql, params).await?;
        }

        tx.commit().await?;
        Ok(affected as u64)
    }
}
```

### 11.3 WIT Interface

```wit
package typhoon:core@0.1.0;

/// Log levels
enum log-level {
    debug,
    info,
    warn,
    error,
}

/// Database operation result
variant db-result {
    ok(u64),           // affected rows
    err(string),       // error message
}

/// Query result
variant query-result {
    ok(list<list<string>>),
    err(string),
}

/// Database statement for atomic batches
record db-statement {
    sql: string,
    params: list<string>,
}

/// Dream result
variant dream-result {
    ok(dream-report),
    err(string),
}

/// Dream report summary
record dream-report {
    run-id: s64,
    promoted-count: s32,
    proposals-created: s32,
    signals-cleaned: s32,
}

/// Memory entry
record memory-entry {
    key: string,
    content: string,
    recall-count: s32,
}

/// Skill entry
record skill-entry {
    name: string,
    procedure: string,
}

/// Pending proposals summary
record pending-proposals {
    skill-count: s32,
    soul-count: s32,
}

world typhoon {
    // Host imports
    import log: func(level: log-level, msg: string);
    import time-now: func() -> s64;
    import db-exec: func(sql: string, params: list<string>) -> db-result;
    import db-query: func(sql: string, params: list<string>) -> query-result;
    import db-batch: func(statements: list<db-statement>) -> db-result;

    // Module exports
    export dream-tick: func() -> dream-result;
    export memory-search: func(query: string, limit: s32) -> list<memory-entry>;
    export skill-match: func(input: string) -> option<skill-entry>;
    export pending-proposals: func() -> pending-proposals;
}
```

### 11.4 WASM Adapter

```rust
/// WASM adapter using host-provided imports
#[cfg(target_arch = "wasm32")]
pub struct WasmAdapter;

#[cfg(target_arch = "wasm32")]
#[async_trait]
impl DbAdapter for WasmAdapter {
    async fn execute(&self, sql: &str, params: &[&str]) -> Result<u64> {
        let params: Vec<String> = params.iter().map(|s| s.to_string()).collect();
        match crate::wasm::bindings::db_exec(sql, &params) {
            crate::wasm::bindings::DbResult::Ok(n) => Ok(n),
            crate::wasm::bindings::DbResult::Err(e) => Err(Error::other(e)),
        }
    }

    async fn query(&self, sql: &str, params: &[&str]) -> Result<Vec<Vec<String>>> {
        let params: Vec<String> = params.iter().map(|s| s.to_string()).collect();
        match crate::wasm::bindings::db_query(sql, &params) {
            crate::wasm::bindings::QueryResult::Ok(rows) => Ok(rows),
            crate::wasm::bindings::QueryResult::Err(e) => Err(Error::other(e)),
        }
    }

    async fn execute_batch(&self, statements: &[DbStatement]) -> Result<u64> {
        let statements: Vec<crate::wasm::bindings::DbStatement> = statements.iter()
            .map(|s| crate::wasm::bindings::DbStatement {
                sql: s.sql.clone(),
                params: s.params.clone(),
            })
            .collect();

        match crate::wasm::bindings::db_batch(&statements) {
            crate::wasm::bindings::DbResult::Ok(n) => Ok(n),
            crate::wasm::bindings::DbResult::Err(e) => Err(Error::other(e)),
        }
    }
}
```

WASM hosts must implement `db-batch` atomically. A host that cannot provide rollback semantics must return an error instead of partially applying a batch.

---

## 12. Error Handling

### 12.1 Error Types

```rust
/// SQL safety violation
#[derive(Debug, Error)]
pub enum SqlSafetyError {
    #[error("Query must start with SELECT")]
    NotSelect,
    #[error("Query contains forbidden keyword: {0}")]
    ForbiddenKeyword(String),
    #[error("Empty query")]
    EmptyQuery,
}

/// Main error type
#[derive(Debug, Error)]
pub enum Error {
    #[error("Database error: {0}")]
    Database(#[from] libsql::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Config key not found: {0}")]
    ConfigNotFound(String),

    #[error("Config validation failed: {0}")]
    ConfigValidation(String),

    #[error("Memory not found: {0}")]
    MemoryNotFound(String),

    #[error("Skill already exists: {0}")]
    SkillExists(String),

    #[error("Skill not found: {0}")]
    SkillNotFound(String),

    #[error("Proposal not found: {0}")]
    ProposalNotFound(i64),

    #[error("Proposal already resolved: {0}")]
    ProposalAlreadyResolved(i64),

    #[error("Soul proposal not found: {0}")]
    SoulProposalNotFound(i64),

    #[error("Soul proposal rejection limit reached for: {0}")]
    SoulProposalRejectionLimit(String),

    #[error("SQL safety violation: {0}")]
    SqlSafety(#[from] SqlSafetyError),

    #[error("Database not initialized")]
    NotInitialized,

    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, Error>;
```

### 12.2 Error Handling Strategy

| Layer | Strategy |
|-------|----------|
| Database | Propagate `libsql::Error` via `?` |
| CLI | Convert to user-friendly message, exit code |
| REPL | Show error, continue loop |
| Dream | Log error, continue to next phase if possible |
| WASM | Convert to error variant in result type |

---

## 13. Concurrency Model

### 13.1 Thread Safety

| Component | Threading | Notes |
|-----------|-----------|-------|
| Database | Single-writer via `BEGIN IMMEDIATE` | SQLite WAL mode |
| REPL | Single-threaded | Main loop |
| Cron | Dedicated tokio task | File lock prevents concurrent dreams |
| Signal capture | Synchronous | Inline with REPL |

### 13.2 File Lock for Dream

```rust
/// Acquire exclusive lock for dream cycle
pub fn acquire_dream_lock() -> Result<std::fs::File> {
    let lock_path = Database::default_path().with_extension("lock");
    let file = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(&lock_path)?;

    // Try exclusive lock (non-blocking)
    use std::os::unix::io::AsRawFd;
    let result = unsafe {
        libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB)
    };

    if result != 0 {
        return Err(Error::other("Dream cycle already running"));
    }

    Ok(file)
}
```

---

## 14. Testing Strategy

### 14.1 Unit Tests

| Module | Test Focus |
|--------|------------|
| `config` | Type validation, range checks |
| `memory` | CRUD, recall increment, prune logic |
| `dream/scoring` | Score calculations with known inputs |
| `skill/trigger` | Longest-match-first, use_count tiebreaker |
| `cli/sql` | SQL safety validation |

### 14.2 Integration Tests

```rust
#[tokio::test]
async fn test_dream_cycle_end_to_end() {
    let db = setup_test_db().await;

    // Insert signals
    for i in 0..10 {
        Signal::capture(&db, "test", &format!("snippet {}", i),
            SignalSource::ToolCall, None, None).await.unwrap();
    }

    // Run dream
    let report = Dream::run(&db).await.unwrap();

    // Verify
    assert!(report.deep.signals_cleaned > 0);
}

#[tokio::test]
async fn test_skill_approval_atomic() {
    let db = setup_test_db().await;

    // Create proposal
    let id = create_test_proposal(&db).await;

    // Approve
    let name = Skill::approve_proposal(&db, id).await.unwrap();

    // Verify skill exists
    let skill = Skill::get(&db, &name).await.unwrap();
    assert!(skill.is_some());

    // Verify proposal marked
    let proposal = SkillProposal::get(&db, id).await.unwrap();
    assert_eq!(proposal.status, ProposalStatus::Approved);
    assert_eq!(proposal.created_skill, Some(name.clone()));

    // Double-approve is idempotent: returns existing created skill
    let retry_name = Skill::approve_proposal(&db, id).await.unwrap();
    assert_eq!(retry_name, name);
}

#[tokio::test]
async fn test_soul_rejection_limit() {
    let db = setup_test_db().await;

    // Create and reject 3 proposals for same key
    for _ in 0..3 {
        let id = Soul::create_proposal(&db, "agent.tone", "terse", "test").await.unwrap();
        Soul::reject(&db, id).await.unwrap();
    }

    // Fourth proposal should be blocked
    assert!(!Soul::can_propose(&db, "agent.tone").await.unwrap());
}
```

### 14.3 Test Fixtures

```rust
/// Setup in-memory test database
async fn setup_test_db() -> Database {
    let db = Database::connect(DbConfig::LocalFile {
        path: PathBuf::from(":memory:")
    }).await.unwrap();

    MigrationRunner::new(&db, MIGRATIONS).run().await.unwrap();
    seed_defaults(&db).await.unwrap();

    db
}
```

---

## 15. Database Schema (Complete)

```sql
-- migrations/001_initial.sql

-- Config
CREATE TABLE config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('string','int','float','bool','cron')),
    description TEXT,
    updated_at INT DEFAULT (unixepoch())
);

-- Memories
CREATE TABLE memories (
    key TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    recall_count INT NOT NULL DEFAULT 0,
    unique_queries INT NOT NULL DEFAULT 0,
    last_recalled INT DEFAULT (unixepoch()),
    created_at INT DEFAULT (unixepoch()),
    concept_tags TEXT,
    query_hashes TEXT
);
CREATE INDEX idx_memories_score ON memories(recall_count, last_recalled);

-- Dream signals
CREATE TABLE dream_signals (
    id INTEGER PRIMARY KEY,
    key TEXT NOT NULL,
    snippet TEXT NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('tool_call','user_correction','session_end')),
    session_id INT,
    sequence_num INT,
    captured_at INT DEFAULT (unixepoch())
);
CREATE INDEX idx_signals_session ON dream_signals(session_id, sequence_num);
CREATE INDEX idx_signals_captured ON dream_signals(captured_at);

-- Skills
CREATE TABLE skills (
    name TEXT PRIMARY KEY,
    description TEXT,
    procedure TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'approved' CHECK(status IN ('draft','approved','disabled')),
    created_from TEXT,
    created_at INT DEFAULT (unixepoch()),
    use_count INT NOT NULL DEFAULT 0,
    success_count INT NOT NULL DEFAULT 0
);

-- Skill triggers
CREATE TABLE skill_triggers (
    skill_name TEXT NOT NULL,
    phrase TEXT NOT NULL,
    PRIMARY KEY(skill_name, phrase),
    FOREIGN KEY(skill_name) REFERENCES skills(name) ON DELETE CASCADE
);

-- Skill proposals
CREATE TABLE skill_proposals (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    procedure TEXT NOT NULL,
    triggers TEXT,
    evidence TEXT,
    value_score REAL,
    frequency INT,
    success_rate REAL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','expired')),
    created_skill TEXT,
    proposed_at INT DEFAULT (unixepoch()),
    resolved_at INT
);
CREATE UNIQUE INDEX idx_proposals_created_skill ON skill_proposals(created_skill) WHERE created_skill IS NOT NULL;

-- Soul proposals
CREATE TABLE soul_proposals (
    id INTEGER PRIMARY KEY,
    config_key TEXT NOT NULL,
    proposed_value TEXT NOT NULL,
    current_value TEXT,
    evidence TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
    rejection_count INT NOT NULL DEFAULT 0,
    proposed_at INT DEFAULT (unixepoch()),
    resolved_at INT
);
CREATE INDEX idx_soul_proposals_key ON soul_proposals(config_key, status);

-- Dream runs
CREATE TABLE dream_runs (
    id INTEGER PRIMARY KEY,
    started_at INT DEFAULT (unixepoch()),
    ended_at INT,
    phase TEXT CHECK(phase IN ('light','rem','deep')),
    promoted_count INT NOT NULL DEFAULT 0,
    proposals_created INT NOT NULL DEFAULT 0,
    report TEXT
);

-- Session analytics
CREATE TABLE session_analytics (
    id INTEGER PRIMARY KEY,
    started_at INT NOT NULL DEFAULT (unixepoch()),
    ended_at INT,
    tool_calls INT NOT NULL DEFAULT 0,
    tool_sequence TEXT,
    user_corrections INT NOT NULL DEFAULT 0,
    skills_used TEXT,
    success INT NOT NULL DEFAULT 1,
    summary TEXT
);

-- Schema migrations
CREATE TABLE schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at INT DEFAULT (unixepoch())
);

-- Insert initial config
INSERT INTO config (key, value, type, description) VALUES
    ('agent.name', 'Typhoon', 'string', 'Agent display name'),
    ('agent.tone', 'concise', 'string', 'Response tone'),
    ('dream.cron', '0 3 * * *', 'cron', 'Dream schedule'),
    ('dream.min_score', '0.8', 'float', 'Minimum memory promotion score'),
    ('dream.min_recall', '3', 'int', 'Minimum recall count for promotion'),
    ('dream.min_unique_queries', '3', 'int', 'Minimum unique queries for promotion'),
    ('dream.recency_half_life_days', '14', 'int', 'Recency decay half-life'),
    ('dream.max_age_days', '30', 'int', 'Maximum memory age before pruning');

-- Mark migration applied
INSERT INTO schema_migrations (version) VALUES ('001');
```

---

## 16. File Structure (Final)

```
typhoon/
  Cargo.toml
  DESIGN.md
  PROPOSAL.md
  PLAN.md

  migrations/
    001_initial.sql

  wit/
    typhoon.wit

  src/
    lib.rs                  # Re-exports for library use
    main.rs                 # CLI entrypoint
    error.rs                # Error types
    types.rs                # Domain structs and enums
    config.rs               # Config operations

    db/
      mod.rs                # Database struct
      connection.rs         # DbConfig enum
      migration.rs          # MigrationRunner
      seed.rs               # Default config inserts
      query.rs              # FromRow trait, CSV helpers

    memory/
      mod.rs                # Memory API
      store.rs              # store(), get(), delete()
      recall.rs             # recall() with tracking
      search.rs             # search() with ranking
      decay.rs              # recency_score(), prune()

    signal/
      mod.rs                # Signal API
      capture.rs            # capture()
      session.rs            # Session tracking

    dream/
      mod.rs                # Dream orchestrator
      light.rs              # Dedup, grouping
      rem.rs                # Pattern detection, scoring
      deep.rs               # Promotion, proposals
      scoring.rs            # Score algorithms

    skill/
      mod.rs                # Skill API
      crud.rs               # CRUD operations
      trigger.rs            # Trigger matching
      proposal.rs           # Proposal approval

    soul/
      mod.rs                # Soul API
      detection.rs          # Personality pattern detection
      proposal.rs           # Soul proposal CRUD
      rejection.rs          # Rejection tracking

    analytics/
      mod.rs                # Analytics API
      session.rs            # Session CRUD
      pattern.rs            # Tool sequence patterns

    cli/
      mod.rs                # Command definitions
      init.rs               # typhoon init
      config.rs             # typhoon config
      run.rs                # typhoon run (REPL)
      dream.rs              # typhoon dream
      cron.rs               # typhoon cron
      skill.rs              # typhoon skill
      propose.rs            # typhoon propose
      soul.rs               # typhoon soul
      sql.rs                # typhoon sql
      link.rs               # typhoon link
      output.rs             # Table formatting

    wasm/
      mod.rs                # WASM module
      adapter.rs            # DbAdapter implementations

  tests/
    fixtures/
      signals.sql
      sessions.sql
      proposals.sql
    integration/
      dream_test.rs
      skill_test.rs
      soul_test.rs
```

---

## Appendix: Default Config Values

| Key | Value | Type | Description |
|-----|-------|------|-------------|
| `agent.name` | `Typhoon` | string | Display name |
| `agent.tone` | `concise` | string | Response style |
| `dream.cron` | `0 3 * * *` | cron | Dream schedule (3am daily) |
| `dream.min_score` | `0.8` | float | Memory promotion threshold |
| `dream.min_recall` | `3` | int | Min recalls for promotion |
| `dream.min_unique_queries` | `3` | int | Min unique queries |
| `dream.recency_half_life_days` | `14` | int | Decay half-life |
| `dream.max_age_days` | `30` | int | Max memory age |
