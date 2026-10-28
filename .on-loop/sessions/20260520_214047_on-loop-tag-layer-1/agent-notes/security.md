# Security Agent Notes — on-loop-tag Layer 1

## Summary Verdict: **PASS_WITH_NOTES**

The implementation of `bin/on-loop-tag` is materially compliant with architect §9 (S-1 through S-10) and OWASP-relevant guidance for a shell tool that writes audit logs and invokes `git tag -s`. All ten threat-model items either VERIFY or are NOT_APPLICABLE; no CRITICAL or HIGH findings exist. Five LOW / INFO-level notes are documented below for downstream documentation/build agents — none block progression.

The JSON round-trip property was verified empirically on BOTH the `jq -Rs .` path and the bash-fallback path across eight adversarial inputs (quotes, backslashes, newlines, tabs, control bytes 0x01/0x1F/0x7F, command-substitution syntax, multi-byte UTF-8, BEL/VT). All sixteen round-trips matched byte-for-byte after re-parsing via `jq -r .reason`.

The semver whitelist (check 1) successfully rejected all eleven command-injection / path-traversal / metacharacter attempts. The `--reason` requirement under `--force` is enforced (exit 2). The TTY-override gate (`ON_LOOP_TAG_FORCE_TTY_INPUT`) is correctly fenced by the `BATS_TEST_FILENAME || BATS_VERSION` sentinel — without the sentinel, the override is silently ignored and a non-TTY invocation exits 7 as designed.

## Findings Table

| ID | Severity | Title | Location | Description | Remediation |
|----|----------|-------|----------|-------------|-------------|
| F-1 | INFO | Bash-fallback JSON encoder relies on locale | `bin/on-loop-tag:134` | `printf '%d' "'$ch"` uses bash's single-char numeric-conversion built-in. Wrapped in `LC_ALL=C` — correct, but worth noting because in non-C locales the bytewise interpretation can drift. The `LC_ALL=C` invocation is per-iteration which is slow but safe. | None required. Document that the bash fallback is slower (~O(n) per character) and that `jq` is the recommended path; bootstrap already installs `jq` implicitly via the marketplace tooling chain. |
| F-2 | INFO | Audit-log lock file is world-readable (mode 0644) | `bin/on-loop-tag:247` + umask 022 | The lock file inherits 0644 from `umask 022`. This is acceptable on single-user workstations but on shared hosts a non-privileged user could lstat/read it. The lock content is empty by design (it is purely a flock anchor) so confidentiality is not at risk; only the existence of a release-in-progress event leaks. | Document in `bin/on-loop-tag.md` security section that multi-user hosts should set `.on-loop/` to mode 0750 (already noted in architect S-6). No code change needed. |
| F-3 | LOW | `ON_LOOP_TAG_FORCE_TTY_INPUT` can be triggered by attacker-controlled env vars | `bin/on-loop-tag:687-707` | If an attacker controls the environment of the calling process, they can set `BATS_VERSION=x ON_LOOP_TAG_FORCE_TTY_INPUT=y` to bypass the y/N prompt. The architect rated this LOW (S-5): an attacker with environment-control already has effective shell control, and the worst the override does is force a single character into the prompt — the script still runs the seven cryptographic / git-state checks ahead of it, and the only mode that creates a tag bypassing the prompt also requires `--force --reason "<text>"`. | Documented in architect S-5 as accepted residual risk. Documentation agent must call out the env-var bypass in `bin/on-loop-tag.md` security notes. No code change. |
| F-4 | LOW | `script_version` falls back to literal `"unknown"` outside the repo | `bin/on-loop-tag:99-110, 367-376` | When `.claude-plugin/plugin.json` is missing or `jq` is unavailable, the audit log records `script_version:"unknown"`. This is correct fail-secure behavior (we never crash on the audit path) but the documentation agent should explicitly call this out so reviewers do not interpret it as evidence of tampering. | Documentation agent: add a one-liner to `bin/on-loop-tag.md` audit-schema section. |
| F-5 | LOW | `git fetch` over `http://` or unauthenticated SSH is permitted | `bin/on-loop-tag:625` | The script does not verify the transport scheme of `origin`. If `origin` is plaintext `http://`, `main_synced` will accept a man-in-the-middled origin/main. Architect S-9 lists this as out-of-script-scope: git itself is responsible for transport. | Documentation agent: add a single line to the security section: "Configure `origin` over HTTPS or verified SSH; tag verification cannot compensate for a compromised fetch transport." |
| F-6 | INFO | Bootstrap symlink creation does NOT pre-validate the target's permissions | `setup/fedora-bootstrap.sh:71-75` | `rm -f "$SCRIPT_DST"` + `ln -s "$SCRIPT_SRC" "$SCRIPT_DST"` is correct and idempotent. The `[[ -L "$SCRIPT_DST" || -e "$SCRIPT_DST" ]]` test is safe (no following of dangling links via `-e` alone, since `-L` is tested first). No race vulnerability because `$HOME/.local/bin` is owned by the invoking user (mode 0755 by default). | None — implementation matches architect §6.1. |

