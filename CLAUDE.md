# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Type

This is a **Claude Code agent-configuration repository**, not a software package. It contains no build system, test suite, package manager files, or deployable code. The only source files are agent manifests under `.claude/agents/` and skill definitions under `.claude/skills/`.

## Repository Structure

- `.claude/agents/` — Agent manifest files that define specialized Claude Code agents:
  - `football-match-reviewer.md` — Retrospectively grades frozen predictions against actual results, computes calibration metrics, and amends evidence annotations in other agents' memory.
  - `football-intelligence-gatherer.md` — Collects pre-match intelligence (odds, lineups, recent form, head-to-head) for a specific football/soccer match.
  - `football-match-analyzer.md` — Converts gathered match intelligence into probability distributions across 1X2, correct score, Asian handicap, and total goals markets.
  - `lottery-strategist.md` — Builds a China Sports Lottery (中国体彩) betting plan within a 20 yuan budget from the analyzer's probabilities.
- `.claude/skills/football-match-analysis/` — The orchestration skill. `SKILL.md` is the single entry point for the whole pipeline; `references/` holds the stage handoff contracts, the review protocol, and the artifact templates; `scripts/` holds a convenience directory helper.
- `matches/YYYY-MM-DD/` — Runtime output directory (created on demand): per-match `-intel.md`, `-analysis.md`, `-review.md`, plus a `summary.md` and, when a ticket was requested, `plan.md`.
- `.claude/agent-memory/` — Per-agent persistent memory directories, one per agent. These start empty and are populated by agents at runtime.

## Multi-Agent Workflow

Requests in this domain are handled by a four-stage pipeline, orchestrated by the `football-match-analysis` skill:

0. **Review** — Conditionally, before anything else: launch `football-match-reviewer` for any match under `matches/` that has a `-analysis.md`, a match date earlier than today, and no `-review.md`. If there are none, this step is skipped silently.
1. **Gather** — When the user names a specific match, launch `football-intelligence-gatherer` to collect odds, lineups, form, and H2H data.
2. **Analyze** — Feed the gathered intelligence into `football-match-analyzer` to produce calibrated probabilities and market assessments.
3. **Plan** — If the user wants a lottery ticket, launch `lottery-strategist` using the analyzer's probabilities to generate a ≤20 yuan 竞彩足球 plan. This step requires explicit user consent every time — it spends real money.

Agents should be invoked in order; each stage depends on the previous stage's output file. Prefer invoking the skill rather than dispatching agents ad hoc, so the handoff contracts are respected.

`football-match-reviewer` is the only agent authorized to amend evidence annotations in other agents' memory. It may not silently rewrite a claim — see `references/review-protocol.md`.

## Development Workflow

There are no build, lint, test, or install commands for this repository. Changes are made by editing the Markdown agent manifests in `.claude/agents/`.

When modifying an agent:

- Keep the YAML frontmatter (`name`, `description`, `model`, `color`, `memory`) intact.
- The `description` field is used by Claude Code to decide when to spawn the agent; keep it precise and include the trigger examples.
- Agent manifests support Markdown body content that defines behavior, output formats, and memory-handling rules.
- Each agent manifest already contains its own detailed instructions, output templates, and edge-case handling; treat those as the authoritative spec for that agent.

## Memory System

Each agent has a dedicated memory directory under `.claude/agent-memory/<agent-name>/`. Agents write `user`, `feedback`, `project`, and `reference` memories there as Markdown files with YAML frontmatter, and maintain the per-agent `MEMORY.md` index. Do not create or delete these directories manually; agents are instructed to write to them directly.

## Language Conventions

Agents are configured to respond in the user's language (Chinese or English). The lottery strategist uses Chinese lottery terminology (竞彩足球, 胜平负, 让球胜平负, 混合过关, etc.) in its output.

The reviewer's calibration reports and the skill's orchestration text follow the same rule: match the user's language.
