#!/usr/bin/env bash
# tests/helpers/git_fixture.bash
#
# Reusable bats fixture helpers for on-loop-tag tests.
#
# Provides:
#   setup_temp_repo      — create a temp dir with bare origin + clone on main
#   teardown_temp_repo   — rm -rf the temp dir
#   setup_git_shim       — PATH-prepend a shim that rewrites 'git tag -s' to 'git tag -a'
#   clean_audit_log      — remove .on-loop/release-log.json inside REPO_DIR
#   last_audit_line      — print the last line of .on-loop/release-log.json
#   make_behind          — push a new commit from a helper clone so local is behind
#   make_ahead           — commit locally without pushing so local is ahead
#
# All helpers operate on the globals exported by setup_temp_repo:
#   TEST_TMPDIR  — root temp dir
#   ORIGIN_DIR   — bare origin repo
#   REPO_DIR     — working clone (tests cd into here)

# ON_LOOP_TAG_BIN is set by the test file itself:
#   ON_LOOP_TAG_BIN="$BATS_TEST_DIRNAME/../bin/on-loop-tag"

# ---------------------------------------------------------------------------
# setup_temp_repo
# ---------------------------------------------------------------------------
# Creates:
#   $TEST_TMPDIR/origin.git   — bare "origin" repo
#   $TEST_TMPDIR/repo         — clone with initial commit pushed to origin/main
#
# Configures the clone with:
#   user.email        test@example.com
#   user.name         Test User
#   user.signingkey   TESTKEY0xDEADBEEF   (placeholder, never used for real signing)
#   commit.gpgsign    false
#   tag.gpgsign       false
#
# The initial commit also installs a .gitignore that ignores .on-loop/ so that
# the runtime-created .on-loop/release-log.json never causes check 4 (clean_tree)
# or check 5 (no_session_untracked) to false-fail during tests.
# (Coding agent note D-H)
setup_temp_repo() {
  TEST_TMPDIR=$(mktemp -d -t onlooptag.XXXXXX)
  ORIGIN_DIR="$TEST_TMPDIR/origin.git"
  REPO_DIR="$TEST_TMPDIR/repo"

  # Create bare origin.
  git init --bare -q "$ORIGIN_DIR"

  # Clone from origin.
  git clone -q "$ORIGIN_DIR" "$REPO_DIR"

  # Configure the clone.
  git -C "$REPO_DIR" config user.email "test@example.com"
  git -C "$REPO_DIR" config user.name  "Test User"
  git -C "$REPO_DIR" config user.signingkey "TESTKEY0xDEADBEEF"
  git -C "$REPO_DIR" config commit.gpgsign false
  git -C "$REPO_DIR" config tag.gpgsign false

  # Ensure we are on main (some git versions default to master).
  git -C "$REPO_DIR" checkout -b main 2>/dev/null || git -C "$REPO_DIR" checkout main 2>/dev/null || true

  # Initial commit — include .gitignore that ignores .on-loop/ so the audit log
  # never triggers clean_tree or no_session_untracked in tests.
  echo "initial" > "$REPO_DIR/README.md"
  printf '.on-loop/\n' > "$REPO_DIR/.gitignore"
  git -C "$REPO_DIR" add README.md .gitignore
  git -C "$REPO_DIR" commit -q -m "initial commit"

  # Push to origin and set upstream.
  git -C "$REPO_DIR" push -q origin main
  git -C "$REPO_DIR" branch --set-upstream-to=origin/main main 2>/dev/null || true

  # Export so bats test can reference them.
  export TEST_TMPDIR ORIGIN_DIR REPO_DIR
}