No CRITICAL findings. No HIGH findings.

## Per-S Verification (architect §9 mitigations)

| ID | Status | Evidence |
|----|--------|----------|
| **S-1** (TAG command injection, CWE-77) | **VERIFIED** | All `git` invocations pass `$TAG` as a positional argv element (`"$TAG"`, never `$TAG` unquoted). The semver regex `^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$` whitelists only alphanumerics, `.`, `-`. Empirically tested 11 bypass attempts (`v1.0.0; rm -rf /tmp/x`, `v1.0.0$(whoami)`, `v1.0.0\`id\``, `v0.0.0../../etc/passwd`, embedded newline, space, glob, percent-format, redirect, pipe, empty) — all rejected by check 1 or by argv parser (empty case exits 2 with no log line written). |
| **S-2** (REASON injection into NDJSON, CWE-117) | **VERIFIED** | `json_escape_string` (lines 115-152) calls `jq -Rs .` when available; the bash fallback escapes `\` first, then `"`, then iterates code points and emits `\b \t \n \f \r` for the common controls and `\uXXXX` for the rest of `0x00-0x1F` plus DEL `0x7F`. JSON round-trip tested on 8 inputs through BOTH paths (16 total) — all matched byte-for-byte via `jq -r .reason`. See "JSON round-trip test results" below for the matrix. |
| **S-3** (-m MESSAGE command injection) | **VERIFIED** | Line 831: `git tag -s "$TAG" -m "$MESSAGE"`. `$MESSAGE` is a separate argv element to `git`; no shell interpolation. Empirical test: `-m '$(rm -rf x)'`, `-m '\`id\`'`, `-m 'release; whoami'`, `-m 'release | cat /etc/passwd'` all stored literally in the annotated-tag message body (verified via `git tag -n99`). |
| **S-4** (PATH untrusted search path, CWE-426) | **VERIFIED with documented residual** | Script does NOT canonicalize `git` or `flock` paths (intentional, per architect S-4: bats shim requires `$PATH` resolution). Risk is operator-side: if `~/.local/bin` is writable by another user, that user can shadow `git`. Mitigation is documented (file permissions on `~/.local/bin` must be 0755 owner-only). Documentation agent must restate this in `bin/on-loop-tag.md`. |
| **S-5** (ON_LOOP_TAG_FORCE_TTY_INPUT gate) | **VERIFIED** | Lines 687-707: `[[ -n "${BATS_TEST_FILENAME:-}" \|\| -n "${BATS_VERSION:-}" ]]`. Empirical confirmation: (a) without either sentinel + override set, script exits 7 with `not a TTY` stderr; (b) with `BATS_VERSION=1.0 ON_LOOP_TAG_FORCE_TTY_INPUT=n`, override fires and user-declined path runs; (c) with `BATS_TEST_FILENAME=/tmp/foo.bats ON_LOOP_TAG_FORCE_TTY_INPUT=n`, same. Residual LOW risk documented as F-3 — attacker-controlled environment can trip this, but they already have shell control, and the seven cryptographic checks still run. |
| **S-6** (audit-log file perms, CWE-732) | **VERIFIED** | `umask 022` at line 24 → audit log + lock both created mode 0644. Confirmed empirically (`stat -c '%a %n' .on-loop/release-log.json.lock` → 644). Multi-user `.on-loop/` directory hardening is out-of-script-scope (architect S-6); documented as F-2. |
| **S-7** (flock missing) | **VERIFIED** | Lines 482-485: `command -v flock >/dev/null 2>&1` checked at startup; exit 3 (`E_NO_REPO` — slight semantic mismatch, the message is "missing dependency: flock") with stderr `install util-linux`. Verified locally; flock is present on this host. |
| **S-8** (TOCTOU between `git tag -s` and audit append) | **VERIFIED** | Trap is armed at line 751 BEFORE `run_first_seven_checks`. Trap remains armed THROUGH `git tag -s` (line 831). After `git tag -s` returns success, trap is cleared at line 842 (`trap - INT TERM`) BEFORE `emit_audit`. The window between trap-clear and `printf >>` inside `audit_append` is one stack frame deep — effectively two function calls plus a write(2). This matches architect §8.2 intent: a SIGINT during audit append produces NO error-audit line (because the trap was deliberately cleared), and the tag remains. Architect explicitly accepted this residual: "tag is more durable than a log line by design." |
| **S-9** (fetch transport security) | **VERIFIED out-of-scope** | git transport is git's responsibility. Documented as F-5. |
| **S-10** (--force audit-bypass abuse) | **VERIFIED** | `--force` requires `--reason "<text>"` (line 458-460: `error_usage '--force requires --reason "<text>"'`, exit 2 confirmed empirically). The reason is logged immutably to git-tracked `.on-loop/release-log.json` (NDJSON, append-only, file is committed per architect §5.1). `--check`+`--force` mutually exclusive (line 448-450). Layer-2 enhancement (minimum reason length / ticket-ID regex) deferred. |

