---
name: on-loop-design
description: Defines the DESIGN phase — scope classification, approach exploration, and the human approval gate for architectural work, inserted between SPEC and PLAN
---

# On-Loop Design Phase

This skill governs the `DESIGN` phase of the on-loop pipeline: the step between `SPEC` (architect writes the spec) and `PLAN` (orchestrator turns it into tasks). It exists to catch a wrong direction *before* CODE/TEST/SECURITY spend retries building the wrong shape of thing.

It is adapted from the [superpowers `brainstorming` skill](https://github.com/obra/superpowers)'s scope classification and hard-approval-gate model. The difference: `brainstorming` is a synchronous, conversational skill that blocks a chat turn on human input. on-loop is an autonomous, resumable pipeline — so instead of blocking mid-conversation, the DESIGN phase either proceeds automatically (bounded scope) or pauses the loop in a durable, resumable state (`DESIGN_REVIEW`) and hands control back to the user, the same way `FAILED` already does for errors.

## Scope Classification

The design agent classifies the change using the architect's spec as `BOUNDED` or `ARCHITECTURAL`. This mirrors brainstorming's bounded/architectural split; on-loop has no spike path (`/on-loop-debug-fix` fills that role for throwaway investigation).

### BOUNDED

A change that fits into a flow that **already exists and is readable** in the repo:

- A new field, flag, endpoint, or CLI option on an existing component
- A bug fix, however deep the root cause, that doesn't change any public interface
- A change confined to one file or one tightly-related cluster of files
- No new persistent schema, no new service boundary, no new external interface

Understanding the *kind* of app is not sufficient — bounded requires the specific flow being changed to already exist. If there's no existing flow to point to, it isn't bounded.

### ARCHITECTURAL

- A new subsystem, service, or top-level component
- A new or changed persistent data schema
- A new external interface (API, event, file format) that other code or other systems will depend on
- A change to an interface that existing callers already depend on
- Anything spanning more than one independently-deployable or independently-owned part of the system

**When in doubt, classify as ARCHITECTURAL.** The cost of an unnecessary pause is one resume command; the cost of an unreviewed architectural mistake is a CODE/TEST/SECURITY cycle built on the wrong foundation.

**The ratchet is one-way.** If a downstream agent (coding, testing, security, reviewer) discovers mid-pipeline that a `BOUNDED` classification was wrong — the change actually touches a shared interface or introduces a new schema — it records this as a `CRITICAL` issue in its agent notes. The orchestrator then routes back to `DESIGN` for reclassification as `ARCHITECTURAL`, never the other direction.

## Process by Classification

### BOUNDED

1. Design agent identifies the one approach that matches the existing pattern
2. Writes a short `design.md` (single-row approaches table, one-paragraph recommendation)
3. Sets `approval_required: false`
4. Orchestrator transitions `DESIGN → PLAN` automatically — **no pause**

The PR created at the end of the loop is still the human checkpoint for bounded work, same as any other on-loop change.

### ARCHITECTURAL

1. Design agent proposes 2-3 approaches with trade-offs, recommends one
2. Writes `design.md` with an `## Open Questions` section if anything needs a human answer
3. Sets `approval_required: true`
4. Orchestrator transitions `DESIGN → DESIGN_REVIEW` and **stops the loop**

## The DESIGN_REVIEW Gate

When the design agent sets `approval_required: true`, the orchestrator:

1. Sets `state.json` `phase` to `"DESIGN_REVIEW"` (this is a pause state, not a failure — `index.json` session status stays `"active"`)
2. Does **not** dispatch PLAN or any further agent
3. Prints to the user:
   - The classification and its justification
   - The recommended approach and its trade-offs
   - Any open questions
   - The path to the full `design.md`
   - Exactly how to respond (see below)
4. Ends its turn. The worktree and session are left in place — nothing is lost by pausing.

### Responding to a DESIGN_REVIEW pause

- **Approve as-is**: `/on-loop-resume` — resumes straight into `PLAN` using the recommended approach
- **Request changes**: `/on-loop-resume --feedback="<what to change>"` — the orchestrator writes the feedback to `<session-dir>/agent-notes/design-feedback.md`, transitions back to `DESIGN`, and re-dispatches the design agent for a revision. This counts against the `design_to_review` retry budget (max 2, see below)
- **Abandon**: `/on-loop:clear` — tears down the worktree and session without proceeding

### Revision Budget

`DESIGN_REVIEW → DESIGN` (feedback revision) follows the same retry-budget pattern as the rest of the pipeline: max **2** revisions, tracked in `state.json` under `retries.design_to_review` / `max_retries.design_to_review`.

If a third round of feedback arrives, the orchestrator records the unresolved concerns as a TODO (severity `HIGH`), proceeds to `PLAN` using the most recent recommendation, and says so explicitly in its response — it does not silently drop the feedback, and it does not loop forever.

## Quality Gates

See `skills/quality-gate/SKILL.md` for the formal SPEC → DESIGN and DESIGN → PLAN / DESIGN_REVIEW gate criteria.

## Design Doc Location

`design.md` lives alongside every other agent's notes at `<session-dir>/agent-notes/design.md` — no separate `docs/` convention is introduced. It is committed with the rest of the session directory as part of the audit trail.
