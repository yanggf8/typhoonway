# Typhoon Way: A Self-Growing Agent That Forges CLIs

> Revised 2026-04-24. Output is CLIs, not skills. The self-growth loop is informed by Hermes Agent; the artifact format is where we differ.

---

## 1. The Problem

Today's agents accumulate skills. Each skill is a text document — a name, a description, a procedure — that the agent reads at session start and invokes when a trigger phrase matches.

Skills have three costs the user actually feels:

- **Token tax.** 100+ skills × descriptions in the system prompt × every session.
- **Agent lock-in.** A skill installed in Claude Code doesn't help Cursor, Codex, a bash pipeline, or a human.
- **Maintenance drag.** Every new agent, every new machine, redo the install.

Maintaining skills across multiple agents is cumbersome, and skills don't port.

---

## 2. The Insight

**The unit of reuse should be a CLI, not a skill doc.**

CLIs already port. Anything that can exec a subprocess can use them — agents, humans, shell scripts, cron, CI, other agents. A skill only helps the agent that owns it.

Typhoon grows CLIs from observed use. When the user and agent do the same three-step thing eight times, Typhoon proposes a binary that does it in one call. The user reviews the source, approves, and the CLI lands on `PATH`. Next time, the agent (or the user) just calls it.

No skill registry. No system-prompt catalog. No agent-side install.

---

## 3. How It Works

**Dream is the analysis engine.** The loop has five roles: the runtime **does the work**, the recorder **persists signals**, dream **analyzes recorded signals and drafts a proposal brief**, the **admin forges** that brief into a high-quality requirement plus source out-of-band using an agentic coding workflow (Codex, Claude Code CLI, Cursor, or similar), and the **admin ratifies** by reviewing both.

**Typhoon doesn't verify correctness — the forge does.** A CLI forged from observed usage can't be mechanically proven reusable; signals are evidence of what happened, not a behavioral contract. Typhoon's role is to extract a *proposal brief* (problem, repeated workflow, evidence, likely interface, rough tier) and catalog the forge's delivery. The forge is responsible for hardening that brief into an implementable requirement, satisfying it with source, and producing a correctness argument (tests, examples, whatever fits). The operator accepts or rejects.

**Typhoon is language-neutral.** It doesn't write CLI source code — it writes proposal briefs. The operator (via the forge) picks whatever language fits (bash, Python, Rust, Deno, Go…) subject only to "runs on the Linux/Mac host that hosts Typhoon." Typhoon catalogs, installs, monitors health, and manages lifecycle — it never synthesizes.

**Forge is manual in v0.1.** "Forge" means the operator-driven coding-agent workflow used to turn a proposal brief into a CLI delivery. It is not a Typhoon subsystem and not one fixed tool; it may be Codex, Claude Code CLI, Cursor, or any comparable agentic coding environment. Forge quality depends on the chosen agent, model, repo context, prompt, available tools, and tests. Typhoon does not invoke the forge automatically. The operator reads the proposal brief, does the forge work externally, and submits the hardened requirement, `tool.md`, and resulting source back via `typhoon tool propose submit`. Automating the forge invocation is deferred until the full manual loop is validated.

**Recorder is the only signal writer.** Channel gateway edge loops, schedulers, and external-agent sidecars never write signal rows directly. Gateway worker loops and other use-plane entry points route use events through the runtime, and the runtime asks the recorder to persist normalized signal rows. Dream reads those rows later; it does not collect online activity itself.

