# on-loop-tag

Safe, audited release tagging for the on-loop plugin.

---

## Synopsis

```
on-loop-tag <TAG> -m <MESSAGE>
on-loop-tag <TAG> -m <MESSAGE> --check
on-loop-tag <TAG> -m <MESSAGE> --force --reason "<TEXT>"
```

---

## Description

`on-loop-tag` creates a signed annotated tag (`git tag -s`) only after eight pre-flight checks all pass. Every invocation — success, refusal, or emergency bypass — is written as a structured NDJSON line to `.on-loop/release-log.json`, which is committed to git as an immutable audit trail.

The script exists because of the 2026-05-20 v0.2.3 ship incident: untracked `.on-loop/sessions/` files caused `git pull` to abort silently (git refuses to overwrite untracked paths), leaving the local branch one commit behind `origin/main`. The developer did not notice, ran the tag command, and `v0.2.3` was signed against the previous release's commit. The Quay image for v0.2.3 therefore contained v0.2.2 code. Layer 1 makes that failure mode unreachable under the default workflow — check 5 (`no_session_untracked`) and check 6 (`main_synced`) together catch the exact precondition — and the only escape hatch is an audited, reason-bearing `--force` that is visible in every subsequent `git log` and PR review.

---

## Usage

### Normal mode (all eight checks must pass)

Run the checks, display the target commit, and prompt for confirmation before tagging:

```bash
on-loop-tag v0.6.2 -m "release: v0.6.2"
```

Example session output:

```
[PASS] semver_format — tag 'v0.6.2' matches vMAJOR.MINOR.PATCH[-PRERELEASE]
[PASS] tag_not_exists — tag 'v0.6.2' is unused locally and on origin
[PASS] on_main — current branch is main
[PASS] clean_tree — working tree is clean
[PASS] no_session_untracked — no untracked on-loop session files
[PASS] main_synced — local HEAD == origin/main
[PASS] signing_key — user.signingkey is configured
About to tag v0.6.2 at fcc59c6
  fcc59c6 chore: release prep
Proceed? [y/N] y

Created v0.6.2. Next: git push origin v0.6.2
```

### Check mode (dry run — no tag, no audit line)

Run the first 7 checks and print a report. `--check` skips check 8 (the interactive confirmation prompt), does not create a tag, and writes no audit line. Useful for CI gating and pre-flight verification:

```bash
on-loop-tag v0.6.2 -m "release: v0.6.2" --check
```

Exit code is 0 if all 7 checks pass, 1 if any fail.

### Force mode (emergency bypass — all checks still run)

For genuine emergencies only. All eight checks still run; failures become warnings rather than errors. Requires `--reason`. The tag is created and the audit log records every bypassed check:

```bash
on-loop-tag v0.6.2 -m "hotfix: critical prod regression" \
  --force --reason "CI infrastructure down, hotfix for prod outage INC-4892"
```

The `--reason` text is logged immutably. It is visible in every `git log --follow .on-loop/release-log.json` and in the PR diff.

Pre-release tags (e.g., `v0.7.0-rc1`) work identically across all three modes.

---

## The eight checks

Checks run in this exact order. All eight run every time (no short-circuit) to give the complete picture. Under `--force`, failures become warnings; check 8 is skipped (auto-pass, recorded in `checks_skipped`).

