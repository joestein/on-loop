#!/usr/bin/env bats
# tests/test_on_loop_tag.bats
#
# 16 bats test cases for bin/on-loop-tag (Layer 1).
# Tests 1-15 cover architect §7.6; test 16 covers Round-1 face-off Findings 1+2.
#
# Spec reference: architect §7.6 (test list), §7.1-§7.5 (fixture + shim design).
# Coding deviations: coding.md D-B (git tag -s shim), D-C (--check runs 1-7 only),
# D-H (.on-loop/.gitignore in fixture).
#
# Each test:
#   - loads tests/helpers/git_fixture.bash
#   - setup() calls setup_temp_repo then setup_git_shim
#   - teardown() calls teardown_temp_repo
#   - invokes the script via absolute path ON_LOOP_TAG_BIN
#   - uses ON_LOOP_TAG_FORCE_TTY_INPUT + BATS_VERSION sentinel for prompt tests
#
# Run with: bats --jobs 1 tests/test_on_loop_tag.bats
#
# bats-core v1.0+; requires: git, jq, flock (util-linux)

load 'helpers/git_fixture'

# ---------------------------------------------------------------------------
# Absolute path to the script under test (resolved relative to this file).
# ---------------------------------------------------------------------------
ON_LOOP_TAG_BIN="${BATS_TEST_DIRNAME}/../bin/on-loop-tag"

setup() {
  # Verify the script exists and is executable before every test.
  if [[ ! -x "$ON_LOOP_TAG_BIN" ]]; then
    echo "FATAL: script not found or not executable: $ON_LOOP_TAG_BIN" >&2
    return 1
  fi

  setup_temp_repo
  setup_git_shim

  # Change into the test repo so the script resolves the repo root correctly.
  cd "$REPO_DIR"
}

teardown() {
  teardown_temp_repo
}

