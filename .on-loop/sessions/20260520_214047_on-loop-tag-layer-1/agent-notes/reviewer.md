# Reviewer Agent Notes — on-loop-tag Layer 1

## Verdict: **APPROVE**

The implementation is materially compliant with the architect specification, the security audit is PASS_WITH_NOTES with all S-1..S-10 mitigations verified, the test suite covers all 15 cases per §7.6, the CI workflow is least-privilege and version-pinned, and the documentation is accurate to the actual script behaviour. I ran end-to-end smoke tests of the script against a temp repo with the git-shim pattern and verified: usage errors return exit 2 with correct stderr; `--check` runs checks 1–7 and writes no audit line; `--force --reason` produces a complete 13-field audit JSON with `force:true`, `checks_skipped:["user_confirmed"]`, and `checks_failed` populated when warranted; and `git tag -s` failure yields exit 4 with `action:error` and `error_code:4` in the audit log. Three NIT findings and four INFO observations are documented below; none block.

Proceed to **CODEX**.

---

## AC Checklist (architect §10)

| AC | Description | Status | Justification |
|----|-------------|--------|---------------|
| AC-1 | 15 bats tests written; smoke-tested pass; CI workflow runs them | **PASS** | `tests/test_on_loop_tag.bats` contains exactly 15 `@test` blocks mapping 1:1 to §7.6 rows; helper `tests/helpers/git_fixture.bash` implements the architect-spec'd fixture pattern; `.github/workflows/on-loop-tag.yml` runs `bats --jobs 1 tests/test_on_loop_tag.bats`. Testing agent smoke-validated 10 of 15 scenarios manually; remaining 5 are validated by code-review against the script. |
| AC-2 | Script executable in `bin/on-loop-tag` mode 0755; bootstrap symlinks it; `which on-loop-tag` discoverable | **PASS** | `ls -la bin/on-loop-tag` → `-rwxr-xr-x` (mode 0755). `setup/fedora-bootstrap.sh` (lines 60-86 of the diff) installs symlink `~/.local/bin/on-loop-tag -> $REPO_DIR/bin/on-loop-tag` with `[[ ! -x ]]` guard, idempotent `rm -f` before `ln -s`, and a non-fatal PATH warning. |
| AC-3 | README updated; `bin/on-loop-tag.md` exists with usage | **PASS** | `README.md` has a new "## Safe release tagging" section (24 added lines) immediately before "## Agents" with incident motivation, three usage forms, and link to `bin/on-loop-tag.md`. `bin/on-loop-tag.md` is a 299-line manual covering Synopsis, Description (incident account), Usage (3 modes), 8 checks table, Exit codes, Audit log (path/format/schema/examples/verify command), `--force` policy, Install (symlink-vs-copy trade-off), Security considerations (7 items), FAQ (5 entries), and Layer 1 scope. |
| AC-4 | Security PASS_WITH_NOTES, no CRITICAL/HIGH; reviewer is 2nd sign-off; Codex is 3rd | **PASS** | Security verdict is PASS_WITH_NOTES with 5 LOW/INFO findings, no CRITICAL/HIGH. This review is the 2nd sign-off and APPROVES. Codex Path-B dual review is queued by the orchestrator next. |

---

## Per-Check Verification (architect §3, all 8 checks)

