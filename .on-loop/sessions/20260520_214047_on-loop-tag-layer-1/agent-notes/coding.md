# Coding Agent Notes — on-loop-tag Layer 1

## Summary

Implemented the Layer 1 deliverables in scope for the CODE phase:

1. `bin/on-loop-tag` (mode 0755) — full implementation of the 8 checks, `--check` and `--force --reason` modes, NDJSON audit log with `flock`, JSON encoding via `jq` (with hand-rolled bash fallback), trap on INT/TERM with audit, all 10 exit codes (0..9), and the spec-mandated stderr wording verbatim.
2. `setup/fedora-bootstrap.sh` — appended the symlink-install block per architect §6.1 (PATH warning, missing-source guard, idempotent `rm -f` before `ln -s`); added `bats` and `util-linux` to the `sudo dnf install -y` package list.
3. `.gitignore` — added `.on-loop/release-log.json.lock`.

## Files Modified

- `bin/on-loop-tag` — CREATE — entry-point bash CLI, ~620 lines including comments
- `setup/fedora-bootstrap.sh` — MODIFY — bats + util-linux dnf install; symlink-install block
- `.gitignore` — MODIFY — release-log.json.lock entry

## Decisions

### D-A (json_array empty handling)

`json_array` is called with `"${CHECKS_PASSED[@]+"${CHECKS_PASSED[@]}"}"` so an empty array yields **no** positional args; the loop simply emits `[]`. Verified with a unit-style smoke test. This is robust under `set -u`.

### D-B (`git tag -s` invocation uses `cd` + subshell, not `git -C`)

The bats shim in architect §7.2 is `if [[ "$1" == "tag" && "$2" == "-s" ]]`. That shim does NOT match `git -C <path> tag -s ...` because `$1` would be `-C`. To make the test fixture work as the architect specified (without forcing the testing agent to write a more complex shim), the actual signing command is executed inside `( cd "$REPO_ROOT" && git tag -s "$TAG" -m "$MESSAGE" )`. All other `git` calls (read-only: rev-parse, status, ls-files, etc.) continue to use `git -C "$REPO_ROOT"`.

