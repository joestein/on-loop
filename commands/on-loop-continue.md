---
name: on-loop-continue
description: Continue work in an existing on-loop worktree — runs full SDLC pipeline, commits and pushes (no new worktree, no new PR)
user_invocable: true
argument: prompt or path to spec file
---

# /on-loop-continue

Run a complete spec-driven SDLC lifecycle **within an existing on-loop worktree**. Reuses the worktree and branch from a prior `/on-loop` session — no new worktree, no new PR.

## Usage

```
/on-loop-continue <prompt describing what to build>
/on-loop-continue <path-to-spec-file>
```

## What This Does

Same agent pipeline as `/on-loop`, but reuses the **existing worktree** created by a prior `/on-loop` run:

1. **INIT** — Locates existing worktree, creates new session directory
2. **SPEC** — Architect agent generates a detailed specification
3. **DESIGN** — Design agent classifies scope and recommends an approach; architectural-scope changes pause for human approval, bounded changes proceed automatically (see `skills/on-loop-design/SKILL.md`)
4. **PLAN** — Orchestrator writes an implementation plan
5. **CODE** — Coding agent implements the spec
6. **TEST** — Testing agent writes and runs tests (retries up to 3x on failure)
7. **SECURITY** — Security agent audits the code (retries up to 2x on blockers)
8. **DOC + BUILD** — Documentation and build agents run in parallel
9. **REVIEW** — Reviewer agent performs final code review (retries up to 2x)
10. **GIT** — Commit all changes and push to existing branch (no PR creation)
11. **COMPLETE** — Summary of everything built

## Key Differences from `/on-loop`

| | `/on-loop` | `/on-loop-continue` |
|---|---|---|
| Worktree | Creates new `.claude/worktrees/<slug>` | Reuses existing worktree |
| Branch | Creates `on-loop/<slug>` if on main | Uses branch from existing session |
| PR | Creates a new PR | No PR — just commits and pushes to existing branch/PR |
| Agent work dir | New worktree directory | Existing worktree directory |
| Cleanup | Removes worktree on complete | Does NOT remove worktree (may be used again) |

## Instructions

When this command is invoked:

1. Read the user's argument. If it's a file path, read the file contents as the prompt.

2. **Locate existing worktree and session**:
   - Read `.on-loop/index.json` to find existing sessions
   - Check current branch with `git branch --show-current`
   - **Find the matching session**: look for sessions where the `branch` matches the current branch, or if the user is on `main`/`master`, look for the most recent `"active"` or `"complete"` session
   - If no session is found, **abort with error**:
     ```
     ERROR: No existing on-loop session found.
     Run /on-loop first to create a worktree and session, then use /on-loop-continue for subsequent work.
     ```
   - Read the session's `state.json` to get the `worktree_path`
   - Verify the worktree exists at `<worktree_path>`:
     ```bash
     git worktree list
     ```
   - If the worktree does not exist, **abort with error**:
     ```
     ERROR: Worktree at <worktree_path> no longer exists.
     Run /on-loop to create a new session, or /on-loop:clear to clean up stale state.
     ```
   - Store the worktree path and branch name for use in all subsequent steps

3. **Generate session identity**:
   - Generate a session ID (UUID v4): `python3 -c "import uuid; print(str(uuid.uuid4()))"`
   - Derive `<branch-slug>` from the branch name (strip `on-loop/` prefix if present)
   - Generate a session name: `YYYYMMDD_HHMMSS_<branch-slug>` (e.g., `20260426_153052_user-management-api`)

4. **Initialize session directory**:
   - Create `.on-loop/sessions/<session-name>/` with `agent-notes/` subdirectory
   - Create `state.json` with:
     - `version`: `"1.2"`
     - `session_id`: the generated UUID
     - `phase`: `"INIT"`
     - `prompt`: the user's prompt
     - `branch`: the branch name (from the existing session)
     - `worktree_path`: the existing worktree path
     - `session_dir`: `.on-loop/sessions/<session-name>`
     - `mode`: `"continue"` (distinguishes from regular on-loop sessions)
   - Create empty `plan.md` and `changes.log`
   - Update `.on-loop/index.json` — append session entry with `status: "active"`, `mode: "continue"`

5. Dispatch the **architect agent** (`agents/architect.md`):
   - Provide the user's prompt
   - Agent operates within the **existing worktree directory**
   - The architect writes the spec to `.on-loop/sessions/<session-name>/agent-notes/architect.md`