# ===========================================================================
# Test 1 — all checks pass creates signed tag
# §7.6 row 1: exit 0, git tag -l v0.0.99 non-empty, audit line action:tagged
# ===========================================================================
@test "all checks pass creates signed tag" {
  # Provide 'y' to the confirmation prompt via the bats TTY override.
  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "test release"

  # exit 0
  [ "$status" -eq 0 ]

  # Tag must exist locally.
  local tag_list
  tag_list=$(git -C "$REPO_DIR" tag -l v0.0.99)
  [ -n "$tag_list" ]

  # Audit log must contain an entry with action:tagged.
  local last_line
  last_line=$(last_audit_line)
  [ -n "$last_line" ]
  run jq -e '.action == "tagged"' <<< "$last_line"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Test 2 — rejects non-semver tag name
# §7.6 row 2: exit 1, stderr contains semver_format, no tag created
# ===========================================================================
@test "rejects non-semver tag name" {
  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" not-semver -m "bad tag"

  # exit 1 (E_CHECK_FAIL)
  [ "$status" -eq 1 ]

  # stderr must contain the token name.
  [[ "$output" == *"semver_format"* ]] || [[ "$stderr" == *"semver_format"* ]]

  # No tag should exist.
  local tag_list
  tag_list=$(git -C "$REPO_DIR" tag -l not-semver 2>/dev/null || true)
  [ -z "$tag_list" ]
}

# ===========================================================================
# Test 3 — rejects when tag exists locally
# §7.6 row 3: exit 1, stderr contains tag_not_exists AND "exists locally"
# ===========================================================================
@test "rejects when tag exists locally" {
  # Create the tag locally first.
  git -C "$REPO_DIR" tag v0.0.99 HEAD

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "duplicate"

  [ "$status" -eq 1 ]
  [[ "$output" == *"tag_not_exists"* ]] || [[ "$stderr" == *"tag_not_exists"* ]]
  [[ "$output" == *"exists locally"* ]] || [[ "$stderr" == *"exists locally"* ]]
}

# ===========================================================================
# Test 4 — rejects when tag exists on remote
# §7.6 row 4: exit 1, stderr contains tag_not_exists AND "exists on origin"
# §7.4: push tag to origin, delete locally, so only remote has it.
# ===========================================================================
@test "rejects when tag exists on remote" {
  # Push tag to origin then delete it locally.
  git -C "$REPO_DIR" tag v0.0.99 HEAD
  git -C "$REPO_DIR" push -q origin v0.0.99
  git -C "$REPO_DIR" tag -d v0.0.99

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "remote dup"

  [ "$status" -eq 1 ]
  [[ "$output" == *"tag_not_exists"* ]] || [[ "$stderr" == *"tag_not_exists"* ]]
  [[ "$output" == *"exists on origin"* ]] || [[ "$stderr" == *"exists on origin"* ]]
}

# ===========================================================================
# Test 5 — rejects when on feature branch
# §7.6 row 5: exit 1, stderr contains on_main
# ===========================================================================
@test "rejects when on feature branch" {
  # Create and switch to a feature branch.
  git -C "$REPO_DIR" checkout -q -b feature/my-feature

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "wrong branch"

  [ "$status" -eq 1 ]
  [[ "$output" == *"on_main"* ]] || [[ "$stderr" == *"on_main"* ]]
}

# ===========================================================================
# Test 6 — rejects when working tree dirty
# §7.6 row 6: exit 1, stderr contains clean_tree
# ===========================================================================
@test "rejects when working tree dirty" {
  # Create an untracked file that is NOT under .on-loop/ (so it definitely
  # triggers clean_tree without also triggering no_session_untracked).
  echo "dirty" > "$REPO_DIR/dirty.txt"

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "dirty"

  [ "$status" -eq 1 ]
  [[ "$output" == *"clean_tree"* ]] || [[ "$stderr" == *"clean_tree"* ]]
}

# ===========================================================================
# Test 7 — rejects when .on-loop sessions untracked
# §7.6 row 7: exit 1, stderr contains no_session_untracked AND
#             the literal "v0.2.3 ship incident"
# ===========================================================================
@test "rejects when .on-loop sessions untracked" {
  # Create a fake untracked session file under .on-loop/sessions/.
  # The .gitignore ignores .on-loop/ root files, but we need to check what
  # the script uses: git ls-files --others --exclude-standard .on-loop/sessions/
  # That command lists files under .on-loop/sessions/ that are untracked.
  # Our .gitignore has ".on-loop/" which ignores the whole dir, so we need
  # to override: write a .gitignore that does NOT ignore .on-loop/sessions/
  # but DOES ignore .on-loop/release-log.json.
  #
  # Rewrite .gitignore in a fresh commit so clean_tree stays clean.
  printf '.on-loop/release-log.json\n.on-loop/release-log.json.lock\n' > "$REPO_DIR/.gitignore"
  git -C "$REPO_DIR" add .gitignore
  git -C "$REPO_DIR" commit -q -m "narrow .gitignore for session test"
  git -C "$REPO_DIR" push -q origin main

  # Now create a fake untracked session directory.
  mkdir -p "$REPO_DIR/.on-loop/sessions/20260101_000000_fake-session"
  echo '{}' > "$REPO_DIR/.on-loop/sessions/20260101_000000_fake-session/state.json"

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "untracked session"

  [ "$status" -eq 1 ]
  [[ "$output" == *"no_session_untracked"* ]] || [[ "$stderr" == *"no_session_untracked"* ]]
  [[ "$output" == *"v0.2.3 ship incident"* ]] || [[ "$stderr" == *"v0.2.3 ship incident"* ]]
}

# ===========================================================================
# Test 8 — rejects when local main behind origin
# §7.6 row 8: exit 1, stderr contains "behind origin/main" and hints "git pull --ff-only"
# §7.5: make_behind helper pushes a commit to origin via helper clone.
# ===========================================================================
@test "rejects when local main behind origin" {
  make_behind

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "behind"

  [ "$status" -eq 1 ]
  [[ "$output" == *"behind origin/main"* ]] || [[ "$stderr" == *"behind origin/main"* ]]
  [[ "$output" == *"git pull --ff-only"* ]] || [[ "$stderr" == *"git pull --ff-only"* ]]
}

# ===========================================================================
# Test 9 — rejects when local main ahead of origin
# §7.6 row 9: exit 1, stderr contains "ahead of origin/main" and hints "git push"
# §7.5: make_ahead helper commits locally without pushing.
# ===========================================================================
@test "rejects when local main ahead of origin" {
  make_ahead

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "ahead"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ahead of origin/main"* ]] || [[ "$stderr" == *"ahead of origin/main"* ]]
  [[ "$output" == *"git push"* ]] || [[ "$stderr" == *"git push"* ]]
}

# ===========================================================================
# Test 10 — rejects when signing key missing
# §7.6 row 10: exit 1, stderr contains signing_key
# ===========================================================================
@test "rejects when signing key missing" {
  # Set signing key to empty string in the local config. We cannot just
  # --unset because the global git config may supply a fallback value.
  # Setting it to an empty string overrides any global value and causes
  # `git config --get user.signingkey` to return empty output.
  git -C "$REPO_DIR" config user.signingkey ""

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "no key"

  [ "$status" -eq 1 ]
  [[ "$output" == *"signing_key"* ]] || [[ "$stderr" == *"signing_key"* ]]
}

# ===========================================================================
# Test 11 — aborts cleanly when user declines confirmation
# §7.6 row 11: exit 0, no tag created, audit line refused / user_declined
# ===========================================================================
@test "aborts cleanly when user declines confirmation" {
  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=n \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "declined"

  # exit 0 — clean decline is not an error (architect §4.4 row 2).
  [ "$status" -eq 0 ]

  # No tag should have been created.
  local tag_list
  tag_list=$(git -C "$REPO_DIR" tag -l v0.0.99 2>/dev/null || true)
  [ -z "$tag_list" ]

  # Audit log must record action:refused, refused_reason:user_declined.
  local last_line
  last_line=$(last_audit_line)
  [ -n "$last_line" ]
  run jq -e '.action == "refused" and .refused_reason == "user_declined"' <<< "$last_line"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Test 12 — --check mode runs checks but does not tag even on pass
# §7.6 row 12: exit 0, no tag created, NO new audit line appended
# Coding deviation D-C: --check runs checks 1-7, skips prompt, writes no audit.
# Architect §4.4: "--check, all pass: NO audit line written".
# ===========================================================================
@test "--check mode runs checks but does not tag even on pass" {
  # Capture line count before invocation.
  local before_count
  before_count=$(audit_log_line_count)

  run "$ON_LOOP_TAG_BIN" v0.0.99 -m "check only" --check

  # exit 0 (all checks pass).
  [ "$status" -eq 0 ]

  # No tag created.
  local tag_list
  tag_list=$(git -C "$REPO_DIR" tag -l v0.0.99 2>/dev/null || true)
  [ -z "$tag_list" ]

  # No audit line written — line count must be unchanged.
  local after_count
  after_count=$(audit_log_line_count)
  [ "$after_count" -eq "$before_count" ]
}

# ===========================================================================
# Test 13 — --force --reason tags despite one failure
# §7.6 row 13: exit 0, tag created, audit line force:true, checks_failed:[clean_tree]
# ===========================================================================
@test "--force --reason tags despite one failure" {
  # Dirty the working tree to force check 4 (clean_tree) to fail.
  echo "dirty for force test" > "$REPO_DIR/dirty_force.txt"

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "force release" \
    --force --reason "Emergency hotfix — CI down"

  # exit 0 (force overrides check failures).
  [ "$status" -eq 0 ]

  # Tag must have been created.
  local tag_list
  tag_list=$(git -C "$REPO_DIR" tag -l v0.0.99 2>/dev/null || true)
  [ -n "$tag_list" ]

  # Audit line: force:true, checks_failed contains clean_tree.
  local last_line
  last_line=$(last_audit_line)
  [ -n "$last_line" ]
  run jq -e '.force == true and (.checks_failed | map(. == "clean_tree") | any)' <<< "$last_line"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Test 14 — --force without --reason refuses
# §7.6 row 14: exit 2, stderr contains --reason
# ===========================================================================
@test "--force without --reason refuses" {
  run "$ON_LOOP_TAG_BIN" v0.0.99 -m "no reason" --force

  # exit 2 (E_USAGE — argv error).
  [ "$status" -eq 2 ]

  # stderr must mention --reason.
  [[ "$output" == *"--reason"* ]] || [[ "$stderr" == *"--reason"* ]]
}

# ===========================================================================
# Test 15 — audit log line is valid JSON with all required fields
# §7.6 row 15: last line parseable by jq -e with schema_version==1 + required fields
# Also verifies: script_version field exists (any value, not a specific one — D-F).
# ===========================================================================
@test "audit log line is valid JSON with all required fields" {
  # Create a successful tag so there is a clean audit line to inspect.
  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "audit schema test"

  [ "$status" -eq 0 ]

  local last_line
  last_line=$(last_audit_line)
  [ -n "$last_line" ]

  # Full schema validation per architect §7.6 row 15 and §5.2.
  # script_version is asserted to exist (non-null) but NOT to a specific value.
  run jq -e '
    .schema_version == 1 and
    (.ts | type == "string") and (.ts | length > 0) and
    (.user | type == "string") and (.user | length > 0) and
    (.tag | type == "string") and (.tag | length > 0) and
    (.action | type == "string") and (.action | length > 0) and
    (.force | type == "boolean") and
    (.checks_passed | type == "array") and
    (.checks_failed | type == "array") and
    (.checks_skipped | type == "array") and
    (.script_version | type == "string") and (.script_version | length > 0)
  ' <<< "$last_line"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Test 16 — tag is pinned to the verified SHA and the audit `commit` field
#           equals the tag's commit-target
# Round-1 Findings 1 + 2 (face-off review):
#   1. `git tag -s` must be invoked with an explicit commit (the SHA captured
#      after the seven pre-flight checks), not "whatever HEAD is at signing
#      time". A wrong HEAD between checks and signing was the v0.2.3-class
#      failure mode this script exists to prevent; pre-fix, the script tagged
#      `HEAD` implicitly and could not detect HEAD movement.
#   2. The audit log's `commit` field must name the SHA the tag actually
#      points at, not a fresh `rev-parse HEAD` read at audit-append time.
#
# Both invariants are observable from outside: the tag's commit-target
# (`git rev-parse "<tag>^{commit}"`) must equal the SHA observed *before*
# script invocation, and the audit `commit` field must equal the tag's
# commit-target byte-for-byte.
# ===========================================================================
@test "tag is pinned to verified SHA and audit commit equals tag target" {
  # Capture the SHA the script will lock in.
  local pre_sha
  pre_sha=$(git -C "$REPO_DIR" rev-parse HEAD)
  [ -n "$pre_sha" ]

  run env \
    BATS_VERSION="${BATS_VERSION:-1.0}" \
    ON_LOOP_TAG_FORCE_TTY_INPUT=y \
    "$ON_LOOP_TAG_BIN" v0.0.99 -m "pin test"

  [ "$status" -eq 0 ]

  # The tag's commit-target must equal the pre-invocation HEAD SHA.
  local tag_commit
  tag_commit=$(git -C "$REPO_DIR" rev-parse "v0.0.99^{commit}")
  [ "$tag_commit" = "$pre_sha" ]

  # The audit `commit` field must equal the tag's commit-target.
  local audit_commit
  audit_commit=$(last_audit_line | jq -r '.commit')
  [ "$audit_commit" = "$tag_commit" ]
}