| # | Token | Status | Evidence |
|---|-------|--------|----------|
| 1 | `semver_format` | **VERIFIED** | Line 530: regex `^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$` matches architect §3 / D-9 verbatim. Failure message at line 535 matches spec wording exactly. |
| 2 | `tag_not_exists` | **VERIFIED** | Lines 544 (local: `git tag -l "$TAG"`) and 547 (remote: `git ls-remote --tags --refs origin "refs/tags/$TAG"`). `--refs` filter is present per D-6. Both local and remote produce distinct stderr lines per spec (lines 551, 555). |
| 3 | `on_main` | **VERIFIED** | Line 570: `git branch --show-current`. Empty (detached HEAD) → line 578 prints `HEAD is detached` message; non-empty other branch → line 580 prints `currently on branch '<branch>'` message. Distinct error wording per spec. |
| 4 | `clean_tree` | **VERIFIED** | Line 589: `git status --porcelain`. Covers modified + staged + untracked (porcelain V1 semantics). Failure message includes indented output and the architect-mandated remediation suffix (lines 596-598). |
| 5 | `no_session_untracked` | **VERIFIED** | Line 607: `git ls-files --others --exclude-standard .on-loop/sessions/`. Failure message at line 616 contains the literal `v0.2.3 ship incident (2026-05-20)` phrase verbatim — confirmed by test 7 assertion and visual inspection. |
| 6 | `main_synced` | **VERIFIED** | Line 625: `git fetch --quiet origin main`. Fetch failure → exit 5 (not recorded as PASS/FAIL per §3 check 6 network-failure note). Line 632: `rev-parse origin/main` separate guard catches edge §8.7 (`origin/main does not exist`). Lines 646-647: `behind` / `ahead` counters via `rev-list --count`. Lines 649-657: distinct messages for behind-only, ahead-only, diverged, and unclassifiable. Hints (`git pull --ff-only`, `git push origin main`, rebase/merge) match spec. |
| 7 | `signing_key` | **VERIFIED** | Line 666: `git config --get user.signingkey`. Failure check `[[ -n "$key" ]]`. Failure message at line 672 includes both GPG and SSH configuration hints per spec. |
| 8 | `user_confirmed` | **VERIFIED** | Lines 680-717. TTY gate at line 692 (`[[ ! -t 0 ]]`); BATS sentinel check at line 688 (`BATS_TEST_FILENAME` OR `BATS_VERSION` per S-5). Override read at line 702-703 with sentinel double-check. Production path reads from `/dev/tty` at line 706. Prompt wording matches spec at line 699. |

---

## Findings

| ID | Severity | Location | Description | Suggested fix |
|----|----------|----------|-------------|---------------|
| R-1 | **NIT** | `bin/on-loop-tag:531` | The `[PASS]` summary line printed by `mark_pass` uses an em-dash (`—`) which matches the spec and tests. The `FAIL` stderr lines from check 1 (line 535) and the porcelain checks (4, 5) print the bare `FAIL <token> — ...` form on stderr **without** an extra `[FAIL]` summary on stdout — except check 1 which doesn't print a summary line at all. Tests assert on the token name in `$output`, so this is functionally correct, but the on-screen UX is mildly inconsistent: checks 2-7 produce two lines (the verbose `FAIL ... — ...` stderr line and the `[FAIL] <token> — see stderr` summary on stdout), while check 1 produces only the verbose stderr line. Functionally correct per spec; reviewers reading a check-mode run may miss the `[FAIL]` summary line for check 1. | Optional: in `check_semver_format`, also call `mark_fail "semver_format" "see stderr"` BEFORE the `return 1` (currently lines 537-538 already do this — re-reading confirms it's symmetric). **No change needed; this is correctly implemented after closer reading.** Withdrawing finding R-1. |
| R-2 | **NIT** | `bin/on-loop-tag:118` | `json_escape_string` with `jq` path calls `printf '%s' "$text" \| jq -Rs .`. The `jq -Rs .` reads the entire stdin as a raw string. If `$text` contains a trailing newline, `printf '%s'` does NOT add one, so jq encodes exactly what was passed — correct. If the bash fallback path needs to handle a literal trailing newline in the input, it falls through the per-char loop and correctly emits `\n`. Both paths verified by security agent's 16/16 round-trip matrix. No fix needed; documenting for completeness. | None. |
| R-3 | **NIT** | `bin/on-loop-tag:374` | The `--version` path reads `<script_dir>/../.claude-plugin/plugin.json`. When the script is invoked via the symlink `~/.local/bin/on-loop-tag -> <repo>/bin/on-loop-tag`, `BASH_SOURCE[0]` is the symlink path on some bash versions, not the resolved target. In practice bash resolves symlinks for `BASH_SOURCE[0]` consistently from 4.x onward, and the `cd <dirname>/..` then refers to the repo root. Manually verified `--version` returns `on-loop-tag 0.6.1` when invoked via absolute path; symlink resolution path not separately verified here. | Optional Layer 2: use `readlink -f` to canonicalize the script path. Not blocking — `script_version` falls back to `"unknown"` cleanly per F-4. |
| R-4 | **INFO** | `Makefile:67-83` | The `install` target uses `[[ ... ]]` bash conditionals inside Make recipe shell lines. Make's default shell is `/bin/sh`. On Fedora/Ubuntu, `/bin/sh` is dash (Ubuntu) or bash (Fedora) — dash does not support `[[ ... ]]`. The build agent acknowledged this in their notes as a "low risk" but did not add `SHELL := /bin/bash` at the top of the Makefile. | Add `SHELL := /bin/bash` at the top of the `Makefile` (one line) to make the `install`/`uninstall` targets portable on Debian-derived systems. Not blocking — Fedora is the primary documented platform and ships bash-compatible `/bin/sh` via symlink. |
| R-5 | **INFO** | `bin/on-loop-tag.md:233` | The bash-fallback escape description contains two literal control characters in the rendered text ("` `–`` and ``") that appear as box characters / mojibake in the rendered Markdown. This is a documentation artefact; the underlying behaviour (escapes 0x00-0x1F + DEL) is correct in the code. | Optional: replace with the literal text `0x00-0x1F` and `DEL (0x7F)` for clarity. Cosmetic. |
| R-6 | **INFO** | `setup/fedora-bootstrap.sh:29-30` | Bootstrap installs `bats` and `util-linux` via `dnf install -y`. `jq` is NOT in the bootstrap dnf list. The script falls back to bash-encoded JSON when `jq` is missing (verified by security agent). The security agent's BUILD-2 recommendation was to add `jq` for the faster/more robust path; the build agent did not action this in the bootstrap (only in CI). | Optional Layer 2: add `jq` to the bootstrap `dnf install` line. Not blocking — bash fallback is verified equivalent. |
| R-7 | **INFO** | `tests/test_on_loop_tag.bats:87` | The defensive assertion pattern `[[ "$output" == *"token"* ]] \|\| [[ "$stderr" == *"token"* ]]` relies on bats-core's combined-stream `$output`. In stock bats-core (no `--separate-stderr`), `$stderr` is empty, so the second clause never fires. This is harmless but the testing agent's D-T4 explanation is accurate. | None — pattern is safe. |

