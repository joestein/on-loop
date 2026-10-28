#!/usr/bin/env bash
# Fedora bootstrap for the on-loop plugin.
#
# Assumes: you have already cloned this repo. Run from anywhere.
# Idempotent: re-running upgrades / re-registers without harm.
#
# Side effects:
#   - sudo dnf install of system packages
#   - sudo npm install -g @anthropic-ai/claude-code (only if claude is missing)
#   - writes under ~/.claude/ (marketplace registration, plugin install)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "==> Bootstrapping on-loop from: $REPO_DIR"

if ! command -v dnf >/dev/null 2>&1; then
  echo "ERROR: dnf not found. This script targets Fedora / RHEL-family systems." >&2
  exit 1
fi

echo "==> Installing system packages (sudo)"
sudo dnf install -y --best \
  git \
  tmux \
  python3 \
  nodejs \
  npm \
  gh \
  bats \
  util-linux

if ! command -v claude >/dev/null 2>&1; then
  echo "==> Installing Claude Code (sudo npm install -g)"
  sudo npm install -g @anthropic-ai/claude-code
else
  echo "==> Claude Code already installed: $(claude --version | head -1)"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run 'gh auth login' first, then re-run this script." >&2
  exit 1
fi

echo "==> Registering local marketplace at $REPO_DIR"
if ! claude plugin marketplace list 2>/dev/null | grep -q '^\s*❯ on-loop-marketplace'; then
  claude plugin marketplace add "$REPO_DIR"
else
  echo "    (already registered — updating)"
  claude plugin marketplace update on-loop-marketplace
fi

echo "==> Installing on-loop plugin (user scope)"
if ! claude plugin list 2>/dev/null | grep -q '^\s*❯ on-loop@on-loop-marketplace'; then
  claude plugin install on-loop@on-loop-marketplace
else
  echo "    (already installed)"
fi

echo "==> Installing on-loop-tag CLI to ~/.local/bin"
mkdir -p "$HOME/.local/bin"
SCRIPT_SRC="$REPO_DIR/bin/on-loop-tag"
SCRIPT_DST="$HOME/.local/bin/on-loop-tag"

if [[ ! -x "$SCRIPT_SRC" ]]; then
  echo "ERROR: $SCRIPT_SRC missing or not executable" >&2
  exit 1
fi

# Symlink so repo edits propagate; remove any stale link/file first (idempotent)
if [[ -L "$SCRIPT_DST" || -e "$SCRIPT_DST" ]]; then
  rm -f "$SCRIPT_DST"
fi
ln -s "$SCRIPT_SRC" "$SCRIPT_DST"
echo "    linked $SCRIPT_DST -> $SCRIPT_SRC"

# PATH check — non-fatal warning
case ":$PATH:" in
  *":$HOME/.local/bin:"*) echo "    PATH OK (~/.local/bin already on PATH)" ;;
  *) cat >&2 <<EOF
WARNING: ~/.local/bin is not on PATH. Add this to ~/.bashrc:
    export PATH="\$HOME/.local/bin:\$PATH"
Then re-source: source ~/.bashrc
EOF
    ;;
esac

echo
echo "==> Verification"
claude plugin list

cat <<'NOTE'

== Post-install ==
- If Claude Code is not authenticated, run `claude` once interactively to log in.
- Marketplace points at the on-disk repo; edits to this checkout immediately affect
  the installed plugin. Run `claude plugin marketplace update on-loop-marketplace`
  after schema-affecting changes if the plugin fails to reload.
- Plugin currently loads 22 skills (commands) + 8 agents; always-on cost ~1.1k tokens.
NOTE
