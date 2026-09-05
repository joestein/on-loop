---
name: on-loop
description: Run a full spec-driven SDLC loop with orchestrated specialist agents
user_invocable: true
argument: prompt or path to spec file
---

# /on-loop

Run a complete spec-driven software development lifecycle for the given prompt.

## Usage

```
/on-loop <prompt describing what to build>
/on-loop <path-to-spec-file>
```

## What This Does

Launches the **orchestrator agent** which drives the following pipeline:

1. **INIT** — Creates git worktree, session directory, feature branch
2. **SPEC** — Architect agent generates a detailed specification
3. **DESIGN** — Design agent classifies scope and recommends an approach. Architectural-scope changes **pause here for human approval**; bounded changes proceed automatically (see `skills/on-loop-design/SKILL.md`)
4. **PLAN** — Orchestrator writes an implementation plan
5. **CODE** — Coding agent implements the spec
6. **TEST** — Testing agent writes and runs tests (retries up to 3x on failure)
7. **SECURITY** — Security agent audits the code (retries up to 2x on blockers)
8. **DOC + BUILD** — Documentation and build agents run in parallel
9. **REVIEW** — Reviewer agent performs final code review (retries up to 2x)
10. **GIT** — Commit all changes from worktree, push branch, create PR
11. **COMPLETE** — Summary of everything built with PR link (worktree left in place)

## Instructions

When this command is invoked:

1. Read the user's argument. If it's a file path, read the file contents as the prompt.

2. **Generate session identity**:
   - Generate a session ID (UUID v4): `python3 -c "import uuid; print(str(uuid.uuid4()))"`
   - Generate a session name: `YYYYMMDD_HHMMSS_<branch-slug>` (e.g., `20260426_143052_user-management-api`)
   - The session name is used for the directory name (human-readable, sorted chronologically)

3. **Branch creation** (before worktree):
   - Check current branch with `git branch --show-current`
   - If on `main` or `master`: create branch `on-loop/<slugified-prompt>` (lowercase, `[a-z0-9-]` only, max 50 chars, must match `^[a-z0-9][a-z0-9-]*[a-z0-9]$`)
     - `git branch on-loop/<branch-slug>`
   - If already on a feature branch: use that branch name
   - Derive `<branch-slug>` from the branch name (strip `on-loop/` prefix if present)

4. **Create git worktree**:
   - Create worktree: `git worktree add .claude/worktrees/<branch-slug> on-loop/<branch-slug>`
   - If the worktree already exists for this branch, report error and suggest `git worktree remove` or `/on-loop:clear`
   - Store the worktree path in state.json as `worktree_path`
   - All subsequent agent work (SPEC through REVIEW) operates within this worktree directory

5. **Initialize session directory**:
   - Create `.on-loop/sessions/<session-name>/` with `agent-notes/` subdirectory
   - Create `state.json` with:
     - `version`: `"1.2"`
     - `session_id`: the generated UUID
     - `phase`: `"INIT"`
     - `prompt`: the user's prompt
     - `branch`: the branch name
     - `worktree_path`: `.claude/worktrees/<branch-slug>`
     - `session_dir`: `.on-loop/sessions/<session-id>`
   - Create empty `plan.md` and `changes.log`
   - Update `.on-loop/index.json` (create if missing) — append session entry with `status: "active"`

6. Dispatch the **architect agent** (`agents/architect.md`):
   - Provide the user's prompt
   - Agent operates within the worktree directory
   - The architect writes the spec to `.on-loop/sessions/<session-name>/agent-notes/architect.md`