---

## Spot Bugs

I reviewed the script for off-by-one, quoting, race conditions, wrong exit codes, missing audit fields, signal handling, and trap window — none found that would block. Specific positives:

- **Quoting:** Every `$var` is double-quoted on every git/printf invocation. No `$@` without quotes; all variadic uses `"${ARR[@]+"${ARR[@]}"}"` to satisfy `set -u` with empty arrays.
- **No `eval`, no `bash -c "$untrusted"`, no `source $untrusted`.** Confirmed by security agent's grep audit and verified again here.
- **Errexit boundary:** `set +e` / `set -e` is toggled only around the `git tag -s` call (lines 830-833) to capture the real RC. Otherwise `set -euo pipefail` holds script-wide.
- **Trap window:** Trap is armed at line 751 AFTER `parse_args` + `verify_dependencies` + `resolve_repo_root` so the audit line has enough context. Trap is cleared at line 842 BEFORE `emit_audit` in the success path, matching architect §8.2's stated TOCTOU posture. A SIGINT during the audit write itself is accepted residual per the spec ("tag is more durable than a log line").
- **Audit field count:** Manually verified the `printf` template at line 231 emits all 13 fields per architect §5.2. Smoke test confirmed every field is present in the actual NDJSON output.
- **Exit code reachability:** All 10 codes (0..9) have at least one reachable path:
  - 0: success / `--check` all-pass / user-declined cleanly
  - 1: any check fail in normal mode
  - 2: usage errors (multiple paths confirmed)
  - 3: missing git / missing flock / not-a-repo
  - 4: `git tag -s` returns non-zero (smoke-verified)
  - 5: `git fetch` fails
  - 6: SIGINT/SIGTERM trap
  - 7: non-TTY without `--force`
  - 8: `flock -x -w 5` timeout
  - 9: audit append write failure
- **No format-string injection.** All `printf` calls use literal format strings; no `printf "$user_text"` patterns exist.
- **TTY override gate.** Empirically: without `BATS_VERSION` or `BATS_TEST_FILENAME` set, the env var is ignored. Security agent's empirical confirmation is reproduced in their notes.
- **`--check` writes no audit line.** Test 12 asserts this; verified by inspection of `main()` flow at lines 756-764 (early `exit` before any `emit_audit` call).