```
 User works with Typhoon (Telegram primary; external-agent CLI for ops)
                       │
                       ▼
  Runtime observes tool calls, corrections, outcomes
                       │
                       ▼
           Recorder writes dream_signals (SQL rows)
                       │
                       ▼   cron readiness check or `typhoon dream --force`
           LIGHT phase  — dedupe, sort signals
           REM   phase  — LLM clusters *successful* signal chains,
                          detects repeated workflows, checks existing CLIs
           DEEP  phase  — LLM drafts a proposal brief (problem,
                          repeated workflow, likely interface, rough
                          tier claim, ROI, evidence) and writes
                          cli_proposals with status=awaiting_forge
                          (or memories, or persona_proposals)
                       │
                       ▼
    Operator forges the brief externally (Codex, Claude Code CLI,
    Cursor, or similar). The forge sharpens the requirement, designs tests /
    examples / checks, writes source, iterates, and submits:
    `typhoon tool propose submit <id> --requirements <file> \
      --tool-doc <tool.md> --source <file> [--tests <file>]`
    Typhoon attaches hardened requirement + tool.md + source +
    forge's correctness argument, records declared external dependencies,
    runs the hardcoded-path lint, and moves status → awaiting_user.
                       │
                       ▼
    Operator reviews the delivery (brief vs. hardened requirement vs.
    tool.md vs. source vs. forge's correctness argument) and approves
    or sends back.
                       │
                       ▼
    Artifact lands in ~/.typhoon/bin/<name>, chmod +x, added to PATH.
    Seed memory written: "You built <name>. It does X. Use when Y."
                       │
                       ▼
    Next session: core surfaces the tool through the registry-backed tool manifest; memory may add context.
```

Dream can run on a cheap batch model because it only writes proposal briefs, and it should not run a full batch merely because the clock ticked. Cron is a wake-up mechanism: before light/REM/deep work starts, dream measures accumulated signal mass since the last full run, using normalized signal-token count plus successful signal-chain count. If neither signal tokens nor successful chains clear the configured batch thresholds, dream prunes stale rows, records a skipped check, and avoids LLM calls. The operator handles forge work out-of-band with whichever coding agent gives the best requirement and code quality for that proposal. Online interaction touches the frontier LLM and the relevant memories — never a skill catalog.

Dream is a readiness-gated single-writer batch with a lease row in `dream_runs` (heartbeat-bearing; phase/status ∈ {light, rem, deep, prune, skipped}). The operator can query a running dream's phase, elapsed time, ETA, and pending signal mass via `typhoon dream status`, and request a cooperative shutdown via `typhoon dream cancel` — the dream observes the request at each phase boundary and before/after each deep-phase LLM call, persists work it has already paid for when a completed deep chunk returns, and exits with status `cancelled`. Total runtime is bounded by `dream.max_runtime_minutes`; each deep-phase LLM call gets a deadline no later than the remaining dream runtime, and a timeout marks the run `timed_out` instead of letting the heartbeat hide a hung call. A second `typhoon dream` invocation while a live run exists prints status rather than failing with a lock error, so the operator can always tell what's happening. Manual `typhoon dream --force` bypasses the readiness gate for explicit operator runs and tests.

### Users and personas

Typhoon does not invent its own identity model. It shares a TursoDB cloud database with **persona-core**, the existing schema authority for users and personas. persona-core owns migrations 001–006 (`user`, `invite`, `persona`, `persona_secret`, `persona_history`, `content_column`, `installment`, `stream`, `issue`, `audit_log`); Typhoon owns its own migrations on top (signal store, memory store, tool registry, proposal queues, daemon state). One database, two schema-versioning rows: `('persona-core', N)` and `('typhoon', M)`.

Two concepts, deliberately separated:

- **User** — a human, identified by OAuth (Google or GitHub) at the persona-core layer. One row in `user`, with `role` ∈ `{admin, author}` and an `active` flag. The user is the auth boundary.
- **Persona** — a writer/agent identity *owned by a user*. One row in `persona`, keyed by `slug`, referencing `user_id`. The persona row holds the bundle that makes the agent act *as* this persona — `expression`, `mental_models`, `heuristics`, `antipatterns`, `limits`. **One user owns many personas.** A user might have a "deploy-coding" persona and a "weekly-AI-news writer" persona; each is a distinct agent identity with its own behavioral configuration.

