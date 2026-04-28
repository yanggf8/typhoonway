# DLD Notes — WIP

Parked planning for the v0.1 detailed design document. Not the DLD itself — the agreed direction, structure outline, per-chapter template, and open decisions to resume from. Written after HLD §2.1 stabilised on the matrix layer view (commits `c890c03` / `399d606`).

---

## Framing

DLD is the **implementation contract**, not "more HLD detail." After reading a DLD section, an implementer should know:

- what files / modules to create
- what function surfaces exist
- what SQL exists
- what errors are returned
- what tests prove it
- what runs, in what order, with what side effects

HLD answers "what is the system / what are the responsibilities / what are the boundaries." DLD answers "exactly what must be built."

## Structural decisions (agreed)

1. **Subsystem-first division.** HLD §2.4 already declares S1–S5 as DLD chapter boundaries. DLD inherits that partitioning.

2. **Single file to start.** `DLD.md` with H2 per subsystem, same shape as `HLD.html`. Split into per-subsystem files only when chapters cross ~800 lines or parallel authoring forces it. Premature multi-file layout encourages isolated chapters that miss cross-cutting issues, and cross-link rot starts immediately.

3. **S5 organised by component groups.**
   HLD keeps S5 as one top-level subsystem but names four review-sized component groups for DLD organisation:
   - S5A — Data-access APIs (Tool registry, Memory store, Signal store, Proposal queue, Config, Identity &amp; persona resolution, Persona attributes)
   - S5B — Storage adapters (TursoDB driver, filesystem/artifact storage mechanics)
   - S5C — Service adapters (Channel service adapters, LLM service adapters)
   - S5D — Transaction and lock primitives (`BEGIN IMMEDIATE` helper, filesystem locks, registry-mutation protocol helpers)

   Note: Identity &amp; persona resolution and Persona attributes read (and Persona attributes also write) persona-core's `user` and `persona` tables — the rest own Typhoon's own tables. The shared schema constraint shapes the Data Model chapter (below) and S5A.

4. **Data Model is a real chapter, not optional.** Most stable, most cross-referenced artifact. Centralising the schema means one place for schema review, one place for migration discipline, and zero risk of S2 and S4 disagreeing on what `cli_proposals.status` means. Write it alongside S5 (or first). The chapter must distinguish Typhoon's own tables (signal, memory, tool registry, proposal queues, channel bindings, system config, daemon state) from persona-core's tables (`user`, `persona`, `audit_log`) that Typhoon reads-and-sometimes-writes. Migrations are versioned per owner: `('persona-core', N)` and `('typhoon', M)`; Typhoon's migrations apply on top of persona-core's and never edit persona-core's tables outside of dream-driven persona-attribute writes.

5. **Command contracts: split conventions from grammar.**
   - **CLI conventions** (exit-code ranges, JSON envelope, `--persona` semantics, `--json` default, error format) live in `DLD.md`'s conventions chapter.
   - **Per-command grammar** lives inside the owning subsystem. `tool propose approve` next to S4's approval transaction; `signal record` next to S2's recorder; `persona approve` next to S4's persona-attribute mutation.

6. **State machines stay in S4.** HLD §3 is authoritative for legal transitions. S4's DLD chapter expands on which functions perform each transition, which SQL transaction wraps each step, which errors guard illegal transitions, and which tests prove each transition. Don't lift §3 into a standalone DLD chapter.

7. **Verification per chapter.** Cross-cutting test strategy (fixture conventions, fake-clock policy, integration-test environment) lives in `DLD.md`. Per-feature tests live with the feature they verify. A separate Verification document becomes a graveyard of stale TODOs.

8. **S5A and S5D first; S5B and S5C can lag.** S1–S4 don't reference all of S5 equally. S5A (data-access APIs) is consumed by every subsystem; S5D (transaction/lock primitives) is composed by every subsystem that mutates state. Together they are the sign-off blocker. S5B (storage adapters) is internal to S5A — S1–S4 don't see it directly, so it may follow alongside S5A. S5C (service adapters) is consumed only by S2 (channels) and S3 (LLM calls), so it may be drafted in parallel with S2.

9. **Forge contract gets its own subheader inside S4.** v0.1 forge is operator-driven outside Typhoon, but the handoff (`tool propose submit` accepts requirements + source + tests + path-lint pass) is a contract Typhoon enforces. Don't bury it inside the lifecycle subsection.

10. **Critical sequences slot per chapter.** HLD's dense single-paragraph prose for things like the registry mutation protocol and the dream three-phase pipeline becomes step-numbered procedures with side effects per step at DLD level. Sequence diagrams for multi-actor cases (e.g., forge submission).

## DLD top-level structure

```
DLD.md
  - document map
  - global conventions
  - workspace / crate dependency rules
  - CLI conventions (exit codes, JSON envelope, --user, --json, error format)
  - DLD/HLD drift discipline
  - cross-cutting test strategy
  - how to read subsystem chapters

  ## Data Model
    - persona-core's tables vs. Typhoon's tables; coexistence rules
    - tables, indexes, constraints (Typhoon-owned)
    - migration rules (versioned per owner; additive-only)
    - row ownership / scoping (persona_slug-tagged, user_id-tagged, vs system-scoped)
    - schema-level invariants and CHECK constraints
    - persona row attribute-column write paths (persona-core direct edits vs. Typhoon's approved persona proposals)

  ## S5A — Data-access APIs
  ## S5B — Storage adapters
  ## S5C — Service adapters
  ## S5D — Transaction and lock primitives
  ## S1 — Platform
  ## S2 — Channels & dispatch
  ## S3 — Self-growth (dream)
  ## S4 — Registry management
```