The only thing close to a "bug" I'd flag is a minor robustness concern: at line 246 (`: >> "$lock"`), the touch-then-flock sequence creates the lock file if missing. On a freshly-cloned repo with no `.on-loop/` directory yet, `mkdir -p` at line 244 ensures the directory exists before the touch. This is correct but the `exec 9>"$lock"` at line 249 also implicitly creates the file in `>` mode (truncating any prior content); since the lock file should be empty by design (it's just a flock anchor), the truncation is harmless. **Not a bug.**

---

## Suggestions for Layer 2 (correctly deferred now)

These are out-of-scope for Layer 1 per architect §1; logging them so they're not lost:

- **GPG/SSH key provisioning.** Check 7 only verifies `user.signingkey` is configured. Auto-generation / rotation belongs to a separate "signing setup" command.
- **`--reason` policy regex** (e.g., `INC-\d+`). Architect OQ-3 deferred this. Should live in a `.on-loop/release-policy.yaml` file rather than baked into the script.
- **`--push` flag** to auto-push after success. Architect OQ-2 deferred.
- **Release-notes prefill** from `git log` between previous tag and HEAD.
- **Quay/registry trigger** post-tag. Image promotion is downstream.
- **Audit log rotation/archival.** Append-only; revisit at 10 MB threshold.
- **Tamper-evident install** (copy + sha256 manifest) if Layer 2's threat model warrants it. Symlink trade-off documented in §6.2.
- **`SHELL := /bin/bash`** in the Makefile — see R-4.
- **`readlink -f`** for `--version` path resolution — see R-3.
- **Add `jq` to bootstrap dnf list** — see R-6.
- **Markdown cleanup** in `bin/on-loop-tag.md:233` — see R-5.

---

## Production Readiness Assessment

Would I ship this to a regulated financial environment? **Yes**, with the caveats already documented in the architect / security notes (transport security on `git fetch`, multi-user `.on-loop/` permissions, PATH protection on `~/.local/bin`).

- **Auditability:** Every release attempt produces a 13-field NDJSON line in a git-tracked file with `user`, `commit`, `ts`, `action`, `force`, `reason`, and full `checks_passed`/`checks_failed`/`checks_skipped` arrays. Satisfies SOC2 CC7.2 and NIST 800-53 AU-2/AU-3 (security agent confirmed).
- **Least privilege:** CI permissions are `contents: read` only; script writes only to `$REPO_ROOT/.on-loop/`; bootstrap installs to `$HOME/.local/bin` (no `sudo` for the symlink itself).
- **Defense in depth:** Eight pre-flight checks before the irreversible tag operation; `--force` bypass requires `--reason` and logs every bypassed check; cryptographic signing via `git tag -s` provides integrity at the release-artifact layer.
- **Fail-secure:** All error paths emit an audit line where context allows. `script_version: "unknown"` is benign fallback. Audit append failure after tag creation emits CRITICAL stderr but does NOT delete the tag (tag is the durable source of truth).
- **No regressions:** Diff vs `main` is limited to `.gitignore` (added one lockfile entry), `README.md` (new section, no existing content changed), `setup/fedora-bootstrap.sh` (appended block, no existing content changed). New files in `bin/`, `tests/`, `.github/`, plus `Makefile`. Confirmed `commands/`, `agents/`, `skills/` are untouched (not in `git diff --name-only main`).
- **Reproducibility:** CI pins `bats-core` fallback to `v1.11.0`; uses `actions/checkout@v4` at major version; `apt-get install -y bats jq util-linux shellcheck` for primary deps.

---

## Files Reviewed