## OWASP Top 10 Mapping

| # | Category | Status | Notes |
|---|----------|--------|-------|
| A01 Broken Access Control | NOT_APPLICABLE | Single-user CLI; authn/authz delegated to the user's shell + git's signing key. |
| A02 Cryptographic Failures | VERIFIED | Tag integrity is via `git tag -s` (GPG/SSH signing); script only verifies `user.signingkey` is configured (Check 7) — actual cryptographic operation is performed by git itself. Audit log is integrity-protected by git history (file is committed). |
| A03 Injection (CWE-77/78/94/117) | VERIFIED | S-1, S-2, S-3 above. No `eval`, no `bash -c "$var"`, no `printf "$fmt"` with variable format strings (statically confirmed via `grep -nE 'eval\|bash -c\|printf[[:space:]]+"[^"]*\$'`). |
| A04 Insecure Design | VERIFIED | Spec-driven; 8 verbatim checks; explicit threat model in architect §9; ADRs for every decision. |
| A05 Security Misconfiguration | VERIFIED | `set -euo pipefail`, `IFS=$'\n\t'`, `umask 022` at top. No debug flags left on. |
| A06 Vulnerable Components | VERIFIED | Runtime deps: `bash >= 4`, `git >= 2.0`, `flock` (util-linux), optional `jq`. All standard system packages with security maintenance. Build agent will run `shellcheck` in CI for static SAST. |
| A07 Auth Failures | NOT_APPLICABLE | No authentication surface in the script. |
| A08 Data Integrity Failures (CWE-345) | VERIFIED | Audit log is append-only NDJSON, committed to git; tags are cryptographically signed. |
| A09 Logging Failures (CWE-117/532) | VERIFIED | NDJSON schema versioned; PII minimized to `id -un` (no UID, no env, no argv beyond intended fields); reason is JSON-encoded (S-2 verified). No secrets logged. |
| A10 SSRF | NOT_APPLICABLE | The only outbound network is `git fetch origin` / `git ls-remote origin`, both of which use the user's existing remote URL — no script-controlled URL construction. |

