---
name: on-loop-status
description: Check the progress of the current SDLC loop
user_invocable: true
---

# /on-loop-status

Display the current status of active, completed, or failed on-loop sessions.

## Instructions

1. Check if `.on-loop/index.json` exists. If not, report that no sessions exist.

2. Read `.on-loop/index.json` and list all sessions:

```
On-Loop Sessions
════════════════
Session Name                              Branch                     Status    Phase     Started
───────────────────────────────────────── ────────────────────────── ───────── ───────── ────────────────────
20260426_100000_user-api                  on-loop/user-api           active    CODE      2026-04-26T10:00:00Z
20260425_140000_auth-middleware            on-loop/auth-middleware    complete  COMPLETE  2026-04-25T14:00:00Z
```

3. For each **active** session, read its `state.json` from `.on-loop/sessions/<session-name>/state.json` and display detailed status:

```
Active Session: 20260426_100000_user-api
══════════════════════════════
Loop ID:    <uuid>
Branch:     <branch name>
Worktree:   <worktree_path>
Phase:      <phase> (<description>)
Started:    <timestamp>
Updated:    <timestamp>
Agent:      <current agent>

Progress:
  ✅ INIT
  ✅ SPEC — <brief summary>
  ✅ DESIGN — <classification: BOUNDED/ARCHITECTURAL>
  ✅ PLAN
  ✅ CODE — <brief summary>
  🔄 TEST — In progress
  ⬜ SECURITY
  ⬜ DOC
  ⬜ BUILD
  ⬜ REVIEW

Retries:
  design→review:  0/2
  test→code:      1/3
  security→code:  0/2
  review→code:    0/2

TODOs: None
```

If phase is `"DESIGN_REVIEW"`, show it as a distinct, non-error waiting state rather than `🔄`:

```
Active Session: 20260426_100000_user-api
══════════════════════════════
Phase:      DESIGN_REVIEW (paused — awaiting human approval)

Progress:
  ✅ INIT
  ✅ SPEC — <brief summary>
  ⏸️  DESIGN — ARCHITECTURAL, awaiting approval (see design.md)
  ⬜ PLAN
  ...

Next step: review `.on-loop/sessions/<session-name>/agent-notes/design.md`, then
  /on-loop-resume                       # approve and continue
  /on-loop-resume --feedback="..."      # request a revision
```

4. If agent notes exist in the session directory, show a brief summary from each completed agent:
   - Read each file in `.on-loop/sessions/<session-name>/agent-notes/`
   - Extract and display the `## Summary` section (for `design.md`, show the `## Classification` and `## Recommended Approach` sections instead — it has no `## Summary`)

5. For **failed** sessions, also display the error field from state.json and suggest `/on-loop-resume --session=<session-name>`

6. For sessions **paused at `DESIGN_REVIEW`**, treat them as active (not failed) and display the "Next step" block above instead of an error

7. Show active worktrees:
   ```bash
   git worktree list
   ```