6. Update `state.json` to phase `"DESIGN"` and dispatch the **design agent** (`agents/design.md`):
   - Provide `plan.md` and architect's notes
   - Agent operates within the **existing worktree directory** (read-only)
   - The design agent writes `.on-loop/sessions/<session-name>/agent-notes/design.md` with a classification (`BOUNDED`/`ARCHITECTURAL`), recommended approach, and an `approval_required` flag
   - **If `approval_required: false`**: continue to step 7 automatically
   - **If `approval_required: true`**: update `state.json` to phase `"DESIGN_REVIEW"`, print the classification, recommended approach, trade-offs, and open questions from `design.md`, and **stop**. Tell the user to run `/on-loop-resume` to approve and continue, or `/on-loop-resume --feedback="..."` to request a revision (max 2 revisions — see `skills/on-loop-design/SKILL.md`).

7. Write `plan.md` in the session directory based on the architect's spec and the design agent's recommended approach.

8. Update `state.json` to phase `"CODE"` and dispatch the **coding agent** (`agents/coding.md`):
   - Provide `plan.md` and architect's notes
   - Agent operates within the **existing worktree directory**

9. Update to phase `"TEST"` and dispatch the **testing agent** (`agents/testing.md`):
   - Provide `plan.md`, architect's notes, and coding agent's notes
   - Agent operates within the **existing worktree directory**
   - If tests fail and retries remain (max 3), go back to CODE with test feedback
   - If retries exhausted, record TODOs and continue

10. Update to phase `"SECURITY"` and dispatch the **security agent** (`agents/security.md`):
    - Provide all prior agent notes
    - Agent operates within the **existing worktree directory**
    - If CRITICAL/HIGH findings and retries remain (max 2), go back to CODE with security feedback
    - If retries exhausted, record TODOs and continue

11. Update to phase `"DOC"` and `"BUILD"` — dispatch **documentation** (`agents/documentation.md`) and **build** (`agents/build.md`) agents in parallel.
    - Both agents operate within the **existing worktree directory**

12. Update to phase `"REVIEW"` and dispatch the **reviewer agent** (`agents/reviewer.md`):
    - Provide all agent notes
    - Agent operates within the **existing worktree directory**
    - If REQUEST_CHANGES and retries remain (max 2), go back to CODE with review feedback
    - If retries exhausted, record TODOs and continue

13. Update to phase `"GIT"` (orchestrator handles directly, from within the existing worktree):
    - `cd` to the existing worktree directory
    - Stage all modified/created files from `changes.log` (explicit paths, not `git add -A`)
    - Also stage the session directory: `.on-loop/sessions/<session-name>/`
    - Commit with a descriptive message summarizing the work, ending with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
    - Push to origin (the branch should already be tracking remote; if not, use `-u` flag)
    - **Do NOT create a PR** — this is continuing work on an existing branch with an existing PR

14. Update to phase `"COMPLETE"`:
    - Update session state.json with `phase: "COMPLETE"`
    - Update `.on-loop/index.json` session entry: `status: "complete"`, `completed_at`
    - **Do NOT remove the worktree** — it may be needed for further `/on-loop-continue` runs
    - Print a summary of what was built
    - List files created/modified
    - Report test results
    - Report security findings
    - List any outstanding TODOs
    - Note: worktree left in place for future use

## Error Handling

`DESIGN_REVIEW` is a planned pause for human approval, not a failure — session status stays `"active"` and the worktree is left untouched either way.

If any phase fails unexpectedly:
- Set `state.json` phase to `"FAILED"` with error details
- Update `index.json` session status to `"failed"`
- **Do NOT remove the worktree** (needed for retry or resume)
- Report the failure to the user
- Suggest using `/on-loop-resume` to continue

## Important

- All inter-agent communication goes through `.on-loop/sessions/<session-name>/` files
- Only the orchestrator writes `state.json`
- The session directory is committed to the repo as an audit log
- The worktree at `.claude/worktrees/` is **reused from a prior `/on-loop` session** — not created or destroyed
- Each agent reads `shared/AGENT_PERSONA.md` for the Staff Engineer + ISC2 persona
- Agent file operations happen in the existing worktree; session state lives in the original repo root
- This command requires a prior `/on-loop` session with an existing worktree — use `/on-loop` first