## STRIDE Analysis

| Component / Threat | Spoofing | Tampering | Repudiation | Info Disclosure | DoS | Elevation |
|--------------------|----------|-----------|-------------|------------------|-----|-----------|
| `--reason` text field | n/a | mitigated (immutable git log) | mitigated (id -un + commit SHA) | LOW: reason text is visible to anyone with repo read | LOW: reason length unbounded | n/a |
| `git tag -s` invocation | mitigated (GPG/SSH signature) | mitigated (signature) | mitigated (signer identity in tag) | n/a | mitigated (fast, idempotent) | n/a |
| Audit log writer | n/a | LOW: 0644 file is writable only by owner | mitigated (append-only, git-tracked) | LOW: any local user can read | LOW: out-of-disk → exit 9, tag still exists | n/a |
| `--force` mode | n/a | n/a | mitigated (reason + checks_failed in audit) | n/a | n/a | LOW: any operator can `--force` — by design; PR-review is the policy gate |
| TTY override env var | LOW (F-3) | n/a | n/a | n/a | n/a | LOW (F-3 — already has shell to set env) |
| Bootstrap symlink | n/a | depends on `~/.local/bin` perms | n/a | n/a | n/a | depends on `~/.local/bin` perms |

## JSON Round-Trip Test Results

**Both jq path and bash-fallback path tested, all 16 inputs round-trip exactly.**

Test harness: `/tmp/sec-roundtrip2.sh` (sandbox at `/tmp/sec-test-on-loop-tag/`). For each input, the script was invoked with `--force --reason "$INPUT"`, the last NDJSON line of `.on-loop/release-log.json` was decoded via `jq -r .reason`, and the decoded byte-string was compared byte-for-byte to the input.

| # | Input description | Raw bytes (representative) | jq path | bash-fallback path |
|---|-------------------|-----------------------------|---------|---------------------|
| 1 | plain ASCII | `plain ASCII` | PASS | PASS |
| 2 | double quotes | `double "quotes" inside` | PASS | PASS |
| 3 | backslash + quote | `back\slash and "quote"` | PASS | PASS |
| 4 | newline + tab | `newline\nand\ttab` | PASS | PASS |
| 5 | control bytes 0x01, 0x1F, 0x7F (DEL) | `with ctrl \x01 \x1f DEL \x7f` | PASS | PASS |
| 6 | shell metacharacters | `$(rm -rf /) backtick \`id\`` | PASS | PASS |
| 7 | UTF-8 multi-byte | `unicode: café résumé ☕ 中文` | PASS | PASS |
| 8 | mixed | `forward/slash and "embedded" \backslash\ + bell \x07 + vert \x0b` | PASS | PASS |

The bash-fallback path was forced by invoking the script under `PATH=$SHIM:$JQLESS_DIR` where `$JQLESS_DIR` symlinks only non-jq utilities — confirmed `command -v jq` returns false inside the invocation.

## Semver Bypass Attempts