| # | Token | What it verifies | Failure remediation hint |
|---|-------|-----------------|--------------------------|
| 1 | `semver_format` | Tag matches `^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$` | Use a valid version like `v0.6.2` or `v0.7.0-rc1` |
| 2 | `tag_not_exists` | Tag does not exist locally (`git tag -l`) or on origin (`git ls-remote --tags --refs`) | Delete the local tag with `git tag -d <TAG>` if intentional; never move a published tag |
| 3 | `on_main` | `git branch --show-current` returns `main` | Run `git checkout main`; detached HEAD is also rejected |
| 4 | `clean_tree` | `git status --porcelain` is empty (covers modified, staged, and untracked files) | Commit, stash, or discard changes first |
| 5 | `no_session_untracked` | `git ls-files --others --exclude-standard .on-loop/sessions/` is empty | Remove stale session directories with `rm -rf .on-loop/sessions/<dir>` or commit them — this is the exact check that would have caught the v0.2.3 incident |
| 6 | `main_synced` | `git fetch origin main` succeeds and local HEAD equals `origin/main` | Behind: `git pull --ff-only` (resolve untracked files first); ahead: `git push origin main`; diverged: rebase or merge |
| 7 | `signing_key` | `git config --get user.signingkey` is non-empty | Configure with `git config --global user.signingkey <key-id>` (GPG) or `git config --global user.signingkey ~/.ssh/id_ed25519.pub` and `git config --global gpg.format ssh` (SSH) |
| 8 | `user_confirmed` | Operator reads the target SHA and subject line and types `y` | Answer `y` to proceed; any other input aborts cleanly with exit 0 |

Check 6 network cost (~500 ms–2 s) is the only blocking I/O. All other checks complete in well under 100 ms.

Full design rationale for each check is in the session spec: `.on-loop/sessions/20260520_214047_on-loop-tag-layer-1/agent-notes/architect.md §3`.

---

## Exit codes

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `E_OK` | Tag created; or `--check` all-pass; or user declined cleanly at the prompt |
| 1 | `E_CHECK_FAIL` | One or more pre-flight checks failed (non-force mode) |
| 2 | `E_USAGE` | Bad CLI arguments (missing flags, unrecognised options, `--force` without `--reason`, etc.) |
| 3 | `E_NO_REPO` | Not inside a git repository, or a required dependency (`git`, `flock`) is missing |
| 4 | `E_GIT_TAG_FAILED` | `git tag -s` itself failed (GPG agent unavailable, key mismatch, etc.) |
| 5 | `E_FETCH_FAILED` | `git fetch origin` failed (network error); `main_synced` is recorded as neither PASS nor FAIL |
| 6 | `E_SIGNAL_INT` | Interrupted by SIGINT or SIGTERM; an error audit line is emitted and no tag is created |
| 7 | `E_NO_TTY` | Interactive confirmation required but stdin is not a TTY; use `--force --reason` to bypass |
| 8 | `E_LOCK_TIMEOUT` | Audit-log lock (`flock -x -w 5`) could not be acquired within 5 seconds |
| 9 | `E_AUDIT_FAILED` | Tag was created but audit-log append failed; manual reconciliation of `.on-loop/release-log.json` is needed — **do not delete the tag** |

---

## Audit log

### Path and format

`.on-loop/release-log.json` — NDJSON (one JSON object per line, newline-terminated), UTF-8, no BOM.

The file is tracked in git. The lock file `.on-loop/release-log.json.lock` is gitignored (runtime artifact).

Writes are serialized with `flock -x -w 5` on the lock file. `--check` mode and argv-parse errors do not write audit lines.

### Schema (v1)

Every line contains these 13 fields:

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | integer | Always `1` for Layer 1 |
| `ts` | string (ISO 8601 UTC) | Timestamp of the invocation |
| `user` | string | `id -un` (login name); see PII note below |
| `tag` | string | The requested tag name (logged even on refusal) |
| `commit` | string or null | For `action: tagged`, the tag's commit-target (`git rev-parse "<tag>^{commit}"`) — i.e. the SHA the tag actually points at. For refusals and errors, the SHA of HEAD at audit-emit time. Null if no repo context. |
| `action` | string enum | `tagged` / `refused` / `error` |
| `force` | boolean | `true` if `--force` was set |
| `reason` | string or null | Non-null only when `force` is `true`; JSON-encoded |
| `checks_passed` | array of strings | Tokens that passed (empty array if checks not reached) |
| `checks_failed` | array of strings | Tokens that failed (empty array if none) |
| `checks_skipped` | array of strings | Tokens auto-skipped (e.g. `user_confirmed` under `--force`) |
| `refused_reason` | string or null | Present when `action` is `refused`: `checks_failed` / `user_declined` / `race_detected` / `race_recheck_failed` / `head_moved` / `argv_error` |
| `error_code` | integer or null | Present when `action` is `error`; matches exit code |
| `script_version` | string | From `.claude-plugin/plugin.json`; `"unknown"` if file or `jq` is unavailable (see Security notes) |

