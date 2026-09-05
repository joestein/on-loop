---
name: quality-gate
description: Defines pass/fail criteria for phase transitions in the on-loop pipeline
---

# Quality Gate

This skill defines the quality criteria that must be met before transitioning between phases.

All paths below use `<session-dir>` to refer to the active session directory (e.g., `.on-loop/sessions/20260426_143052_user-management-api/`).

## Gate: SPEC → DESIGN

**Check**: Architect agent notes exist and contain a valid specification.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/architect.md` exists | Yes |
| Specification has functional requirements | Yes |
| Specification has non-functional requirements | Yes |
| Security considerations documented | Yes |
| Architecture diagram present | Recommended |

**On fail**: Cannot proceed. Report to user.

## Gate: DESIGN → PLAN or DESIGN_REVIEW

**Check**: Design agent notes exist with a classification and a recommendation. See `skills/on-loop-design/SKILL.md` for the full mechanics.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/design.md` exists | Yes |
| `## Classification` is `BOUNDED` or `ARCHITECTURAL` | Yes |
| `## Recommended Approach` is non-empty | Yes |
| `## Approval` states `approval_required: true` or `false` | Yes |

**Routing** (not pass/fail — both outcomes are valid):
- `approval_required: false` → transition to `PLAN` automatically
- `approval_required: true` → transition to `DESIGN_REVIEW` and stop; resumes via `/on-loop-resume`

**On fail** (missing notes or missing classification/approval fields): Cannot proceed. Re-dispatch the design agent.

## Gate: DESIGN_REVIEW → PLAN

**Check**: Human has responded to the pause.

| Criteria | Required |
|----------|----------|
| `/on-loop-resume` invoked against the paused session | Yes |
| If `--feedback` given, revision was written and design agent re-run | Yes |

**On approval** (no `--feedback`): proceed to `PLAN` using the existing recommendation.
**On feedback (retries remain)**: transition back to `DESIGN` with the feedback, re-run the design agent (max 2 revisions).
**On feedback (retries exhausted)**: record a `HIGH` TODO with the unresolved feedback, proceed to `PLAN` with the latest recommendation, and say so explicitly.

## Gate: PLAN → CODE

**Check**: Plan is written and actionable.

| Criteria | Required |
|----------|----------|
| `<session-dir>/plan.md` has content | Yes |
| Tasks are listed with assignments | Yes |
| Constraints documented | Yes |

**On fail**: Orchestrator rewrites plan.

## Gate: CODE → TEST

**Check**: Coding agent completed implementation.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/coding.md` exists | Yes |
| Files created/modified listed in `changes.log` | Yes |
| No CRITICAL issues self-reported | Yes |
| Code compiles/parses without errors | Yes |

**On fail**: Cannot proceed. Coding agent must resolve.

## Gate: TEST → SECURITY

**Check**: All tests pass.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/testing.md` exists | Yes |
| All tests pass (zero failures) | Yes |
| Happy path tests exist | Yes |
| Error path tests exist | Yes |

**On fail (retries remain)**: Transition back to CODE with test feedback.
**On fail (retries exhausted)**: Record TODO, proceed to SECURITY.

## Gate: SECURITY → DOC/BUILD

**Check**: No critical security vulnerabilities.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/security.md` exists | Yes |
| No CRITICAL findings | Yes |
| No unmitigated HIGH findings | Yes |
| OWASP Top 10 review completed | Yes |

**On fail (retries remain)**: Transition back to CODE with security findings.
**On fail (retries exhausted)**: Record TODO, proceed to DOC/BUILD.

## Gate: DOC + BUILD → REVIEW

**Check**: Both documentation and build agents completed.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/documentation.md` exists | Yes |
| `<session-dir>/agent-notes/build.md` exists | Yes |
| README exists or was updated | Recommended |
| CI configuration exists | Recommended |

**On fail**: Warn but proceed to REVIEW (doc/build issues are non-blocking).

## Gate: REVIEW → GIT

**Check**: Reviewer approved the code.

| Criteria | Required |
|----------|----------|
| `<session-dir>/agent-notes/reviewer.md` exists | Yes |
| Verdict is `APPROVE` | Yes |
| No CRITICAL issues | Yes |

**On fail (retries remain)**: Transition back to CODE with review feedback.
**On fail (retries exhausted)**: Record TODO, proceed to GIT with warnings.

## Gate: GIT → COMPLETE

**Check**: Git operations completed successfully.

| Criteria | Required |
|----------|----------|
| All changed files staged and committed | Yes |
| Branch pushed to origin | Yes |
| PR created via `gh pr create` | Yes |
| `pr_url` set in `state.json` | Yes |

**On fail**: Report git error to user. The user can retry with `/on-loop-resume --from=GIT`.

## Retry Budget Summary

| Transition | Max Retries | Trigger |
|-----------|-------------|---------|
| DESIGN_REVIEW → DESIGN | 2 | Human-requested revision via `/on-loop-resume --feedback` |
| TEST → CODE | 3 | Test failures |
| SECURITY → CODE | 2 | CRITICAL/HIGH findings |
| REVIEW → CODE | 2 | REQUEST_CHANGES verdict |

Total maximum code iterations: 1 (initial) + 3 + 2 + 2 = **8** (unaffected by design revisions, which happen before CODE starts)

## Exhausted Retry Behavior

When retries are exhausted:
1. Record all unresolved issues as TODOs in `state.json`
2. Log the decision: `[timestamp] orchestrator DECISION retry_exhausted — <details>`
3. Advance to the next phase
4. The COMPLETE summary will prominently display all TODOs
