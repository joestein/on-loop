# Build Agent Notes — on-loop-tag Layer 1

## Summary

Created two build-infrastructure files in the worktree at
`.claude/worktrees/on-loop-tag-layer-1/`:

1. `.github/workflows/on-loop-tag.yml` — GitHub Actions CI pipeline
2. `Makefile` — developer task runner with six targets

No pre-existing Makefile or `.github/` directory existed in the worktree;
both files were created from scratch. No script or test files were modified.

## Decisions

### D-BUILD-1: bats version fallback strategy

Ubuntu's `apt` ships bats 1.2.x on 22.04 and 1.8.x on 24.04 — versions below
1.7 lack features expected by the test suite (notably stable `$output` handling
and `--jobs` flag semantics). The workflow includes an explicit version check
after the `apt-get install`: if `bats --version` reports < 1.7, the job clones
`bats-core/bats-core` at the pinned tag `v1.11.0` and installs from source via
the upstream `install.sh`. This pin is auditable and does not introduce an
unpinned internet dependency.

The version check is `bats_major >= 2 OR (bats_major == 1 AND bats_minor >= 7)`
and handles both single-digit and two-digit minor versions correctly.

### D-BUILD-2: path filter on both push and pull_request triggers

The workflow uses `on.push.paths` and `on.pull_request.paths` with identical
path lists (`bin/on-loop-tag`, `tests/**`, `setup/fedora-bootstrap.sh`,
`.github/workflows/on-loop-tag.yml`). This means:

- A push that only modifies `README.md` or session notes does NOT trigger the
  workflow, keeping CI fast for documentation-only changes.
- All four paths are covered: the script itself, the tests, the bootstrap
  (which modifies the install path), and the workflow file itself (so CI
  configuration changes are tested immediately).

The `pull_request` trigger is narrowed to `branches: [main]` only, matching
the repo's single-branch merge convention.

### D-BUILD-3: fetch-depth: 0

Full history is fetched. The tests create isolated temp repos (so they have
their own complete history) but `git rev-list`-style introspection in the
worktree itself, and any future meta-test that runs against the actual repo,
requires full ancestry. The cost on a shallow-history repo is negligible;
defense against obscure edge cases is worth it.

### D-BUILD-4: GPG / signing key in CI — no special action needed

The test suite uses the `git tag -s` shim (architect §7.2, coding D-B) which
intercepts `git tag -s` and rewrites to `git tag -a`. This shim is wired in
`tests/helpers/git_fixture.bash` and operates via a PATH-prepended fake `git`
binary. The `git config commit.gpgsign false` and `git config tag.gpgsign
false` settings are applied to the temp repo inside each test fixture.

**No GPG agent, no SSH signing key, and no `GIT_COMMITTER_EMAIL` override are
needed** in the Actions runner environment. The `BATS_VERSION` env var is set
automatically by bats-core, so the `ON_LOOP_TAG_FORCE_TTY_INPUT` gate in the
script fires correctly for tests 1 and 11 without any workflow-level env setup.

### D-BUILD-5: permissions: contents: read (least privilege)

The job only reads the repository to run static analysis and tests. It does
not push, create releases, or write to any GitHub resource. Setting
`permissions: contents: read` at the job level satisfies NIST 800-53 AC-6
(Least Privilege) and is aligned with the persona's Zero Trust principle.

### D-BUILD-6: timeout-minutes: 10

The full suite (15 tests, shellcheck, apt install, optional bats source build)
is expected to complete in under 3 minutes on a standard Actions runner. The
10-minute timeout allows 3x headroom for `apt-get` slowness and cold-cache
bats source builds without letting a hung test block the runner indefinitely.

### D-BUILD-7: Makefile uses bash built-ins for idempotent install/uninstall

The `install` and `uninstall` targets invoke `[[ ... ]]` conditionals and use
`$(CURDIR)` to resolve an absolute path to the script. The `$$` escaping
convention for Make shell variables is applied throughout so `$HOME`, `$PATH`,
etc. resolve at recipe-execution time, not at Make parse time. The install
target is idempotent: it removes any stale file or symlink before creating the
new one, exactly mirroring the bootstrap script logic in `setup/fedora-bootstrap.sh`.

## Files Modified

- `.github/workflows/on-loop-tag.yml` — CREATE — CI pipeline (shellcheck + bats)
- `Makefile` — CREATE — developer task runner (help, test, lint, check, install, uninstall)

## CI Pipeline

- **Triggers**: push to any branch when relevant paths change; PRs against main when relevant paths change
- **Relevant paths**: `bin/on-loop-tag`, `tests/**`, `setup/fedora-bootstrap.sh`, `.github/workflows/on-loop-tag.yml`
- **Steps** (in order):
  1. `actions/checkout@v4` with full history
  2. `apt-get install bats jq util-linux shellcheck`
  3. bats version check; source install from `bats-core/bats-core@v1.11.0` if apt version < 1.7
  4. `shellcheck bin/on-loop-tag` (zero-warning gate)
  5. `bats --jobs 1 tests/test_on_loop_tag.bats` (all 15 cases)
- **Estimated duration**: 1-3 minutes (cold cache); under 90 seconds (warm cache after first run)
- **Failure behavior**: any non-zero exit from any step fails the job immediately

## Issues Found

None blocking.

### [INFO] GPG agent requirement

The CI environment has no GPG agent and no signing key. This is handled
entirely by the test fixture's PATH shim (architect §7.2) which rewrites
`git tag -s` to `git tag -a`. No workflow-level workaround is needed. Flag
retained here so the reviewer agent can confirm the shim is correctly
wired in the test suite.

### [INFO] ubuntu-latest bats version drift

`ubuntu-latest` will eventually move from 22.04 to 24.04 (and later).
Ubuntu 24.04 ships bats 1.8.0 which satisfies the `>= 1.7` threshold, so
the fallback source install will become a no-op. If ubuntu-latest moves
to a distro that drops bats from default apt, the fallback will engage
transparently. The pinned fallback tag (`v1.11.0`) should be reviewed
periodically by the team.

## Recommendations for Next Agent (Reviewer)

1. Verify `shellcheck bin/on-loop-tag` passes with zero warnings/errors
   (coding agent claimed shellcheck-clean; CI enforces it; reviewer should
   confirm no suppressions were added).
2. Confirm the `bats --jobs 1` flag is preserved in the workflow — parallel
   execution corrupts test isolation (architect OQ-4).
3. Confirm the `fetch-depth: 0` rationale is acceptable for the project's
   security posture (full history fetch has no confidentiality implications
   for a public repo; fine for a private repo given the runner's read-only
   token).
4. The `Makefile` `install` target uses `[[ ... ]]` bash conditionals in a
   recipe shell. This requires `SHELL` to be bash. Make's default shell is
   `/bin/sh`. If the reviewer finds this is a portability concern, the
   Makefile should add `SHELL := /bin/bash` at the top. For Fedora and
   Ubuntu developer environments (the only documented platforms), `/bin/sh`
   is bash-compatible; this is low risk but worth noting.
