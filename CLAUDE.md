# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Typhoon Way

A self-growing agent system delivered as skills for NullClaw. Combines OpenClaw's dream-based memory consolidation with Hermes Agent's autonomous skill creation loop — all in SKILL.md format, no new binary.

### Influences
- **NullClaw** (`~/claw/nullclaw`): Target runtime. Zig-based, 678KB binary, skill system with SKILL.md manifests
- **OpenClaw** (`~/claw/openclaw`): Dream system architecture — Light/REM/Deep phases, memory promotion scoring
- **Hermes Agent** (`~/claw/hermes-agent`): Self-growth loop — background review, skill creation from experience, security validation

### Architecture
5 composable skills:
1. `dream-cortex` — orchestrates the dream cycle on HEARTBEAT cron
2. `memory-weaver` — declarative memory with search, decay, and promotion
3. `skill-forge` — procedural memory, creates/patches skills from patterns
4. `echo-sense` — session analytics, feeds signals into dream system
5. `soul-shaper` — personality evolution via SOUL.md patches

### Key Concepts
- **Dream phases**: Light (sort/dedup) → REM (pattern recognition) → Deep (promotion to MEMORY.md + skill creation)
- **Promotion scoring**: Frequency (0.24) + Relevance (0.30) + Diversity (0.15) + Recency (0.15) + Consolidation (0.10) + Conceptual (0.06)
- **Self-growth triggers**: 5+ tool calls, error recovery, user correction, novel workflow
- **Everything is SKILL.md**: plain markdown, inspectable, shareable, no compiled code
