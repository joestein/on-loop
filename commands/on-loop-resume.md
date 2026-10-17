---
name: on-loop-resume
description: Resume an interrupted SDLC loop from the last phase or a specified phase, or approve/revise a paused DESIGN_REVIEW
user_invocable: true
argument: "[--from=phase] [--session=<name>] [--feedback=\"<text>\"]"
---

# /on-loop-resume

Resume an interrupted on-loop run from where it left off, from a specified phase, or approve/revise a change paused at `DESIGN_REVIEW`.

## Usage

```
/on-loop-resume                                              # Resume most recent non-complete session
/on-loop-resume --from=CODE                                  # Resume from a specific phase
/on-loop-resume --session=20260426_143052_user-management-api  # Resume a specific session
/on-loop-resume --session=<name> --from=CODE                  # Both
/on-loop-resume                                              # On a DESIGN_REVIEW session: approve and continue to PLAN
/on-loop-resume --feedback="use approach B, and split the schema migration into its own step"  # Request a design revision
```

## Instructions

1. **Find the session to resume**:
   - If `--session=<name>` is provided, look for `.on-loop/sessions/<name>/state.json`
   - Otherwise, read `.on-loop/index.json` and find the most recent session with `status: "active"` or `status: "failed"`
   - If no session found, report that no loop exists to resume

2. Read the session's `state.json` to understand the current state.

3. **Verify worktree exists**:
   - Read `worktree_path` from `state.json`
   - Check if the worktree directory exists at that path
   - If not, recreate it: `git worktree add <worktree_path> <branch>`
   - If the branch no longer exists, report error and suggest starting fresh with `/on-loop`

4. **If the session is paused at `"DESIGN_REVIEW"`**, handle it before the general resume logic:
   - **If `--feedback="<text>"` is provided**: write the text to `<session-dir>/agent-notes/design-feedback.md`, increment `retries.design_to_review` in `state.json`. If this would exceed `max_retries.design_to_review` (2), do not loop again — instead record a `HIGH` severity TODO with the feedback and transition straight to `PLAN` using the existing recommendation, telling the user why. Otherwise, transition to `"DESIGN"` and re-dispatch the **design agent** (`agents/design.md`), which reads the feedback file and revises `design.md` (see `agents/design.md` and `skills/on-loop-design/SKILL.md`). This ends back at `DESIGN_REVIEW` for another look, or auto-advances to `PLAN` if the revision is now `BOUNDED`.
   - **If no `--feedback` and no `--from`**: this is an approval. Transition `DESIGN_REVIEW → PLAN` using the design agent's existing recommendation from `design.md`. Do not re-dispatch the design agent.
   - **If `--from` is also given**: honor `--from` instead (an explicit phase override takes precedence over the approval default) and continue with step 5 below.
   - Skip steps 5-6 below once this branch has determined the resume phase.

5. If `--from=<phase>` is specified (and step 4 didn't already resolve it):
   - Validate the phase name is valid (INIT, SPEC, DESIGN, DESIGN_REVIEW, PLAN, CODE, TEST, SECURITY, DOC, BUILD, REVIEW)
   - Reset the state to that phase
   - Clear any error state
   - Note: Retry counts are NOT reset (to prevent infinite loops)

6. If no `--from` argument and the session isn't at `DESIGN_REVIEW`:
   - If phase is `"FAILED"`, resume from the phase that failed
   - If phase is any active phase, resume from that phase
   - If phase is `"COMPLETE"`, report the loop is already complete

7. Resume the orchestrator pipeline from the determined phase:
   - Re-read all existing agent notes from the session directory for context
   - Continue the normal phase sequence from the resume point
   - All agent work happens in the worktree directory
   - The orchestrator handles everything from here (same as `/on-loop`)

8. Update `.on-loop/index.json` session status back to `"active"` if it was `"failed"`

9. Report to the user:
   - Which session is being resumed (session name)
   - Which phase is being resumed from
   - The worktree path being used
   - What context is available from previous phases
   - Any warnings about state that may be stale

## Validation

- The session directory must exist with a valid `state.json`
- The resume phase must be a valid phase in the pipeline
- Warn if resuming from a phase earlier than the last completed phase (re-running work)
- `--feedback` is only meaningful when the session is paused at `DESIGN_REVIEW`; if passed against a session in any other phase, warn and ignore it rather than silently discarding user intent
