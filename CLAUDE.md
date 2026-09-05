# On-Loop Plugin

Spec-driven SDLC plugin that orchestrates specialist agents through a full development lifecycle.

## Commands

- `/on-loop <prompt>` — Run full SDLC loop (spec -> design -> code -> test -> security -> docs -> build -> review -> git)
- `/on-loop-continue <prompt>` — Continue work in an existing on-loop worktree (full SDLC pipeline, commits and pushes, no new worktree or PR)
- `/on-loop-check [PR number or branch]` — Check GitHub CI status, fix regressions, alert on pre-existing failures
- `/on-loop-debug-fix [description or image] [--complexity=level]` — Debug and fix issues from infrastructure logs or user-provided context
- `/on-loop-status` — Check current loop progress and list all sessions
- `/on-loop-resume [--from=phase] [--session=<id>]` — Resume an interrupted loop
- `/on-loop:clear [--include-logs]` — Clean up worktrees, optionally remove session logs, switch to main
- `/on-loop:main-resolve` — Pull main, merge into current branch, resolve conflicts
- `/on-spec <description>` — Standalone spec generation
- `/on-test <target>` — Standalone test generation
- `/on-security <target>` — Standalone security audit
- `/on-doc <target>` — Standalone documentation generation
- `/on-build <target>` — Standalone build/CI setup
- `/on-review <target>` — Standalone code review

### Roadmap Commands (Multi-Session)

- `/on-prepare <prompt>` — Generate a roadmap with phases, steps, and acceptance criteria from a full prompt
- `/on-plan [feature-slug]` — Read roadmap, produce detailed implementation plan with parallelism annotations
- `/on-continue [feature-slug]` — Pick up next available step and execute through agent pipeline
- `/on-pause [feature-slug]` — Release locks, commit WIP, write handoff summary

## Architecture

Each `/on-loop` session operates in a **git worktree** at `.claude/worktrees/<branch-slug>/`, allowing multiple sessions to run concurrently without interfering with each other or the user's working directory.

### Session Logs

Session state is persisted under `.on-loop/sessions/<YYYYMMDD_HHMMSS_branch-slug>/`:
- `state.json` — Phase tracking (only orchestrator writes)
- `plan.md` — Implementation plan (all agents read)
- `changes.log` — Append-only file modification log
- `agent-notes/<agent>.md` — Structured output per agent

The session index at `.on-loop/index.json` tracks all sessions.

Session directories are committed to the repo as an audit log.

### Worktrees

Worktrees at `.claude/worktrees/` are gitignored and temporary:
- Created during INIT
- Used for all agent work (SPEC through REVIEW)
- Commits and pushes happen from the worktree (GIT phase)
- Removed on COMPLETE, left in place on FAILED (for resume)

## Agent Roster

| Agent | Role |
|-------|------|
| orchestrator | Pipeline control, quality gates, retry logic, worktree/session lifecycle |
| architect | Spec generation, ADRs, system design |
| design | Scope classification, approach exploration, human approval gate for architectural work |
| coding | Implementation with security-first practices |
| testing | Unit, integration, and E2E tests |
| security | OWASP/STRIDE audit, compliance checks |
| documentation | READMEs, guides, CLAUDE.md files |
| build | Makefile, CI/CD, lint/security configs |
| reviewer | Final code review gate |

## Quality Standards

All agents operate as Staff Engineers with ISC2 certifications targeting regulated financial environments. See `shared/AGENT_PERSONA.md` for the full persona and `shared/QUALITY_STANDARDS.md` for the quality bar.

## Workspace Convention

- `.on-loop/` — Persistent session logs, committed to repo
- `.on-loop/index.json` — Session manifest
- `.on-loop/sessions/<YYYYMMDD_HHMMSS_slug>/` — Per-session state, plan, changes, agent notes
- `.claude/worktrees/` — Temporary git worktrees (gitignored)

## Roadmap Convention

The `roadmap/` directory is persistent and committed to the repo. It contains:
- `roadmap/<feature>.md` — Roadmap documents with phases, steps, mermaid diagrams
- `roadmap/.state/<feature>.json` — State tracking per feature (phase/step status, locks)
- `roadmap/.state/_global.json` — Cross-session coordination (active sessions, global locks)

Multiple sessions can work on the same feature concurrently using `/on-continue`. Each session gets its own worktree and session directory. File-based locking with TTL prevents conflicts.

## Skills

| Skill | Purpose |
|-------|---------|
| `skills/roadmap-state/` | State file operations: init, read, transition, step tracking |
| `skills/roadmap-lock/` | Lock acquisition, release, heartbeat, stale detection |
| `skills/quality-gate/` | Pass/fail criteria for phase transitions |
| `skills/loop-state/` | On-loop phase state transitions and validation |
| `skills/on-loop-design/` | DESIGN phase mechanics: scope classification, approach exploration, human approval gate |