7. Update `state.json` to phase `"DESIGN"` and dispatch the **design agent** (`agents/design.md`):
   - Provide `plan.md` and architect's notes
   - Agent operates within the worktree directory (read-only)
   - The design agent writes `.on-loop/sessions/<session-name>/agent-notes/design.md` with a classification (`BOUNDED`/`ARCHITECTURAL`), recommended approach, and an `approval_required` flag
   - **If `approval_required: false`**: continue to step 8 automatically
   - **If `approval_required: true`**: update `state.json` to phase `"DESIGN_REVIEW"`, print the classification, recommended approach, trade-offs, and open questions from `design.md`, and **stop**. Tell the user to run `/on-loop-resume` to approve and continue, or `/on-loop-resume --feedback="..."` to request a revision (max 2 revisions — see `skills/on-loop-design/SKILL.md`). Do not proceed further in this invocation.

8. Write `plan.md` in the session directory based on the architect's spec and the design agent's recommended approach.

9. Update `state.json` to phase `"CODE"` and dispatch the **coding agent** (`agents/coding.md`):
   - Provide `plan.md` and architect's notes
   - Agent operates within the worktree directory

10. Update to phase `"TEST"` and dispatch the **testing agent** (`agents/testing.md`):
    - Provide `plan.md`, architect's notes, and coding agent's notes
    - Agent operates within the worktree directory
    - If tests fail and retries remain (max 3), go back to CODE with test feedback
    - If retries exhausted, record TODOs and continue

11. Update to phase `"SECURITY"` and dispatch the **security agent** (`agents/security.md`):
    - Provide all prior agent notes
    - Agent operates within the worktree directory
    - If CRITICAL/HIGH findings and retries remain (max 2), go back to CODE with security feedback
    - If retries exhausted, record TODOs and continue

12. Update to phase `"DOC"` and `"BUILD"` — dispatch **documentation** (`agents/documentation.md`) and **build** (`agents/build.md`) agents in parallel.
    - Both agents operate within the worktree directory

13. Update to phase `"REVIEW"` and dispatch the **reviewer agent** (`agents/reviewer.md`):
    - Provide all agent notes
    - Agent operates within the worktree directory
    - If REQUEST_CHANGES and retries remain (max 2), go back to CODE with review feedback
    - If retries exhausted, record TODOs and continue

14. Update to phase `"GIT"` (orchestrator handles directly, from within the worktree):
    - `cd` to the worktree directory
    - Stage all modified/created files from `changes.log` (explicit paths, not `git add -A`)
    - Also stage the session directory: `.on-loop/sessions/<session-name>/`
    - Commit with a descriptive message summarizing the work, ending with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
    - Push branch to origin with `-u` flag
    - Create PR via `gh pr create` with title from prompt and body with summary, files changed, test results, security findings, TODOs
    - Store PR URL in `state.json` as `"pr_url"`

15. Update to phase `"COMPLETE"`:
    - Update session state.json with `phase: "COMPLETE"`
    - Update `.on-loop/index.json` session entry: `status: "complete"`, `completed_at`, `pr_url`
    - **Do NOT remove the worktree** — leave it in place for `/on-loop-continue` or manual use. Use `/on-loop:clear` to clean up worktrees.
    - Print a summary of what was built
    - List files created/modified
    - Report test results
    - Report security findings
    - List any outstanding TODOs
    - Display the PR URL

## Error Handling

`DESIGN_REVIEW` is a planned pause for human approval, not a failure — session status stays `"active"` and the worktree is left untouched either way.

If any phase fails unexpectedly:
- Set `state.json` phase to `"FAILED"` with error details
- Update `index.json` session status to `"failed"`
- **Do NOT remove the worktree** (needed for `/on-loop-resume`)
- Report the failure to the user
- Suggest using `/on-loop-resume` to continue

## Important

- All inter-agent communication goes through `.on-loop/sessions/<session-name>/` files
- Only the orchestrator writes `state.json`
- The session directory is committed to the repo as an audit log
- The worktree at `.claude/worktrees/` is gitignored and temporary
- Each agent reads `shared/AGENT_PERSONA.md` for the Staff Engineer + ISC2 persona
- Agent file operations happen in the worktree; session state lives in the original repo root