The persona row *is* the soul. The "soul proposals" concept from earlier drafts maps directly to dream-driven changes to a persona's attribute bundle (heuristics, antipatterns, etc.); they are renamed **persona proposals** in this design.

What's per-X vs. shared:

- **Shared across the whole runtime.** The tool registry. When one persona's signals motivate a tool, every persona benefits once an admin approves. Tools are the artifact; sharing is the point.
- **Per-persona.** Signals, memory, persona-attribute proposals. Tagged by `persona_slug`; cross-persona reads are a privacy bug. Dream is the deliberate exception — it scans across all personas so cross-persona pattern overlap can become evidence for a shared tool.
- **Per-user.** OAuth identity, role, audit trail. These live in persona-core's tables and are not duplicated.

Identity flow per channel turn. Typhoon does not authenticate users itself — persona-core's OAuth layer authenticates the human; the bot token authenticates the bot. The runtime resolves a channel message to *(user, persona)* in two steps:

1. **Channel binding → user.** `(channel, bot_account_id, peer_id) → user_id`, via a verified binding row.
2. **Bot account → active persona.** v0.1 uses the simplest model: **one Telegram bot account corresponds to one persona**. The bot's persona is configured at deploy time. Future versions may add per-thread or command-driven persona switching, but v0.1 ships with per-bot persona because it's the cleanest mapping (the bot's credentials already authenticate it as that persona) and it generalises to future channels (Slack workspace = persona, Discord server = persona).

If the binding lookup misses, the channel message is not accepted as a Typhoon turn. v0.1 marks the inbound queue row `dead_letter` with reason `binding_missing`; it does not auto-bind the peer, does not default to an admin identity, and does not emit an onboarding reply.

The Telegram path is queued inside one gateway daemon. The gateway edge loop talks to Telegram through the adapter and writes normalized updates into a durable channel inbox; the Typhoon Way worker loop claims those rows, runs the agent loop, and writes replies to a channel outbox that the edge loop delivers. This is intentionally a Turso-backed queue, not an in-memory Rust channel, because the handoff must survive daemon restarts, expose retry/dead-letter state, and keep external-system I/O decoupled from the Typhoon agent loop.

The role gate is on the *user*, not the persona. Only a user with `role='admin'` may ratify proposals or mutate the tool registry; a `role='author'` user contributes signals, consumes memory, and runs installed tools through whichever of their personas is active. The deploying party is seeded as the first admin at `typhoon init`. v0.1 has exactly one admin and zero or more authors.

v0.1 is single-channel (Telegram, with one bot per persona) plus the admin's external-agent channel (Claude Code, Cursor, Codex). The external-agent channel defaults to the admin's primary persona; an explicit `--persona` flag is added when a second persona uses that channel.

### What dream produces

Three outputs, each with its own landing path:

| Output | Lands in | User approval? |
|---|---|---|
| Memories | `memories` table (agent context only) | No — low stakes, reversible |
| CLI proposal briefs | `cli_proposals` → forge → `~/.typhoon/bin/` | Yes — every time in v0.1 |
| Persona proposals | `persona_proposals` → `persona` row attribute bundle | Yes — every time |

Memory writes happen inside the dream run — worst case is noise in next session's context. Executable state (binaries, config) always routes through a proposal queue.

### Memory, not a skill registry

The active tool manifest is how the channel LLM decides which approved CLI to call. Each installed tool has a reviewed `tool.md` descriptor (see `TOOL.md`) that states when to use it, when not to use it, its command shape, inputs, outputs, side effects, examples, failure modes, and dependencies. Core loads approved registry rows and their `tool.md` descriptors through the Tool registry, then builds the bounded LLM tool manifest for the turn. The LLM chooses tool calls from that manifest; core only mediates execution and records the result.

Memory remains useful context, but it is not the tool interface. When the user says "deploy the preview," memory retrieval may return *"Last successful preview deploy used `deploy-preview` after build passed."* The actual callable surface comes from that tool's `tool.md`, not from an inferred memory snippet.

Memory structure borrows the useful parts of mem0 v3 rather than depending on mem0 as a service: ADD-only memory writes, entity-aware retrieval, multi-signal ranking (semantic + keyword + entity), and strict token-budgeted retrieval. Extraction happens inside the dream cycle instead of per-turn — cheaper at scale and the batching is what makes dream phases worthwhile in the first place. **Retrieval is bounded** (Top-K + similarity threshold + token budget) so memory never becomes a skill catalog in disguise.

A signal chain is tagged **successful** when the final tool call exits 0 and the next user turn carries no correction signal. REM clusters only successful chains — noisy dead-ends and hallucinated paths don't become CLI proposals.

### CLI classification: pure / read / mutate

Tiers guide **requirement quality and review strictness**, not approval flow. Every CLI needs operator approval in v0.1.

| Tier | Effect | Examples | Review intensity |
|---|---|---|---|
| **Pure** | stdin → stdout, no side effects | `json-extract`, `regex-match`, `date-parse` | Light — skim source, trust forge |
| **Read** | Reads filesystem/network, writes nothing | `git-log-summary`, `deploy-status` | Moderate — check what's read |
| **Mutate** | Writes disk / network / subprocess | `deploy-preview`, `commit-push`, `restart-service` | Strict — read every line |

Dream emits a rough tier claim based on which signals the pattern touched. The forge confirms or revises that tier in the hardened requirement and uses it to choose the test strategy and implementation constraints. There is no sandbox in v0.1. Tier honesty is reviewed by the operator from the brief, hardened requirement, source, declared dependencies, and forge's correctness argument.

**All tiers** also fail a deliberately strict **hardcoded-path scan** — absolute user paths like `/home/…`, `/Users/…`, `C:\…`, `/tmp/…` are rejected because they defeat portability or hide machine assumptions. Source must use `$HOME`, `$PWD`, CLI arguments, or runtime-created temp paths such as `mktemp`. Simple regex, any language. False positives are acceptable in v0.1; the forge can revise the source and resubmit.

(Auto-install of pure-tier CLIs is a v0.2 question. Validate the manual loop first.)

### Replacement, not duplication

Dream checks existing CLIs before drafting a new brief — by description embedding similarity and by signal-sequence overlap with the origin signals of existing CLIs. Three outcomes:

- **Same semantics** → proposal is a *replacement* (`replaces: <name>`), carries the evidence of what changed in usage; the forge later produces the source diff.
- **Name collision** → always treated as a replacement, always reviewed.
- **Near-duplicate but distinct** → drafted as sibling CLI with a "similar to: `<name>`" note; user decides whether to merge or keep separate.

**Replacements never auto-approve, even pure tier.** A pure-function rewrite still changes behavior downstream callers depend on — silently swapping it would break the user's habits.

On approval of a replacement, the old binary moves to `~/.typhoon/bin/.history/<name>.<timestamp>`. `typhoon tool rollback <name>` reverts. The whole swap is atomic — backup, replace, registry update, reviewed `tool.md` update, and context seed-memory update all succeed together or none do.

### Human in the loop

Every proposal reaches the operator as a pair: the **brief** (dream's output) and the **delivery** (forge's output).

The brief carries:

- Problem description (what repeated pain the CLI should remove)
- Repeated workflow summary (what the user and agent have been doing manually)
- Likely interface sketch (candidate args, flags, stdin/stdout, exit codes)
- Rough acceptance hints (examples of success/failure from observed use, not a complete test plan)
- Evidence (signal clusters that motivated it — context, not a test suite)
- Rough tier claim + ROI score (frequency × success × sequence length × time span)
- `replaces:` pointer, if it's a replacement

The delivery carries:

- Hardened requirement (final interface contract, acceptance criteria, out-of-scope items, edge cases, and test plan)
- `tool.md` (LLM-facing descriptor: when to use, command shape, inputs/outputs, side effects, examples, failure modes, dependencies)
- Source code
- The forge's correctness argument (its own tests, example invocations, whatever it considered sufficient)
- External dependencies used
- Language + runtime

Approval means the operator is satisfied with the delivery against the brief, the hardened requirement, and the LLM-facing `tool.md`. Typhoon runs the hardcoded-path lint and records metadata, but it does not judge correctness — that's the forge's job and the operator's call.

Three rejections on the same pattern (or the same replacement) stops dream from re-proposing it — same 3-strike rule as persona proposals.

---

## 4. CLI Lifecycle and Management

CLIs are the core artifact. How they come into being, get used, evolve, and retire is first-class — not an afterthought.

### States

A CLI has one of these states at any time:

| State | Meaning |
|---|---|
| `proposed` | Draft in `cli_proposals`, awaiting forge (`awaiting_forge`) or operator review (`awaiting_user`) |
| `active` | Installed in `~/.typhoon/bin/`, on `PATH`, discoverable via memory |
| `disabled` | Registry row kept, removed from `PATH`; re-enable any time |
| `superseded` | Replaced by a newer CLI; source preserved in `.history/`, lineage recorded |
| `deleted` | Registry row removed; binary archived to `.history/` unless hard-purged |

Proposals have their own state machine: `awaiting_forge → awaiting_user → approved | rejected`. A brief lands first (no code); the operator forges externally and submits the hardened requirement, `tool.md`, and source via `typhoon tool propose submit`, which attaches requirement + `tool.md` + source + forge's correctness argument, records declared dependencies and runtime metadata, runs the hardcoded-path lint, and flips to awaiting_user. The operator then reviews the delivery against the brief and approves or rejects.

### Lifecycle

```
     signals accumulate
           │
           ▼
    dream clusters → proposal brief
           │
           ▼
    awaiting_forge
           │
           │  operator forges externally, submits requirement + source
           ▼
    awaiting_user  (source attached + path lint passed)
           │
           ├── approve ──► active
           │
           └── reject  ──► rejected  (×3 on same pattern → dream stops proposing)

    active
     │
     ├── disable ──► disabled ──── enable ──► active
     │                 │
     │                 └── delete
     │
     └── dream proposes replacement ──► superseded (.history/)
```

### What we track per CLI

Each registry row holds enough to answer any lifecycle question:

- **Identity**: name, kind (pure/read/mutate), status, description
- **Body**: hardened requirement, source, language (bash/python/rust/deno/…), runtime (interpreter binary or "compiled"), tests, external dependencies
- **Origin**: which proposal and signals produced it; which forge synthesized it; whether user- or auto-approved
- **Health**: usage count, success count, last used, recent errors
- **Lineage**: parent, version, what replaced it
- **Timestamps**: created, updated

### User commands

```bash
typhoon tool list                          # active CLIs
typhoon tool list --kind pure              # filter by tier
typhoon tool list --unused --since 30d     # stale candidates
typhoon tool list --all                    # include disabled + superseded

typhoon tool show <name>                   # source, stats, lineage, origin signals
typhoon tool diff <name>                   # compare with previous version
typhoon tool history <name>                # full lineage chain

typhoon tool disable <name>                # off PATH, keep registry row
typhoon tool enable <name>                 # back on PATH
typhoon tool rollback <name>               # revert to previous version from .history/
typhoon tool delete <name>                 # remove registry row, archive binary
typhoon tool purge <name>                  # hard delete, including .history/

typhoon tool promote <path>                # adopt a hand-written script into the registry
typhoon tool check-deps                    # scan external_deps across all CLIs
typhoon tool sync                          # rebuild binaries from registry source (second machine)
```

`promote` is the escape hatch: user writes a script themselves and wants Typhoon to track it. Runs the classification + safety check, adds it with `approved_by='user'` and no origin proposal.

### Evolution and deprecation

Dream watches its own CLIs:

- **Error rate rising** → propose a fix as a replacement.
- **New flag patterns observed** → propose an extension (e.g., user keeps piping `--author` filter → propose v2 with `--author` built in).
- **Unused for N days** (default 30) → propose deprecation as a `cli_proposals` entry with kind `deprecate`. User approves → status flips to `disabled`, binary archives.

Deprecation never hard-deletes. A disabled CLI stays in the registry and `.history/` so a future dream run can revive it if usage reappears.

### Sharing across machines

TursoDB is the always-online state store for one Typhoon runtime instance. The runtime itself runs on one machine, but the operator may use the same TursoDB database from other machines during forge/review workflows. Registry rows, `cli_proposals`, `memories`, and `config` are therefore available wherever the operator has credentials. Artifacts don't sync automatically (arch and runtime mismatch risk).

Re-materialization depends on what the forge produced:

- **Script languages** (bash, Python, Deno, Node, Ruby…): `typhoon tool sync` writes the source back to `~/.typhoon/bin/`, `chmod +x`, and checks declared dependencies. Near-instant.
- **Compiled languages** (Rust, Go…): the registry carries the actual source that was forged on machine A. `typhoon tool sync` runs the local toolchain (`cargo build`, `go build`) on that exact source to produce the binary — **no forge re-invocation**, no LLM variability. Background, priority-queued by `use_count`.

The registry always stores the brief + hardened requirement + forged source. Compiled binaries themselves aren't synced.

### External dependencies

A CLI that shells out to `jq` or `gh` is portable only where those exist. The forge declares external dependencies in the delivery, and `typhoon tool propose submit` stores them alongside the source. Typhoon may also run a best-effort source scan to catch obvious missing declarations, but the delivery remains the source of truth. `typhoon tool show` lists dependencies; `typhoon tool check-deps` scans the whole registry and flags missing tools.

**Install gates on `check-deps`**: missing dependencies block install rather than leaving a broken binary on `PATH`. The user installs the tool, rejects the proposal, or edits the source to remove the dependency.

---

## 5. Evidence This Is Reachable

**Hermes Agent (Nous Research; v0.10.0 on Apr 16, 2026)** is evidence that an agent with a closed learning loop can be useful in the wild. As of Apr 24, 2026, the official GitHub repo reports roughly 97.8K stars. The important ideas for Typhoon are not the star count; they are the shape of the loop: create reusable artifacts from experience, improve them through use, retrieve past sessions, run through messaging channels, and schedule unattended work.

Hermes forges skill documents and is now exploring self-evolution of skills, prompts, tool descriptions, and eventually code through trace-driven optimization plus human-reviewed PRs. Typhoon adopts the parts that fit: trace analysis, requirement hardening, artifact lifecycle, scheduled review, and human ratification. Typhoon rejects the part that creates an in-context skill catalog. The reusable artifact remains a CLI, not a skill file.

**mem0 v3 (April 2026)** is useful as a memory-system reference, not a dependency. Its public docs report 91.6 on LoCoMo and 93.4 on LongMemEval with ADD-only extraction, entity linking, and multi-signal retrieval under a retrieval token budget. Typhoon borrows those design constraints for its own memory layer: append rather than overwrite, preserve temporal evidence, retrieve by multiple signals, and cap injected context.

---

## 6. Non-Goals

| Rejected | Why |
|---|---|
| In-context skill catalog | Token tax — the whole reason we exist |
| Silent changes to executable state | Every CLI install needs operator approval in v0.1; tier-based auto-install is a v0.2 question |
| Typhoon verifying CLI correctness | Correctness is the forge's responsibility — it delivers source + correctness argument; operator accepts or rejects. Typhoon stores metadata and rejects hardcoded paths, but does not sandbox or run replay tests as a correctness gate. |
| Silent personality changes | Persona proposals always require approval — no auto-tier exists for `persona` attribute mutations |
| Typhoon writing CLI source code itself | Synthesis is delegated to the operator's chosen coding-agent forge; Typhoon writes proposal briefs, not code |
| Typhoon invoking the forge automatically (v0.1) | Operator runs the forge manually with their chosen coding agent; automation is deferred until the full loop is validated end-to-end by hand |
| Picking a single CLI language | Operator (via the forge) picks per CLI, constrained only by "runs on the Linux/Mac host" |
| Re-implementing Hermes Agent | They forge skills; we forge CLIs. Different artifact, same loop |
| Cloudflare Workers / browser target | CLI product; wrong substrate |
| YAML / JSON config files | Files rot, self-modify is fragile, SQL is the config |
| Python / Node runtime for **Typhoon itself** | Bloat, slow startup, single binary wins. (Generated CLIs may use any language the forge picks.) |

---

## 7. Stack (brief)

| Layer | Choice | Why |
|---|---|---|
| Typhoon runtime | Rust 2021 | Single binary, predictable latency, good WASM story later |
| DB | TursoDB / libSQL client | Always-online SQL state store; one Typhoon runtime instance owns one DB |
| Channel | Telegram (primary); external-agent CLI (Codex, Claude Code, Cursor…) for the operator | Telegram = always-on + multi-device free; external-agent path uses one-shot subcommands, no REPL needed |
| Online LLM (agent) | Cloud frontier (Claude Sonnet 4.6 / GPT-5 / GLM 5.1) | Quality per turn matters |
| Dream LLM (proposal writer) | Cloud cheap batch model (Haiku 4.5 / MiniMax M2.7 / similar) | Cheap, batch, overnight; only writes proposal briefs, not code |
| Forge (code synthesizer) | **Operator-driven coding-agent workflow** in v0.1 (Codex, Claude Code CLI, Cursor, or similar) | Not automated by Typhoon yet; operator chooses the agent and handles requirement hardening, synthesis, quality iteration, and retries. Automation comes after the manual loop is validated. |
| CLI target language | **Any** that runs on the Linux/Mac host | Forge picks per CLI (bash, Python, Rust, Deno, Go, …) |
| State | One DB | Config, memories, signals, proposals, CLI registry — all SQL rows |

Typhoon itself: no YAML, no JSON config, no Python, no Node. Generated CLIs: whatever the forge picks.

---

## 8. Typhoon's Own Command Surface (sketch — exact shape belongs in the design doc)

```bash
typhoon init --url URL --token TOK     # connect persona-core TursoDB, run Typhoon migrations + seed
typhoon gateway                        # Channel daemon: Telegram edge loop + queue-consuming worker loop

typhoon dream [--catchup] [--force]    # readiness-gated dream cycle; --force bypasses the signal-token gate
typhoon cron                           # scheduler daemon

typhoon tool propose list [--awaiting-forge|--awaiting-user]   # CLI proposals
typhoon tool propose show <id>                                 # brief + evidence
typhoon tool propose submit <id> --requirements <file> --tool-doc <tool.md> --source <file>
                                                          # attach forged requirement, tool.md,
                                                          # source, correctness argument, deps, metadata
typhoon tool propose approve|edit|reject <id>             # resolve once awaiting_user
typhoon tool list|show|disable|enable|rollback|delete|purge|promote|sync|check-deps  # lifecycle (see §4)
typhoon persona list|show|approve|reject                  # persona-attribute proposals
typhoon signal record / typhoon memory query              # external-agent sidecar one-shots

typhoon config get|set|list
typhoon sql "<SELECT ...>"             # debug, read-only
```

---

## 9. What's Deferred

Schema details, atomicity and idempotency rules, wasmtime WIT interface, scoring-weight tables, and the phase-by-phase build plan belong in the **design doc and implementation plan** that come after this proposal settles. This document is the goal, the mechanism, and the evidence — nothing more.

`OUTDATEDPLAN.md` and `OUTDATEDDESIGN.md` describe an earlier Cloudflare-Workers-shaped scope and do not apply. New plan and design will be written against this proposal.