This is a small deviation from a literal reading of the spec (which doesn't dictate `git -C` vs `cd`) but it preserves the testing-agent's expected shim contract.

### D-C (`--check` runs checks 1-7, not 1-8)

The orchestrator prompt says "**`--check` mode**: run all 8". The architect §3 check 8 (`user_confirmed`) is the interactive confirmation prompt that reads from `/dev/tty`. Running it in `--check` mode is impossible without TTY interaction in CI and breaks the diagnostic-only semantics of `--check`. The architect §2.2 control flow already routes `--check` to "Print report; exit 0 if all pass else 1" without going through the prompt path. §7.6 test 12 only asserts "runs checks but does not tag even on pass" — no explicit assertion about check 8.

**Decision**: in `--check`, run checks 1-7. Print "all pass" / fail report. No audit line. No prompt.

If the testing agent's test 12 requires check 8 to be in the audit/skipped list under `--check`, I will revisit on retry — the simplest fix is to add `user_confirmed` to `CHECKS_SKIPPED` in `--check` mode, but since no audit line is written in `--check` mode that's moot. The reviewer should confirm this interpretation.

### D-D (audit-log file mode)

`umask 022` enforced at script start → audit log created mode 0644, lock file mode 0644. Multi-user concerns documented in security S-6.

### D-E (signal trap is armed AFTER argv parse but BEFORE checks)

Architect §8.1 says "BEFORE the long-running portion". Argv parsing is non-blocking; the long portion is `run_first_seven_checks` (which includes `git fetch`). The trap is installed immediately after `resolve_repo_root` so:
- A Ctrl-C during checks → emit `action:error, error_code:6` audit, exit 6.
- A Ctrl-C during `git tag -s` → same (trap is still armed).
- The trap is cleared (`trap - INT TERM`) immediately before the audit append for the success case (§8.2).

### D-F (script_version readout)

`SCRIPT_VERSION` is populated once at startup from `<repo-root>/.claude-plugin/plugin.json` via `jq -r .version`. If `jq` is missing OR the file is missing, the field is literal `"unknown"`. The `-V/--version` output uses the same source.

### D-G (TTY override gating)

`ON_LOOP_TAG_FORCE_TTY_INPUT` is only honored when **either** `BATS_TEST_FILENAME` **or** `BATS_VERSION` is set in the environment (architect §7.3 + S-5). Otherwise the override is silently ignored and the `[[ ! -t 0 ]]` check fires (exit 7) outside of `--force`. Verified manually.

### D-H (test fixture needs `.gitignore` for `.on-loop/`)

During smoke-testing I noticed that `clean_tree` and `no_session_untracked` will flag the runtime-created `.on-loop/release-log.json` if the test repo doesn't ignore `.on-loop/`. The testing-agent fixture (per architect §7.1) initializes a clean repo with `README.md`; the helper should also commit a `.gitignore` that includes `.on-loop/` OR commit an empty `.on-loop/.gitkeep` before invoking the script. Flagged for testing agent.

## Issues Found

- **[INFO] `git tag -s` shim contract** — see D-B above. Testing agent needs to use `cd` + invoke (or accept that my script `cd`s to repo root before calling `git tag -s`). My implementation matches their architect-spec'd shim.
- **[INFO] `.on-loop/` cleanliness in test fixture** — see D-H. The fixture must avoid having `.on-loop/release-log.json` flagged by `clean_tree` / `no_session_untracked`. Easiest: `.gitignore` it in the fixture's initial commit.
- **[LOW] `--check` semantics** — see D-C. I run checks 1-7 only in `--check`, skipping the interactive prompt. The spec is ambiguous but my interpretation matches the §2.2 control-flow diagram. Reviewer to confirm.

## Self-validation

- `bash -n bin/on-loop-tag` — passes.
- Manual smoke test in a temp repo with the architect's `git tag -s` shim:
  - `--check` with all-pass → exit 0, no audit line written.
  - `--check` with bad semver → exit 1, FAIL semver_format on stderr.
  - `--force --reason "smoke"` → exit 0, tag created, audit line has `force:true`, all 7 checks_passed, `user_confirmed` in `checks_skipped`.
  - Bats-mode prompt yes (`BATS_VERSION=1.0 ON_LOOP_TAG_FORCE_TTY_INPUT=y`) → exit 0, all 8 in `checks_passed`, audit line clean.
  - Bats-mode prompt no (`...INPUT=n`) → exit 0, audit line `action:refused, refused_reason:user_declined`, `checks_failed:[]`.
  - Normal mode, dirty tree → exit 1, audit line `action:refused, refused_reason:checks_failed, checks_failed:[clean_tree]`.
  - No TTY without `--force` → exit 7, exact stderr per spec.
  - Local tag exists → FAIL tag_not_exists with exact wording.
  - `--check` + `--force` → exit 2, "mutually exclusive" stderr.
  - `--force` without `--reason` → exit 2, `--force requires --reason "<text>"` stderr.
  - `--reason` without `--force` → exit 2, "only valid with --force" stderr.
  - `--unknown` → exit 2, "unknown option" stderr.
  - Empty `-m` → exit 2, "must not be empty" stderr.
  - Reason with double-quotes / backslashes / newlines / tabs → JSON-encoded correctly via `jq -Rs .`, round-trip parses back.

- shellcheck not installed in this environment; cannot statically verify. Script is written to be shellcheck-clean (no `[ ]`, no backticks, all variable expansions quoted, arrays for variadic args, no `eval`, no untrusted `bash -c`). The build agent will wire `shellcheck bin/on-loop-tag` into CI; if it surfaces warnings, those will come back as a retry.

## Remediation Notes

(No prior agent feedback — this is the first CODE pass.)

## Remediation (Retry 1) — codex Path-B REVIEW review

Codex dual-review surfaced three blocking bugs in `bin/on-loop-tag` and four non-blocking fixes in the surrounding files. All applied surgically — no refactors, no token/grammar/exit-code/schema changes.

### Feedback Addressed

#### B1 — Fetch-failure must emit an audit line

**Old behavior:** `check_main_synced` called `exit "$E_FETCH_FAILED"` directly inside the function when `git fetch origin main` failed. No audit line was emitted. This violated architect §5.5 invariant "every post-parse outcome produces one NDJSON line".

**New behavior:**
- `check_main_synced` no longer exits on fetch failure. It appends `main_synced:fetch_failed` to `CHECKS_SKIPPED` (B1 convention choice — see below), sets the new global `FETCH_FAILED=1`, and returns 1 to the caller.
- A new `FETCH_FAILED=0` global declared near the other check-accounting arrays.
- In `--check` mode, the orchestrator checks `FETCH_FAILED` first and exits 5 with no audit (consistent with --check's "no audit" semantics).
- In normal mode, the orchestrator prints `Error: could not fetch from origin; aborting (no tag created)`, then emits `action:error, force:false, refused_reason:null, error_code:5` via the new `emit_audit_or_die` helper, then exits 5.
- In `--force` mode, the orchestrator prints `WARNING: --force is bypassing fetch failure (main_synced:fetch_failed); proceeding because --reason was supplied`, then continues into `do_tag_and_audit "true" "$REASON"`. The audit line then naturally carries `checks_skipped:["main_synced:fetch_failed","user_confirmed"]` along with `force:true, reason:"<text>"`. This honors the user's explicit bypass.

**Convention choice (B1 - documented):** I chose `CHECKS_SKIPPED+=("main_synced:fetch_failed")` (record under skipped with the `<token>:<reason>` suffix) over `CHECKS_FAILED`. Rationale: a network failure is not a check verdict; it is an inability to evaluate the check. This matches `checks_skipped`'s semantic ("auto-skipped tokens"). Tokens in `checks_passed`/`checks_failed` are never qualified with a colon-suffix in the existing code, so the `main_synced:fetch_failed` form is distinguishable and machine-parseable. Verified via smoke test that the audit line schema remains valid.

#### B2 — Re-verify tag_not_exists immediately before `git tag -s`

**Old behavior:** Between check 2 and the `git tag -s` invocation a concurrent push from another shell could land, causing the tag to overwrite a published ref (architect §8.6 caveat).

**New behavior:** New `perform_race_recheck` function. Called inside `do_tag_and_audit` between `set +e` and the `( cd ... && git tag -s ... )` subshell. It re-runs both `git tag -l "$TAG"` (local) and `git ls-remote --tags --refs origin "refs/tags/$TAG"` (remote). On collision:
- Prints `ERROR: tag '<TAG>' was created concurrently between pre-flight check and tag invocation; aborting` to stderr.
- Resets `CHECKS_FAILED=("tag_not_exists")` so the audit line clearly attributes the refusal to the race (even if the original check 2 had passed).
- Calls `emit_audit_or_die "refused" "$force_str" "$reason_str" "race_detected" "" "$E_CHECK_FAIL"`.
- Exits 1 (or 8/9 if audit-append fails per B3).

**`--force` does NOT bypass race-detection.** This is a correctness issue (we must never overwrite a published tag), not a bypass-able policy. The recheck runs the same way in both modes.

#### B3 — Refusal audit failures must surface

**Old behavior:** Refusal-path `emit_audit` calls were guarded with `|| true`, silently dropping audit-append failures (lock timeout, disk full, perms denied) and exiting with the original refusal code (0 or 1). This violated the success-path symmetry (where audit failure surfaces as exit 8 or 9).

**New behavior:** Introduced helper `emit_audit_or_die <action> <force> <reason> <refused_reason> <error_code> <fallback_exit_code>` that:
- Calls `emit_audit` and captures the exit code.
- On success (audit_rc == 0): exits `<fallback_exit_code>`.
- On audit-append failure: prints `CRITICAL: failed to write audit line for <action> outcome — manual reconciliation needed (audit_rc=<N>)` to stderr.
- Exits `$E_LOCK_TIMEOUT` (8) if audit_rc == 8, else `$E_AUDIT_FAILED` (9).

All four refusal/error audit emissions now go through this helper:
1. `refused, checks_failed` → fallback exit 1.
2. `refused, user_declined` → fallback exit 0.
3. `error, error_code:5` (fetch failure normal mode) → fallback exit 5.
4. `error, error_code:4` (`git tag -s` failed) → fallback exit 4.
5. `refused, race_detected` (B2) → fallback exit 1.

The success-path `do_tag_and_audit` keeps its existing `audit_rc=$?` capture and case-handling (unchanged) since it already had this behavior. The INT/TERM signal trap (`audit_error_signal`) keeps its `|| true` — we are already in a fatal-signal teardown, and re-raising audit errors there would mask the original signal exit code.

#### N1 — NUL/control bytes in `bin/on-loop-tag.md` line 233

Replaced `(including \`<0x00>\`–\`<0x1F>\` and \`<0x7F>\`)` (literal control bytes — caused `file(1)` to report the file as `data` and made `rg`/`grep` skip it) with `(including \`0x00\`–\`0x1F\` and DEL \`0x7F\`)`. Verified via Python byte-scan: no bytes in 0..31 (excluding `\t`/`\n`) and no `\x7F` remain. `file bin/on-loop-tag.md` now reports `UTF-8 Unicode text, with very long lines` (no longer `data`).

#### N2 — `SHELL := /bin/bash` in Makefile

Added `SHELL := /bin/bash` near the top of `Makefile` with a comment explaining why (the `install`/`uninstall` recipes use `[[ -x ... ]]` and `[[ -L ... || -e ... ]]` which dash does not implement). Distros where `/bin/sh` is `dash` (Debian/Ubuntu) would otherwise silently fail with `[[: not found`.

#### N3 — CI workflow path filters

Added `bin/on-loop-tag.md`, `Makefile`, and `.gitignore` to both `on.push.paths` and `on.pull_request.paths` in `.github/workflows/on-loop-tag.yml`. Previously, edits to those files would not trigger CI even though they are part of the on-loop-tag deliverable.

#### N4 — `--help` clarifies that `--check` skips check 8

`print_help` text for `--check` was:
> `--check           Run all 8 checks and report; do not tag. No audit line.`

Updated to:
> `--check           Run the first 7 checks (skips check 8, the interactive confirmation) and report. Does not create a tag and writes no audit line. Exit 0 if all 7 pass, else 1.`

Also updated `bin/on-loop-tag.md` "Check mode" section to read "Run the first 7 checks ... `--check` skips check 8 (the interactive confirmation prompt) ..." and the exit code line to "Exit code is 0 if all 7 checks pass, 1 if any fail."

### Unresolved

(None.)

### Smoke-test results (RETRY-1)

All ran from a freshly-created temp repo with a deliberately broken `origin` pointing at a non-existent path:

| Scenario | Expected exit | Observed | Audit line emitted? |
|----------|--------------:|---------:|---------------------|
| `--version` | 0 | 0 | n/a |
| `--help` | 0 | 0 (new wording present for `--check`) | n/a |
| `--force` (no TAG, no -m, no --reason) | 2 | 2 ("TAG is required") | n/a (parse-error) |
| `v0.0.1 -m x --force` (no --reason) | 2 | 2 (`--force requires --reason "<text>"`) | n/a (parse-error) |
| Normal mode, `git fetch` fails | 5 | 5 | yes — `action:error, error_code:5, checks_skipped:["main_synced:fetch_failed"]` |
| `--check` mode, `git fetch` fails | 5 | 5 | no (per --check semantics) |
| `--force --reason "ci-emergency"`, `git fetch` fails | 4 (because shim path quirk caused real GPG failure) | 4 | yes — `action:error, error_code:4, force:true, reason:"ci-emergency", checks_skipped:["main_synced:fetch_failed","user_confirmed"]` — confirms --force bypassed fetch failure and proceeded into tag attempt (and B3 worked: the error_code:4 audit was emitted despite the new emit_audit_or_die path) |

`bash -n bin/on-loop-tag` — passes.

### Files modified (RETRY-1)

- `bin/on-loop-tag` — B1, B2, B3, N4
- `bin/on-loop-tag.md` — N1, N4
- `Makefile` — N2
- `.github/workflows/on-loop-tag.yml` — N3

## Remediation (Retry 2) — codex verification pass

Codex's RETRY-1 re-verification surfaced two surgical bugs (one I introduced in RETRY-1, one pre-existing). Both fixed without refactor.

### Feedback Addressed

#### Issue 1 — `perform_race_recheck` swallowed `ls-remote` failure

**Old behavior (RETRY-1 regression):** Both the local `git tag -l "$TAG"` and the remote `git ls-remote --tags --refs origin "refs/tags/$TAG"` calls used `|| true`. A network failure (auth denied, DNS, transient outage, etc.) would empty `remote_exists`, which the subsequent `[[ -n "$local_exists" || -n "$remote_exists" ]]` test reads as "no tag present" — letting the script proceed into `git tag -s` without confirming the remote ref is absent. This nullifies the race recheck under exactly the conditions where it matters most.

**New behavior:** Capture both stderr and exit code explicitly:
- `local_err=$(git -C "$REPO_ROOT" tag -l "$TAG" 2>&1 >/dev/null) || local_rc=$?` followed by the actual value query (still `|| true` for the value, but `local_rc` is set).
- Same pattern for `remote_err` / `remote_rc` against `git ls-remote`.
- On non-zero exit code (either local or remote): print spec-mandated stderr `ERROR: cannot verify remote tag absence before signing (ls-remote failed); aborting to prevent unverified tag creation` followed by the underlying git stderr on an indented continuation line, set `CHECKS_FAILED=("tag_not_exists")` (for clear attribution), call `emit_audit_or_die "refused" "$force_str" "$reason_str" "race_recheck_failed" "" "$E_FETCH_FAILED"`.
- Applies in BOTH normal and `--force` modes (same correctness-not-policy reasoning as the actual race detection: if we cannot confirm the remote ref is absent, we must refuse — even an explicit operator bypass cannot make an uncertain state safe).
- Exit code 5 (`E_FETCH_FAILED`) — same as a regular fetch failure, since this is the same class of error (cannot reach/verify remote).

The audit line for the race-recheck-failed path produces:
```
{"...","action":"refused","force":<bool>,"reason":<reason-or-null>,"checks_passed":[<7 tokens>],"checks_failed":["tag_not_exists"],"checks_skipped":["user_confirmed"|...],"refused_reason":"race_recheck_failed","error_code":null,"script_version":"..."}
```

Note: `error_code` is `null` in the audit despite the process exit code being 5. This follows the existing convention from the architect spec §5.5 — `error_code` is only populated for `action:error`; `action:refused` carries its cause in `refused_reason`. Same as `race_detected`, `checks_failed`, `user_declined`. The process exit code (5) is the operationally meaningful signal here; the audit captures the cause.

#### Issue 2 — `check_user_confirmed` no-TTY exit 7 bypassed audit emit

**Old behavior (pre-existing):** When stdin is not a TTY and `--force` is not set, `check_user_confirmed` printed the stderr error and called `exit "$E_NO_TTY"` directly — no audit line. This violated architect §5.5's invariant that every post-argv-parse outcome must produce one NDJSON line. RETRY-1 fixed this for `git tag -s` failure (B3) but missed the no-TTY path.

**New behavior:** Inside the `[[ ! -t 0 ]]` branch, after the stderr print:
- Append `"user_confirmed:no_tty"` to `CHECKS_SKIPPED` (using the same `<token>:<reason>` colon-suffix convention introduced for `main_synced:fetch_failed` in B1).
- Call `emit_audit_or_die "error" "false" "" "no_tty" "$E_NO_TTY" "$E_NO_TTY"`.
- This routes through the existing helper, so audit-append failures (lock timeout, disk full, perms) still surface as exit 8/9 — consistent with the success path and B3.

The audit line for the no-TTY path produces:
```
{"...","action":"error","force":false,"reason":null,"checks_passed":["semver_format","tag_not_exists","on_main","clean_tree","no_session_untracked","main_synced","signing_key"],"checks_failed":[],"checks_skipped":["user_confirmed:no_tty"],"refused_reason":"no_tty","error_code":7,"script_version":"..."}
```

All 7 pre-flight checks ran and passed (this branch is only reachable after `run_first_seven_checks` succeeded with `${#CHECKS_FAILED[@]} == 0`); the only "skip" is the interactive prompt itself, marked with the `:no_tty` suffix.

`--force` mode is unaffected (the no-TTY branch is inside `check_user_confirmed`, which `--force` does not call — `--force` skips the prompt by adding `user_confirmed` to `CHECKS_SKIPPED` and going straight to `do_tag_and_audit`).

### Unresolved

(None.)

### Smoke-test results (RETRY-2)

All three scenarios run from a freshly-built temp repo with the architect's `git tag -s` shim and `.on-loop/` gitignored:

| Scenario | Expected | Observed exit | Audit line emitted? |
|----------|---------:|--------------:|---------------------|
| Pipe-input (no TTY), no `--force`, `v9.9.9 -m '...'` | 7 + audit | 7 | yes — `action:error, error_code:7, refused_reason:"no_tty", checks_passed:[all 7], checks_failed:[], checks_skipped:["user_confirmed:no_tty"]` |
| Pipe-input WITH `--force --reason 'ci-emergency-smoke'` | 0 + tagged | 0 | yes — `action:tagged, force:true, reason:"ci-emergency-smoke", checks_skipped:["user_confirmed"]` (no `:no_tty` suffix — --force never hits the TTY check) |
| Race-recheck `ls-remote` failure under `--force --reason 'race-test'` | 5 + refused | 5 | yes — `action:refused, force:true, reason:"race-test", refused_reason:"race_recheck_failed", checks_failed:["tag_not_exists"]` — confirms --force does NOT bypass the race-recheck-failure refusal |

`bash -n bin/on-loop-tag` — passes.

Existing RETRY-1 invariants verified intact (re-ran key cases):
- `--check` mode still exits 0/1 with no audit line.
- `--force --reason` happy path still produces `action:tagged, force:true`.
- Fetch failure in normal mode still emits `action:error, error_code:5, checks_skipped:["main_synced:fetch_failed"]` and exits 5.

### Files modified (RETRY-2)

- `bin/on-loop-tag` — Issue 1 (perform_race_recheck error handling), Issue 2 (check_user_confirmed audit emit on no-TTY)

No other files touched. CI workflow, Makefile, docs, tests, bootstrap are unchanged per orchestrator directive.

## Recommendations for Next Agent

### Testing agent

1. **Fixture must `.gitignore` `.on-loop/`** OR ensure no `.on-loop/release-log.json` exists at check time. Otherwise `clean_tree` and `no_session_untracked` will FAIL because the audit log itself is untracked.
2. The bats `git tag -s` shim from architect §7.2 works with my script (verified) — my script invokes `( cd "$REPO_ROOT" && git tag -s ... )` so the shim's naive `$1==tag && $2==-s` match holds.
3. The `ON_LOOP_TAG_FORCE_TTY_INPUT` override gate honors both `BATS_TEST_FILENAME` and `BATS_VERSION`. Most bats versions set both; either is sufficient.
4. Test 15 ("audit log line is valid JSON with all required fields"): my output passes `jq -e '.schema_version==1 and .ts and .user and .tag and .action and (.force | type=="boolean")'` — confirmed in smoke test.
5. For test 7 (`v0.2.3 ship incident`) — the exact phrase is in the `no_session_untracked` failure message: `this exact failure caused the v0.2.3 ship incident (2026-05-20)`.
6. For test 8 (`behind`) and test 9 (`ahead`), the stderr will contain `behind origin/main` / `ahead of origin/main` respectively, with the exact remediation hints.
7. Test 11 (user declines): the script exits 0 (not 1) per architect §4.4 row 2.

### Security agent

Focus areas (architect §9, mitigations S-1 through S-10):
- **S-1 (tag injection)**: `$TAG` is always passed as a positional arg to git via `"$TAG"`. The semver regex (check 1) restricts to `[A-Za-z0-9.-]`. No interpolation into format strings.
- **S-2 (reason injection)**: `json_escape_string` uses `jq -Rs .` when available; the bash fallback escapes `\` → `\\`, `"` → `\"`, then iterates code points to handle 0x00-0x1F and DEL via `\uXXXX`. Verified with backslash, double-quote, newline, tab inputs round-tripping through `jq -r .reason`.
- **S-5 (TTY override)**: gate is `[[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" ]]`. Without either, env var is ignored.
- **S-7 (flock check)**: `command -v flock` is verified at startup; exit 3 with clear message if missing.
- **S-8 (signal/TOCTOU)**: `trap - INT TERM` is set immediately before audit append in the success path. The window is ~one `printf` syscall after `git tag -s` returns.
- **No `eval`, no `bash -c "$x"` with untrusted input** — confirmed.

### Documentation agent

- Audit schema reference: §5.2 of architect notes. All 13 fields are always emitted; empty arrays as `[]`, missing strings as JSON `null` (not the string `"null"`).
- Force-policy summary: `--force` requires `--reason "<text>"`; runs all 7 pre-flight checks (1-7); skips check 8 (the prompt); records `user_confirmed` in `checks_skipped`; failed checks become warnings; tag is still created.
- Symlink-install trade-off table: §6.2.
- Security note: document the multi-user `.on-loop/` permissions caveat (S-6).
- Exit codes: list all 10 (0..9) with their meanings (§2.3).

### Build agent

- The CI workflow should install `bats jq util-linux shellcheck` on Ubuntu before running.
- `shellcheck bin/on-loop-tag` should be clean — flag any warnings back to me.
- `bats tests/test_on_loop_tag.bats --jobs 1` per architect OQ-4.
- `Makefile` target `test`: `bats tests/test_on_loop_tag.bats`.

### Reviewer agent

Acceptance criteria mapping (architect §10):
- **AC-2 (executable & installed)**: `bin/on-loop-tag` mode 0755; bootstrap installs symlink to `~/.local/bin/on-loop-tag` and warns on PATH.
- Verify all 8 check token names are the literal strings: `semver_format`, `tag_not_exists`, `on_main`, `clean_tree`, `no_session_untracked`, `main_synced`, `signing_key`, `user_confirmed`.
- Verify all 10 exit codes 0..9 are reachable from at least one code path.
- Verify the audit line schema includes all 13 fields verbatim.
- Verify `set -euo pipefail`, `IFS=$'\n\t'`, `umask 022` are at the top.
- Verify the `[[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" ]]` sentinel gate on the TTY override.