### Example lines

**Success:**

```json
{"schema_version":1,"ts":"2026-05-20T20:34:46Z","user":"jekavara","tag":"v0.6.2","commit":"fcc59c6a3b1d2e4f5a6b7c8d9e0f1a2b3c4d5e6f","action":"tagged","force":false,"reason":null,"checks_passed":["semver_format","tag_not_exists","on_main","clean_tree","no_session_untracked","main_synced","signing_key","user_confirmed"],"checks_failed":[],"checks_skipped":[],"refused_reason":null,"error_code":null,"script_version":"0.6.1"}
```

**Refusal — user declined at the prompt:**

```json
{"schema_version":1,"ts":"2026-05-20T20:35:01Z","user":"jekavara","tag":"v0.6.2","commit":"fcc59c6a3b1d2e4f5a6b7c8d9e0f1a2b3c4d5e6f","action":"refused","force":false,"reason":null,"checks_passed":["semver_format","tag_not_exists","on_main","clean_tree","no_session_untracked","main_synced","signing_key"],"checks_failed":[],"checks_skipped":[],"refused_reason":"user_declined","error_code":null,"script_version":"0.6.1"}
```

**Force bypass with one failed check:**

```json
{"schema_version":1,"ts":"2026-05-20T20:36:11Z","user":"jekavara","tag":"v0.6.2","commit":"abc1234def567890abc1234def567890abc12345","action":"tagged","force":true,"reason":"CI infrastructure down, hotfix for prod outage INC-4892","checks_passed":["semver_format","tag_not_exists","on_main","no_session_untracked","main_synced","signing_key"],"checks_failed":["clean_tree"],"checks_skipped":["user_confirmed"],"refused_reason":null,"error_code":null,"script_version":"0.6.1"}
```

Verify any line with:

```bash
tail -1 .on-loop/release-log.json | jq -e '.schema_version == 1 and .ts and .user and .tag and .action and (.force | type == "boolean")'
```

---

## `--force` policy

`--force` is an emergency bypass. Its design follows ADR-007: _an emergency mode that hides what it is bypassing is worse than no emergency mode._

Key properties:

- **`--reason` is mandatory.** `--force` without `--reason` exits with code 2 (usage error). The reason is free-text with no minimum length or pattern in Layer 1; Layer 2 may add a ticket-ID regex requirement.
- **All checks still run.** Failed checks print as warnings to stderr but do not block the tag.
- **Check 8 (`user_confirmed`) is skipped.** Recorded in `checks_skipped` as `user_confirmed`. No prompt is shown.
- **Every bypassed check is logged.** The `checks_failed` field in the audit line contains the exact list of tokens that failed, and `force: true` makes the bypass visible.
- **The audit log is git-tracked.** `.on-loop/release-log.json` is committed to the repository. Any `--force` invocation is visible in PR diffs and `git log`.

`--check` and `--force` are mutually exclusive (exit 2 if combined). If you want a dry run, use `--check`; if you need an emergency bypass, use `--force`. They serve different purposes and combining them is treated as a usage error.

---

## Install

### How it is installed

`bin/on-loop-tag` ships in the repository at `bin/on-loop-tag`. `setup/fedora-bootstrap.sh` creates a symlink:

```
~/.local/bin/on-loop-tag -> <repo>/bin/on-loop-tag
```

After running the bootstrap script, verify with:

```bash
which on-loop-tag
# expected: /home/<user>/.local/bin/on-loop-tag

readlink ~/.local/bin/on-loop-tag
# expected: <absolute path to repo>/bin/on-loop-tag
```

If `~/.local/bin` is not on your `PATH`, the bootstrap prints a warning with the exact line to add to `~/.bashrc`.

### Symlink vs copy trade-off