Section order is review order, not authoring order — Data Model and S5A first; S1–S4 may be drafted in parallel once S5A's API surface stabilises. S5 chapters are listed alphabetically so S5A (the surface S1–S4 consume) appears first; DLD authors may use a dependency-first internal order when writing chapter content (S5D primitives → S5B storage adapters → S5A APIs → S5C service adapters).

## Per-subsystem chapter template

Every subsystem chapter uses the same fixed template:

1. **Purpose** — one paragraph; what this subsystem owns and does not own.
2. **Owned modules** — list referencing HLD §2.2 module rows.
3. **Inputs and outputs** — what comes in, what goes out, scoped per module.
4. **Public APIs / commands** — function surfaces (data-access libraries) or CLI grammar (workflow modules), exact shape.
5. **Data touched** — which rows / columns / files this subsystem reads and writes; cross-references the Data Model chapter.
6. **State transitions** — for subsystems that own state machines (S4 in particular), reference HLD §3 as authoritative; expand on functions, transactions, errors, tests.
7. **Transactions and locks** — exact `BEGIN IMMEDIATE` boundaries, file-lock acquisition and release, registry-mutation-protocol invocations.
8. **Critical sequences** — numbered procedures for non-trivial dynamic flows, with side effects called out per step. Sequence diagrams for multi-actor flows.
9. **Error cases and exit codes** — every error variant, when it fires, what the operator sees.
10. **Observability** — what counters increment, what spans wrap, what shows up in `typhoon health`, what lands in `dream_runs`.
11. **Verification** — unit / integration / crash / concurrency tests proving the subsystem's invariants.

## Discipline rules to land in DLD.md conventions

These are decisions that should be stated up front, not rediscovered per chapter:

- **DLD/HLD drift.** Any DLD deviation from HLD requires an HLD update in the same commit. Avoids "DLD says X, HLD says Y" reviewer traps.
- **Workspace boundary = compile-time where practical.** Application crates may not bypass data-access APIs to write stores directly; service adapters may not own Typhoon lifecycle policy. (HLD §2.5 already flags this; restate as a binding rule.)
- **No `anyhow` in library crates.** Already in HLD §2.5; restate.
- **No `tokio::main` in library crates.** Async-runtime choice is binary-level. (Already in HLD §2.5.)
- **Per-row `persona_slug` enforcement.** Every data-access API for per-persona state (signals, memory, persona proposals) takes `persona_slug` and filters every read and write — verified by test, not by convention. Cross-persona reads through these APIs are forbidden; dream is the only consumer that opts into a cross-persona scan, through a separate API.
- **persona-core schema is read-mostly.** Typhoon's data-access libraries treat persona-core's `user` and `persona` tables as read-mostly. The only Typhoon-driven write into persona-core's schema is a persona-attribute column update through the Persona attributes library, executed inside an approved persona-proposal transaction. No Typhoon code may write `user`, `audit_log`, or `invite`.
- **Review order.** S5A (data-access APIs) and S5D (transaction/lock primitives) are the sign-off blocker for S1–S4. S5B (storage adapters) may follow alongside S5A; S5C (service adapters) may be drafted in parallel with S2. After S5A and S5D are stable, S1–S4 are independent.

## Open decisions for DLD-time

These don't need to be settled before drafting starts but should be tracked:

1. **Async runtime per process.** v0.1 daemons (gateway, scheduler) need full Tokio; one-shot CLIs may run on `current_thread` Tokio or a `block_on` bridge. DLD picks per-process, given the libSQL client's async surface.
2. **Sandbox mechanism.** Forged tool execution sandbox specifics (bwrap config, seccomp filters, resource limits, AppArmor/SELinux interaction). HLD does not commit; PLAN §8 lists this as deferred.
3. **Forged tool execution permissions.** v0.1 default: forged CLI runs with the same privileges as the invoking Typhoon process — typically the channel gateway daemon when invoked from a channel turn, or the admin's shell when invoked manually. DLD confirms or revises.
4. **Success-tagging edge cases.** What counts as a "correction"? PLAN §8 R8 flagged abandoned tasks as a false-positive risk. DLD specifies the rule.
5. **Retrieval budget knobs.** Exact `top_k`, similarity threshold, per-turn token budget. PLAN §8 lists as placeholders to tune in first two weeks.
6. **Replacement similarity thresholds.** Dream's "is this proposal a replacement for an existing tool?" decision; threshold values.
7. **Initial threshold values.** `dream.min_frequency`, `dream.min_score`, `dream.min_recall`, `dream.min_unique_queries`, `dream.recency_half_life_days`. Placeholders in HLD; tune in first two weeks of operation.
8. **Sequence diagram tooling.** Mermaid `sequenceDiagram` works in HTML render; readable as plaintext. Use it or write step-numbered prose? Likely both, depending on flow complexity.

## Non-goals for DLD

- Re-stating HLD prose. Reference HLD §X.Y rather than copying.
- Exhaustive function-by-function code listings. DLD names function surfaces; the source code is the implementation.
- Architecture-level alternatives or rejected options. Those belong in HLD's history (PROPOSAL.md §No-Go) or commit messages, not DLD.

## Next action

Land HLD review cycle (in progress). Once HLD is approved, draft `DLD.md` starting with conventions chapter and Data Model, then S5A and S5D in parallel (these are the blockers for S1–S4). S5B follows alongside S5A; S5C may be drafted in parallel with S2. Subsystem chapters S1–S4 follow once S5A's API surface is stable.
