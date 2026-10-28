# Implementation Plan — on-loop-tag Layer 1

Read together with `agent-notes/architect.md` (the authoritative spec). This plan defines ordering, ownership, and acceptance gates per phase. Token names, exit codes, error wording, audit schema, and CLI grammar are normative in the architect spec — do not re-derive them here.

## Branch & worktree

- Branch: `on-loop/on-loop-tag-layer-1`
- Worktree: `.claude/worktrees/on-loop-tag-layer-1/`
- Session: `.on-loop/sessions/20260520_214047_on-loop-tag-layer-1/`

All file operations happen inside the worktree. Agent notes and state live at the repo root.

## Deliverables (single PR)

| Path | Phase / owner | Notes |
|------|---------------|-------|
| `bin/on-loop-tag` | CODE / coding | Executable bash script implementing all 8 checks, `--check`, `--force`, audit log. mode 0755. |
| `bin/on-loop-tag.md` | DOC / documentation | Usage, 8 checks, force policy, audit schema, security notes. |
| `tests/test_on_loop_tag.bats` | TEST / testing | 15 bats cases per architect §7.6. |
| `tests/helpers/git_fixture.bash` | TEST / testing | `setup_temp_repo` / `teardown_temp_repo` / `setup_git_shim`. |
| `setup/fedora-bootstrap.sh` | CODE / coding | Append symlink-install block per architect §6.1; `bats` + `flock` install. |
| `README.md` | DOC / documentation | New `## Safe release tagging` section. |
| `.github/workflows/on-loop-tag.yml` | BUILD / build | Runs bats + shellcheck on push/PR. |
| `.gitignore` | CODE / coding | Add `.on-loop/release-log.json.lock`. |

## Phase plan

### CODE
1. Create `bin/on-loop-tag` per architect §2-§5 (control flow, exit codes, all 8 checks, audit log, `--check`/`--force`).
   - Token names (`semver_format`, `tag_not_exists`, etc.) verbatim.
   - Exit codes 0..9 per §2.3.
   - Audit append uses `flock -x -w 5` + `printf '%s\n' >>`.
   - JSON encoding for `reason` uses `jq -Rs .` if present, else a bash escape helper for `\`, `"`, control chars.
   - TTY override `ON_LOOP_TAG_FORCE_TTY_INPUT` gated on `${BATS_TEST_FILENAME:-}` OR `${BATS_VERSION:-}` (S-5).
   - `umask 022` at start; `trap` on INT/TERM for clean exit 6.
2. Append symlink-install block + bats/flock package add to `setup/fedora-bootstrap.sh` per §6.1.
3. Add `.on-loop/release-log.json.lock` to `.gitignore`.
4. Log every touched file to `changes.log`.

### TEST
1. Create `tests/helpers/git_fixture.bash` per §7.1, §7.2, §7.4, §7.5 (temp repo + bare origin + git shim + divergence helpers).
2. Create `tests/test_on_loop_tag.bats` with the 15 cases from §7.6 — verbatim assertions on exit codes, stderr substrings, tag presence, and jq-parsed audit fields.
3. Run `bats tests/test_on_loop_tag.bats`. All 15 must pass. If any fail, return to CODE with feedback (max 3 retries).

### SECURITY
1. Verify mitigations S-1..S-10 from architect §9.
2. Spot-check: tag name and reason are never interpolated into format strings; reason JSON-encoded with proper escaping; PATH note documented; flock presence checked; TTY override sentinel-gated.
3. CRITICAL/HIGH findings → retry CODE (max 2). Otherwise record TODOs and proceed.

### DOC + BUILD (parallel)
- **DOC**: `bin/on-loop-tag.md` (usage, 8 checks, force, audit schema, security notes, install method trade-off). README `## Safe release tagging` section linking to it.
- **BUILD**: `.github/workflows/on-loop-tag.yml` running `bats tests/test_on_loop_tag.bats` + `shellcheck bin/on-loop-tag` on Ubuntu (with `apt-get install -y bats jq util-linux shellcheck`). Workflow must use `--jobs 1` per OQ-4. Add a Makefile target `make test` that runs the same.

### REVIEW
1. Reviewer verifies acceptance criteria mapping (§10), correctness of all 8 checks vs spec, audit schema completeness, bootstrap install correctness, doc accuracy.
2. REQUEST_CHANGES → retry CODE (max 2).

### CODEX (Path B dual review — orchestrator step, post-REVIEW)
1. Spawn codex:rescue with a review-only prompt: confirm 8 checks correct, audit schema complete, no obvious bash bugs, tests adequate. APPROVE / REQUEST_CHANGES.
2. If REQUEST_CHANGES → log feedback; if blocking, return to CODE.

### GIT
1. Commit explicitly-listed files from `changes.log` + session dir.
2. Commit message summarizes incident motivation + checks + tests + docs + bootstrap.
3. Push `on-loop/on-loop-tag-layer-1`.
4. `gh pr create` with acceptance-criteria checklist in body.

## Non-goals (Layer 2+)

Per architect §1: no GPG provisioning, no release-notes prefill, no Quay trigger, no `--push`, no log rotation, no `--reason` policy regex.

## Outstanding decisions (already resolved by architect)

- Install method: **symlink** (ADR-002).
- Audit path: **`.on-loop/release-log.json`** committed to repo (OQ-1).
- `--check` and `--force` mutually exclusive (ADR-005).
- `--force` runs all checks, converts FAILs to warnings (ADR-007).
- TTY override sentinel-gated (S-5).

## Confluence handoff (post-merge, not in this PR)

Per user prompt: update Confluence PE/106233857 §3 + lesson section. JE will apply manually; orchestrator notes this in PR body under "After merge".