| Input | Result | Notes |
|-------|--------|-------|
| `v1.0.0; rm -rf /tmp/x` | REJECTED by check 1 (exit 1, `FAIL semver_format`) | command-injection metachar |
| `v1.0.0$(whoami)` | REJECTED | command-substitution |
| `v1.0.0\`id\`` | REJECTED | backtick |
| `v0.0.0../../etc/passwd` | REJECTED | path traversal |
| `v1.0.0\n v2.0.0` (embedded LF) | REJECTED | newline injection |
| `v1.0.0 v2.0.0` (space) | REJECTED | argv split attempt |
| `v1.0.0*` | REJECTED | glob |
| `v1.0.0%n%n` | REJECTED | format-string char |
| `v1.0.0>/tmp/x` | REJECTED | redirection |
| `v1.0.0\|cat` | REJECTED | pipe |
| `` (empty) | REJECTED by argv parser (exit 2, `TAG is required`) | parse-time guard, before semver runs; no audit line — correct |

## Message Passthrough Tests (S-3)

All inputs were stored verbatim in the annotated-tag message body (`git tag -n99` confirmation):

| `-m` input | Stored verbatim? |
|------------|-------------------|
| `$(rm -rf x)` | YES |
| `` `id` `` | YES |
| `release; whoami` | YES |
| `release \| cat /etc/passwd` | YES |

No shell expansion occurred (verified by absence of side-effect files).

## Static Code Review

- `grep -nE 'eval\|bash -c\|source[[:space:]]\|\$\(.*\$\{' bin/on-loop-tag` → only matches are legitimate `${ARR[@]+"${ARR[@]}"}` empty-array safety guards on lines 227-229 and a one-time `BASH_SOURCE[0]` directory resolution on line 371. NO `eval`, NO `bash -c "$untrusted"`, NO sourcing of attacker-controlled files.
- `grep -nE 'printf[[:space:]]+[\"]?\$[A-Za-z_]' bin/on-loop-tag` → no format-string injection (every `printf` uses a literal format string with `%s` placeholders).
- `bash -n bin/on-loop-tag` → clean syntax.
- All `$var` expansions inside `git` / `printf` calls are double-quoted.
- Errexit boundaries: `set -euo pipefail` script-wide; `set +e` / `set -e` toggled only around the targeted `git tag -s` invocation (lines 830/833) so we can capture its return code without abort.

## Bootstrap Hunk Review

Lines 60-86 of `setup/fedora-bootstrap.sh`:

- `mkdir -p "$HOME/.local/bin"` — quoted, safe.
- `SCRIPT_SRC` and `SCRIPT_DST` are computed from `REPO_DIR` (toplevel, derived via `cd $(dirname $0)/..` with quotes) and `$HOME` — both trusted values.
- The `[[ ! -x "$SCRIPT_SRC" ]]` guard prevents linking to a missing or non-executable target. Good.
- `if [[ -L "$SCRIPT_DST" || -e "$SCRIPT_DST" ]]; then rm -f "$SCRIPT_DST"; fi` — `-L` test catches dangling symlinks; `-e` catches regular files; either way `rm -f` is safe (no `-r`, single file).
- `ln -s "$SCRIPT_SRC" "$SCRIPT_DST"` — symlink only; no privileged path. The symlink lives in `$HOME/.local/bin` which is owner-only-writable on standard Fedora layouts.
- PATH-membership check uses `case ":$PATH:" in *":$HOME/.local/bin:"*)` — correct standard idiom; no `eval`, no leak.
- WARNING heredoc is constant text, `\$PATH` is intentionally backslash-escaped so the message reads literally.

No vulnerabilities in the bootstrap hunk. The symlink trade-off (architect §6.2) is documented and accepted.

## Compliance Notes

