# Documentation Agent Notes — on-loop-tag Layer 1

## Summary

Created `bin/on-loop-tag.md` (the canonical user manual) and added a `## Safe release tagging` section to `README.md` in the worktree at `.claude/worktrees/on-loop-tag-layer-1/`.

All content was derived from the script itself (`bin/on-loop-tag`, read verbatim), the architect spec (§1–§9), the coding agent notes (deviations D-A through D-H), and the security agent notes (findings F-1 through F-6, per-S verification table). No fields, flags, or behaviours were invented that are not present in the implemented script.

## Decisions

- **Placement of README section.** Inserted `## Safe release tagging` immediately before the `## Agents` table. This keeps it adjacent to the Commands table (where users orient themselves) without burying it in the Architecture section.
- **Audit log examples use full commit SHAs in the schema table, short SHAs in the example lines.** The example lines reproduce the architect §5.3 examples faithfully (which used short SHAs). The schema table notes that `commit` is the "full SHA"; this is accurate per the script (`git rev-parse HEAD`, not `--short`). The discrepancy in the spec examples is inherited, not introduced here.
- **`--check` runs checks 1–7 (not 8).** This matches the coding agent's deviation D-C. The manual documents this truthfully: "Check 8 (`user_confirmed`) is skipped" under `--force`, and the `--check` description says "no tag is created and no audit line is written" without claiming check 8 runs. The reviewer should confirm D-C is accepted behaviour.
- **`script_version: "unknown"` note.** Surfaced in the Security considerations section as directed by security F-4. Explicitly stated it is not evidence of tampering.
- **Layer 1 scope section.** Lists the seven non-goals from architect §1 verbatim, plus the `--reason` policy deferral (OQ-3) to make it easy for Layer 2 engineers to pick up from a known baseline.
- **FAQ item on `+` build metadata.** The Layer 1 semver regex does not include `+build` metadata. Added a FAQ entry because this is a common surprise for engineers familiar with SemVer 2.0.0 full syntax.

## Files Modified

- `bin/on-loop-tag.md` — CREATE — full user manual: synopsis, description, usage (three modes with examples), eight-checks table, exit codes table, audit log (path, format, schema, three example NDJSON lines, jq verification command), `--force` policy, install (symlink vs copy table, verification commands), security considerations (seven items from security notes F-2 F-3 F-4 F-5 + S-4 S-6), failure modes and FAQ (five entries), and Layer 1 scope / non-goals list.
- `README.md` — MODIFY — added `## Safe release tagging` section (after Commands table, before Agents table) with incident motivation paragraph, one-sentence description, mini usage block (three forms), link to `bin/on-loop-tag.md`, and install one-liner.

## Issues Found

- **[INFO] Audit log schema example commit SHAs.** The architect §5.3 example lines use short SHAs (e.g. `fcc59c6`) for the `commit` field, but the script uses `git rev-parse HEAD` (full SHA). The schema table correctly states "full SHA". The example lines reproduce the architect examples to keep documentation reviewable against the spec; the examples are labelled illustrative. If the reviewer wants the examples updated to use full SHAs, that is a trivial change.
- **[INFO] `--check` runs checks 1–7 only.** The manual accurately reflects the coding agent's deviation D-C (interactive check 8 is not run in `--check` mode). The spec text is ambiguous on this point; the architect §2.2 control flow diagram supports the coding agent's interpretation. Reviewer should confirm.
- **[INFO] `jq` not listed in bootstrap dnf packages.** The security agent (Recommendations, BUILD phase item 2) flags that `jq` should be added to the bootstrap `dnf install` list. This is out of documentation scope; flagged here for the build agent.

## Recommendations for Next Agent

- **Reviewer:** confirm that the `--check` mode description (checks 1–7 only, no audit line) matches the accepted interpretation of D-C.
- **Reviewer:** confirm that the `--force` policy section (ADR-007 rationale, mandatory `--reason`, `checks_skipped: ["user_confirmed"]`, audit immutability) accurately characterises the implementation.
- **Build agent:** add `jq` to the Fedora bootstrap `dnf install` line (security agent Recommendation BUILD-2); the bash fallback works but `jq` is the faster, more robust path for JSON encoding of `--reason`.
- **Post-merge (JE):** update Confluence PE/106233857 §3 and the lesson section per the orchestrator's plan.md note. The `bin/on-loop-tag.md` "Description" paragraph is the canonical incident account and can be quoted directly.