# ---------------------------------------------------------------------------
# teardown_temp_repo
# ---------------------------------------------------------------------------
teardown_temp_repo() {
  # Ensure we are not inside the temp dir before deleting it.
  cd / 2>/dev/null || true
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ---------------------------------------------------------------------------
# setup_git_shim
# ---------------------------------------------------------------------------
# Prepends a shim dir to PATH that intercepts `git tag -s ...` and rewrites it
# to `git tag -a ...`. All other git subcommands pass through unchanged.
#
# Architect §7.2 contract: shim matches $1==tag && $2==-s.
# The coding agent's script invokes ( cd "$REPO_ROOT" && git tag -s ... ) so
# $1==tag, $2==-s is always the pattern.
setup_git_shim() {
  SHIM_DIR="$TEST_TMPDIR/shim"
  mkdir -p "$SHIM_DIR"

  # Detect the real git binary before we prepend ourselves to PATH.
  local real_git
  real_git=$(command -v git)

  cat > "$SHIM_DIR/git" <<SHIM
#!/usr/bin/env bash
# Shim: intercept 'git tag -s' and redirect to 'git tag -a'.
if [[ "\$1" == "tag" && "\$2" == "-s" ]]; then
  shift 2
  exec ${real_git} tag -a "\$@"
fi
exec ${real_git} "\$@"
SHIM

  chmod +x "$SHIM_DIR/git"

  # Save original PATH for teardown.
  ORIGINAL_PATH="$PATH"
  export PATH="$SHIM_DIR:$PATH"
  export SHIM_DIR ORIGINAL_PATH
}

# ---------------------------------------------------------------------------
# restore_git_shim
# ---------------------------------------------------------------------------
# Not normally called explicitly (teardown_temp_repo handles cleanup via rm),
# but available if a test wants to restore PATH between sub-invocations.
restore_git_shim() {
  if [[ -n "${ORIGINAL_PATH:-}" ]]; then
    export PATH="$ORIGINAL_PATH"
  fi
}

# ---------------------------------------------------------------------------
# clean_audit_log
# ---------------------------------------------------------------------------
# Removes .on-loop/release-log.json from REPO_DIR.
# Call between assertions to verify incremental audit entries.
clean_audit_log() {
  rm -f "$REPO_DIR/.on-loop/release-log.json"
}

# ---------------------------------------------------------------------------
# last_audit_line
# ---------------------------------------------------------------------------
# Prints the last line of .on-loop/release-log.json (the most recent audit entry).
# Returns non-zero (via tail) if the file does not exist.
last_audit_line() {
  tail -n 1 "$REPO_DIR/.on-loop/release-log.json"
}

# ---------------------------------------------------------------------------
# audit_log_line_count
# ---------------------------------------------------------------------------
# Prints the number of lines in .on-loop/release-log.json, or 0 if absent.
audit_log_line_count() {
  if [[ -f "$REPO_DIR/.on-loop/release-log.json" ]]; then
    wc -l < "$REPO_DIR/.on-loop/release-log.json"
  else
    echo 0
  fi
}

# ---------------------------------------------------------------------------
# make_behind
# ---------------------------------------------------------------------------
# Makes the REPO_DIR/main behind origin/main by:
#   1. Cloning origin into a helper directory.
#   2. Committing and pushing a new commit from the helper clone.
#   3. Running `git fetch origin` (no merge) in REPO_DIR so the tracking
#      ref origin/main advances but HEAD does not.
#
# After this, REPO_DIR main is 1 commit behind origin/main.
make_behind() {
  local helper_dir="$TEST_TMPDIR/helper_behind"
  git clone -q "$ORIGIN_DIR" "$helper_dir"
  git -C "$helper_dir" config user.email "helper@example.com"
  git -C "$helper_dir" config user.name  "Helper User"
  git -C "$helper_dir" config commit.gpgsign false

  # The bare origin's HEAD may point to 'master' (git default) even though the
  # actual branch is 'main'. A plain `git clone` will land on an orphan 'master'.
  # We must explicitly track origin/main.
  git -C "$helper_dir" checkout --track origin/main -b main 2>/dev/null \
    || git -C "$helper_dir" checkout -b main origin/main 2>/dev/null \
    || git -C "$helper_dir" checkout main 2>/dev/null \
    || true

  echo "behind-push" > "$helper_dir/behind.txt"
  git -C "$helper_dir" add behind.txt
  git -C "$helper_dir" commit -q -m "helper commit (make_behind)"
  git -C "$helper_dir" push -q origin main

  # Fetch only — do NOT merge so REPO_DIR/main stays behind.
  git -C "$REPO_DIR" fetch -q origin main
}

# ---------------------------------------------------------------------------
# make_ahead
# ---------------------------------------------------------------------------
# Makes the REPO_DIR/main ahead of origin/main by committing locally without
# pushing.
#
# After this, REPO_DIR main is 1 commit ahead of origin/main.
make_ahead() {
  echo "ahead-commit" > "$REPO_DIR/ahead.txt"
  git -C "$REPO_DIR" add ahead.txt
  git -C "$REPO_DIR" commit -q -m "local commit (make_ahead)"
}