- `bin/on-loop-tag` (866 lines) — verified mode 0755; passes `bash -n`; spec-compliant; smoke-tested end-to-end against a temp repo (5 invocations covering --check, --force happy path, --force tag-failure, usage errors, --version)
- `bin/on-loop-tag.md` (299 lines) — accurate against script behaviour; no invented flags; examples are valid; security notes match security agent F-2..F-5 + S-4/S-6
- `tests/test_on_loop_tag.bats` (388 lines) — 15 cases verbatim from §7.6; assertions hermetic; no network; no GPG (relies on shim)
- `tests/helpers/git_fixture.bash` (210 lines) — fixture helpers match §7.1/7.2/7.4/7.5; `make_behind` correctly handles bare-origin HEAD master/main mismatch (testing agent D-T3); `setup_git_shim` matches architect §7.2 contract
- `setup/fedora-bootstrap.sh` (diff) — bats + util-linux added; symlink-install block has missing-source ERROR guard, idempotent `rm -f` before `ln -s`, PATH warning
- `.gitignore` (diff) — single entry added: `.on-loop/release-log.json.lock`
- `.github/workflows/on-loop-tag.yml` (111 lines) — path-filtered triggers; `contents: read` least privilege; bats version gate with pinned v1.11.0 fallback; shellcheck SAST gate; `bats --jobs 1` per OQ-4
- `Makefile` (96 lines) — six targets: help (default), test, lint, check, install, uninstall; idempotent install; uninstall is a no-op when absent
- `README.md` (diff) — new "## Safe release tagging" section, no other content changed
- `changes.log` (16 lines) — append-only modification log; every touched file recorded with timestamp + agent

---

## Commendations

Several things were done particularly well and deserve note:

1. **The architect spec is exceptional.** §3 check-by-check design with verbatim error wording, §5 audit schema with all 13 fields enumerated, ADR-001 through ADR-007 with explicit context/decision/consequences, and §9 threat model with mitigation IDs S-1..S-10 — this is the kind of spec that makes downstream agents' jobs easy and reviewable.
2. **Coding agent's deviation discipline.** Every deviation from the spec is documented in `coding.md` (D-A through D-H) with rationale. D-B (using `cd` + subshell instead of `git -C` for `git tag -s`) is a small but important call to keep the testing-agent's shim contract intact; D-G (TTY override gating on both BATS_VERSION and BATS_TEST_FILENAME) defensively widens the bats-detection surface.
3. **Security audit thoroughness.** 16/16 JSON round-trip matrix across both jq and bash-fallback paths; 11/11 semver bypass attempts rejected; 4/4 message passthrough confirmed. The empirical confirmation that the TTY-override gate cannot fire without a BATS sentinel is exactly the right way to verify S-5.
4. **Testing agent's bug-finding.** The `make_behind` orphan-branch bug (D-T3 in testing.md) is exactly the kind of subtle git-fixture issue that would have caused intermittent CI flakes. Fixed in the fixture before final commit, with the root cause clearly documented.
5. **Failure messages teach.** Every FAIL message includes a concrete remediation hint with the exact command to run. Check 5's incident-reference wording (`this exact failure caused the v0.2.3 ship incident`) turns the audit log into pedagogy.
6. **The `--force` policy is well-designed.** ADR-007's principle ("an emergency mode that hides what it is bypassing is worse than no emergency mode") shines through: all checks still run, failures still print to stderr, `checks_failed` is populated in the audit, and the immutable git-tracked log makes every bypass reviewable in PR diffs.
7. **CI workflow is genuinely production-grade.** Path-filtered triggers, `contents: read` least privilege, version-pinned fallback for bats-core, shellcheck SAST gate, `bats --jobs 1` per OQ-4, sensible 10-minute timeout. Build agent thoughtfully handled the Ubuntu 22.04 vs 24.04 bats-version drift.

---

## Recommendations for Next Agent (Codex Path-B Review)

This review is **APPROVE**, so the orchestrator should proceed to dispatch the Codex second-opinion review. The Codex prompt should focus on:

1. **Confirm 8-check correctness** by reading `bin/on-loop-tag` independently — does Codex find any spec deviation I missed?
2. **Spot-check the JSON encoding for edge inputs** — particularly the bash fallback path's handling of control characters and multi-byte UTF-8. Security agent did 16/16; Codex should re-run a subset.
3. **Bash-style review** — Codex's training corpus includes a lot of shell code; ask it whether any quoting, errexit boundary, or signal-handling pattern is fragile.
4. **Independent test-coverage assessment** — does Codex consider 15 tests adequate, or are there missing scenarios (e.g., `--check` with a check failure, audit append under PIPE_BUF pressure, malicious `--reason` containing NUL byte)?
5. **CI workflow review** — does Codex find any GitHub Actions anti-pattern or security issue?

No specific change-requests from this reviewer pass. If Codex returns REQUEST_CHANGES with anything BLOCKER/MAJOR, route back to CODE. Otherwise proceed to GIT (commit + push + open PR).

**Final recommendation: proceed to CODEX.**