The bootstrap uses a symlink. The trade-offs:

| Aspect | Symlink (chosen) | Copy |
|--------|-----------------|------|
| Repo edits propagate | Yes — `git pull` updates the installed CLI immediately | No — must re-run bootstrap |
| Tamper resistance | Lower — the link target is editable via the repo | Higher — install snapshot is frozen |
| Auditing "what is installed" | `readlink ~/.local/bin/on-loop-tag` shows the source | `sha256sum` shows the version |
| Cross-machine reproducibility | Weaker (depends on repo path) | Stronger |
| Removal | `rm symlink` | `rm file` |
| Matches existing pattern | Yes (marketplace points at on-disk repo) | No |

The symlink approach is chosen for Layer 1 because rapid iteration on the script is the priority. The `git tag -s` cryptographic signature provides integrity at the release-artifact layer, not at the install layer. If a later layer requires tamper-evident install, the approach will switch to copy with a sha256 manifest.

---

## Security considerations

**Tag name validation.** The tag argument is validated against a strict semver whitelist (`[a-zA-Z0-9.-]` only) before any git command runs. It is always passed as a positional argument to `git`, never interpolated into a format string or command string. Shell metacharacters in a tag name are rejected by check 1.

**`--reason` encoding.** The reason text flows into NDJSON. It is JSON-encoded via `jq -Rs .` when `jq` is available; the bash fallback escapes `\`, `"`, and all control characters (including `0x00`–`0x1F` and DEL `0x7F`) per-character. Both paths have been verified to round-trip arbitrary input through `jq -r .reason` without modification.

**Audit log PII.** The `user` field records `id -un` (login name). This is operationally necessary for attribution in the release audit. No UID, home directory, email, or environment variables are logged beyond the fields in the schema. On systems where login names are considered PII, review whether the audit log should be restricted before committing it to a public repository.

**Multi-user hosts: restrict `.on-loop/` permissions.** The audit log and its lock file are created mode 0644 (`umask 022`). On shared hosts a non-privileged user can read the log and observe the existence of in-progress release events (the lock content is always empty). To harden this, set the directory to mode 0750:

```bash
chmod 0750 .on-loop/
```

**`ON_LOOP_TAG_FORCE_TTY_INPUT` is a test-only override.** This environment variable is honored only when `BATS_TEST_FILENAME` or `BATS_VERSION` is set in the process environment (i.e., only inside a bats test run). Without the bats sentinel, the variable is silently ignored and a non-TTY invocation exits 7 as designed. An attacker who controls the environment of the calling process can set the bats sentinel and inject a single character into the y/N prompt, but that same attacker already has effective shell control — the seven cryptographic and git-state checks ahead of the prompt still run regardless. Do not rely on this variable in production scripts; it is not part of the stable interface.

**`script_version: "unknown"` is not evidence of tampering.** When `.claude-plugin/plugin.json` is absent or `jq` is unavailable, the script records `"unknown"` for `script_version`. This is a benign fallback, not a sign that the script has been modified.

**Configure `origin` over HTTPS or verified SSH.** The `main_synced` check runs `git fetch origin main`. If `origin` uses plaintext `http://`, the fetch is susceptible to man-in-the-middle. Configure your remote with `https://` or an SSH URL with a verified host key; tag integrity cannot compensate for a compromised fetch transport.

**`~/.local/bin` write permissions.** The script resolves `git` and `flock` via `$PATH` rather than hardcoded paths (required for the bats test shim to work). If `~/.local/bin` is writable by an untrusted user, that user can place a malicious `git` shim earlier on the path. Ensure `~/.local/bin` is owned by and writable only by you (`chmod 0755 ~/.local/bin`).

**HEAD pinning between pre-flight and signing.** The SHA shown at the confirmation prompt is the commit `git tag -s` will sign. The script captures HEAD once after the seven pre-flight checks complete and passes that SHA explicitly to `git tag -s "<TAG>" "<SHA>"`. If HEAD moves between the prompt and the signing call (concurrent `git reset`/`checkout`/`commit` from another shell, or a hook), the script refuses with `refused_reason: head_moved` and exit code 1 — applies in `--force` mode too (correctness, not bypass-able, same policy as the `tag_not_exists` race recheck).

