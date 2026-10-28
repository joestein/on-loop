# Fedora VM bootstrap

Quick re-image runbook for the on-loop plugin on a fresh Fedora VM.

## TL;DR

```bash
# 1. Authenticate gh (interactive, one time)
gh auth login

# 2. Clone the repo
sudo mkdir -p /var/build && sudo chown "$USER:$USER" /var/build
git clone https://github.com/UlyssesModel/on-loop.git /var/build/on-loop

# 3. Bootstrap
bash /var/build/on-loop/setup/fedora-bootstrap.sh

# 4. First-time Claude Code auth (interactive)
claude
```

## What the script installs

| Component | How |
|---|---|
| `git`, `tmux`, `python3`, `nodejs`, `npm`, `gh` | `sudo dnf install` |
| Claude Code | `sudo npm install -g @anthropic-ai/claude-code` (skipped if already present) |
| on-loop marketplace | `claude plugin marketplace add <repo path>` (user scope, `~/.claude/`) |
| on-loop plugin | `claude plugin install on-loop@on-loop-marketplace` (user scope) |

## What it does NOT install

- **Docker** — not required by the plugin. Install separately if you need it (`sudo dnf install moby-engine` for Fedora's bundled Docker, or follow Docker CE's Fedora repo instructions).
- **Podman** — Fedora ships it by default; nothing to do.
- **uv, pnpm, yarn** — none are required.

## Side effects outside the repo

- `sudo dnf install` (system packages)
- `sudo npm install -g` (only if claude is missing; writes to `/usr/lib/node_modules`)
- `~/.claude/plugins/` (marketplace + plugin registration)
- `~/.claude/.credentials.json` is created when you authenticate Claude Code

## After re-image: what's lost vs. preserved

| | Lost on re-image | How to restore |
|---|---|---|
| `/var/build/on-loop` | yes | `git clone` (step 2) |
| `~/.claude/plugins/` | yes | re-run `setup/fedora-bootstrap.sh` |
| `~/.claude/.credentials.json` | yes | `claude` interactive (step 4) |
| `~/.config/gh/hosts.yml` | yes | `gh auth login` (step 1) |
| Pushed git history (this branch) | no — lives on GitHub | — |

## Notes

- The marketplace points at the on-disk clone, so any local edits to `/var/build/on-loop` immediately affect the installed plugin. After schema-affecting changes (e.g., `hooks/hooks.json`), run `claude plugin marketplace update on-loop-marketplace` to make Claude Code re-read the manifest.
- Verify after install: `claude plugin list` should show `on-loop@on-loop-marketplace` with status `✔ enabled`.