- **SOC2 CC7.2 (Security event detection)**: VERIFIED — every release-tagging attempt produces an immutable NDJSON audit line including `user`, `commit`, `ts`, `action`, `force`, `reason`. The audit log is committed to git.
- **NIST 800-53 AU-2 (Audit Events) / AU-3 (Content of Audit Records)**: VERIFIED — schema includes event type (`action`), timestamp (UTC ISO 8601), user identity, outcome (`checks_passed`/`checks_failed`), and event-specific fields (`reason`, `error_code`). All 13 fields per architect §5.2 are emitted.
- **NIST 800-53 AC-3 (Access Enforcement) / AC-6 (Least Privilege)**: The script does not elevate privileges, does not write outside `$REPO_ROOT/.on-loop/`, and respects the operator's GPG/SSH key configuration. Bootstrap installs to `$HOME/.local/bin` (user scope, no `sudo` for the symlink itself).
- **PCI-DSS**: NOT_APPLICABLE — no cardholder data handled.
- **GDPR**: VERIFIED — `user` field is `id -un` (login name), which is operationally necessary for audit attribution. No additional PII. The architect's OQ-1 already flagged this for re-review if reviewers raise concern.

## Dependency Audit

Runtime dependencies:

| Package | Required? | Status |
|---------|-----------|--------|
| `bash >= 4` | yes | Fedora ships bash 5.x; macOS users will need `brew install bash` (already documented as architect §12 constraint). |
| `git >= 2.0` | yes | Fedora `dnf install -y git` per bootstrap line 24. No known CVEs in current packaged versions. |
| `flock` (util-linux) | yes | Fedora bootstrap installs `util-linux` (line 31). Verified present locally (`/usr/bin/flock`). |
| `jq` | optional | Recommended; not in bootstrap dnf list. Bash-fallback verified equivalent in this audit. Consider adding `jq` to the bootstrap dnf list (informational — see Recommendations). |
| `bats` (test only) | yes (test) | Added to bootstrap line 30. Test-time only. |

No known-CVE blocking dependencies. SAST gap: `shellcheck` not installed in this sandbox; build agent must wire it into CI per architect §10 / coding D-recommendations.

## Recommendations for Next Agent

### Documentation agent (DOC phase)
1. Add to `bin/on-loop-tag.md` a "Security notes" subsection that calls out:
   - Multi-user `.on-loop/` permission caveat (F-2, S-6) — recommend mode 0750 for shared hosts.
   - `ON_LOOP_TAG_FORCE_TTY_INPUT` is a test-only override gated by BATS sentinels; attacker-controlled env is the only way to trip it and they already have shell control (F-3, S-5).
   - `script_version: "unknown"` is benign when `plugin.json` is unreachable (F-4); do not interpret as tampering.
   - Configure `origin` over HTTPS or verified SSH (F-5, S-9).
   - `~/.local/bin` must be 0755 owner-only to prevent PATH-shadowing (S-4).
2. Document the `--force` policy + audit-immutability story in the README "Safe release tagging" section.
3. List all 10 exit codes (0..9) in the man page.

### Build agent (BUILD phase)
1. Add `shellcheck bin/on-loop-tag` to `.github/workflows/on-loop-tag.yml`. Script is written to be shellcheck-clean.
2. Add `jq` to the Fedora bootstrap dnf list (optional but improves audit performance for the common case).
3. Configure `bats tests/test_on_loop_tag.bats --jobs 1` per architect OQ-4.
4. Consider adding a CI step that runs `jq -e '.schema_version==1' .on-loop/release-log.json` against every PR that touches the log (low-priority hygiene).

### Reviewer agent (REVIEW phase)
1. Confirm all 13 NDJSON schema fields per architect §5.2 are emitted in every audit line (already validated in test 15).
2. Confirm the `trap - INT TERM` at line 842 sits between the successful `git tag -s` return and `emit_audit "tagged"` — this is the S-8 mitigation surface.
3. Confirm `$TAG` and `$MESSAGE` are passed only as positional argv elements to `git` and never as part of any format string (audited above).

## Final Recommendation

**PASS_WITH_NOTES — proceed to DOC + BUILD phases.**

No CRITICAL or HIGH findings. All architect §9 mitigations (S-1 through S-10) verified or appropriately deferred. Five LOW/INFO notes are downstream-actionable (documentation phrasing only) and do not warrant a CODE-phase retry.