---

## Failure modes and FAQ

**The script was interrupted (Ctrl-C) before the tag was created.**
The `INT`/`TERM` trap fires, emits an audit line with `action: error, error_code: 6`, and exits 6. No tag is created. The audit line is best-effort; if the interrupt happened before repo resolution, no audit line is written.

**The script was interrupted during the post-tag critical section (between `git tag -s` returning and the success audit line being written).**
The `INT`/`TERM` trap detects this via the `TRAP_ARMED` flag and prints a `CRITICAL:` line to stderr instead of writing a contradictory `action: error` audit. The tag may exist on disk without a matching audit entry. Reconcile `.on-loop/release-log.json` manually by appending a line describing the outcome, then commit the file. This window is short (a single `flock` + `printf` to a local file) but auditable when it happens.

**The script was interrupted after `git tag -s` but before the audit line was written.**
The tag exists locally. The audit line does not. Exit 9 (`E_AUDIT_FAILED`) will appear on stderr with a `CRITICAL` prefix. Do not delete the tag; it is the source of truth. Reconcile `.on-loop/release-log.json` manually by appending a line that captures what happened, then commit the file.

**Check 6 (`main_synced`) says "behind" vs "ahead" vs "diverged" — what is the difference?**

| Message | Meaning | Fix |
|---------|---------|-----|
| `local main is N commits behind origin/main` | Remote has new commits you have not pulled | `git pull --ff-only` (after resolving any untracked files — see check 5) |
| `local main is N commits ahead of origin/main` | You have commits that have not been pushed | `git push origin main` so the release commit is published before tagging |
| `local main has diverged from origin/main (A ahead, B behind)` | Histories have forked | Reconcile via rebase or merge before tagging |

**The tag name is rejected even though it looks valid.**
Pre-release identifiers must use only `[a-zA-Z0-9.]`. Examples that are accepted: `v0.7.0-rc1`, `v0.7.0-rc.1`, `v0.7.0-beta.2`. Examples that are rejected: `v0.7.0+build1` (build metadata `+` is not in the Layer 1 regex), `v0.7.0_alpha` (underscore is not allowed).

**`on-loop-tag: command not found` after running the bootstrap.**
`~/.local/bin` is not on `PATH`. Add this to `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then run `source ~/.bashrc` and retry.

**`error: required dependency missing: flock (install util-linux)`.**
`flock` ships in the `util-linux` package. On Fedora it is installed by `setup/fedora-bootstrap.sh`. On other distributions: `apt-get install -y util-linux` (Debian/Ubuntu) or `brew install util-linux` (macOS via Homebrew).

---

## Layer 1 scope — what this does NOT do

The following are explicit non-goals. They are candidates for Layer 2 or later:

- **No auto-push.** After a successful tag, the script prints `Next: git push origin <TAG>`. Pushing is the operator's explicit decision.
- **No GPG or SSH key provisioning.** Check 7 verifies that `user.signingkey` is configured; it does not create, rotate, or import keys.
- **No release-notes prefill.** The `-m` message is passed through to `git tag -s -m` verbatim; no changelog, git log summary, or PR body is generated.
- **No Quay or registry image build trigger.** Image promotion after tagging is downstream of this script.
- **No audit log rotation or archival.** `.on-loop/release-log.json` is append-only. If the file exceeds 10 MB, revisit in a later layer.
- **No `--reason` policy enforcement.** Layer 1 accepts any non-empty string. Layer 2 may add a minimum length or ticket-ID regex (e.g. `INC-\d+`) via a `.on-loop/release-policy.yaml` configuration file.
- **No tag deletion or amendment.** There is no `--delete` flag.
- **No Windows or non-bash shell support.** Bash 4+ on Linux and macOS only.
- **No cross-repo tagging.** The script always operates in `git rev-parse --show-toplevel` of the current working directory.
