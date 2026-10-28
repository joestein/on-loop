# Makefile — on-loop-tag Layer 1
#
# Standard developer targets for the on-loop-tag release-tagging script.
# Spec: .on-loop/sessions/20260520_214047_on-loop-tag-layer-1/agent-notes/architect.md

# Recipes use bash-only constructs ([[ ]] in install/uninstall); pin SHELL
# so non-bash /bin/sh defaults (dash on Debian) do not break recipes.
SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help test test-portable lint check install uninstall

# ---------------------------------------------------------------------------
# help — list all targets with descriptions
# ---------------------------------------------------------------------------
help:
	@printf '%-20s %s\n' "Target" "Description"
	@printf '%-20s %s\n' "------" "-----------"
	@printf '%-20s %s\n' "test"      "Run Bats and portable skill tests"
	@printf '%-20s %s\n' "test-portable" "Run portable skill tests (Python 3)"
	@printf '%-20s %s\n' "lint"      "Run shellcheck on bin/on-loop-tag"
	@printf '%-20s %s\n' "check"     "Smoke-check bin/on-loop-tag --version"
	@printf '%-20s %s\n' "install"   "Symlink bin/on-loop-tag to ~/.local/bin/"
	@printf '%-20s %s\n' "uninstall" "Remove ~/.local/bin/on-loop-tag symlink"

# ---------------------------------------------------------------------------
# test — bats test suite
#
# --jobs 1 is mandatory: each test mutates PATH and cwd.
# Architect OQ-4 and testing-agent notes both require sequential execution.
# ---------------------------------------------------------------------------
test:
	@if ! command -v bats >/dev/null 2>&1; then \
		printf 'ERROR: bats not found. Install it with:\n'; \
		printf '  sudo dnf install -y bats          # Fedora\n'; \
		printf '  sudo apt-get install -y bats      # Debian/Ubuntu\n'; \
		printf '  git clone https://github.com/bats-core/bats-core.git && sudo bats-core/install.sh /usr/local\n'; \
		exit 1; \
	fi
	bats --jobs 1 tests/test_on_loop_tag.bats
	$(MAKE) test-portable

test-portable:
	python3 -m unittest discover -s tests -p 'test_*.py' -v

# ---------------------------------------------------------------------------
# lint — shellcheck SAST
#
# Exits non-zero on any warning or error (shellcheck default behaviour).
# ---------------------------------------------------------------------------
lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		printf 'ERROR: shellcheck not found. Install it with:\n'; \
		printf '  sudo dnf install -y ShellCheck    # Fedora\n'; \
		printf '  sudo apt-get install -y shellcheck  # Debian/Ubuntu\n'; \
		exit 1; \
	fi
	shellcheck bin/on-loop-tag

# ---------------------------------------------------------------------------
# check — smoke test: run the script's --version flag to confirm it is
#         executable, parses correctly, and can read plugin.json.
# ---------------------------------------------------------------------------
check:
	bin/on-loop-tag --version

# ---------------------------------------------------------------------------
# install — symlink bin/on-loop-tag into ~/.local/bin/
#
# Idempotent: removes any existing file/link before creating a new symlink
# so that re-running this target after a path change is safe.
# Mirrors the logic in setup/fedora-bootstrap.sh §6.1.
# ---------------------------------------------------------------------------
install:
	@mkdir -p "$(HOME)/.local/bin"
	@SCRIPT_SRC="$(CURDIR)/bin/on-loop-tag"; \
	SCRIPT_DST="$(HOME)/.local/bin/on-loop-tag"; \
	if [[ ! -x "$$SCRIPT_SRC" ]]; then \
		printf 'ERROR: %s missing or not executable\n' "$$SCRIPT_SRC" >&2; \
		exit 1; \
	fi; \
	if [[ -L "$$SCRIPT_DST" || -e "$$SCRIPT_DST" ]]; then \
		rm -f "$$SCRIPT_DST"; \
	fi; \
	ln -s "$$SCRIPT_SRC" "$$SCRIPT_DST"; \
	printf 'Linked %s -> %s\n' "$$SCRIPT_DST" "$$SCRIPT_SRC"; \
	case ":$$PATH:" in \
		*":$(HOME)/.local/bin:"*) printf 'PATH OK: ~/.local/bin is on PATH\n' ;; \
		*) printf 'WARNING: ~/.local/bin is not on PATH. Add to ~/.bashrc:\n'; \
		   printf '    export PATH="$$HOME/.local/bin:$$PATH"\n' ;; \
	esac

# ---------------------------------------------------------------------------
# uninstall — remove the ~/.local/bin/on-loop-tag symlink (no-op if absent)
# ---------------------------------------------------------------------------
uninstall:
	@SCRIPT_DST="$(HOME)/.local/bin/on-loop-tag"; \
	if [[ -L "$$SCRIPT_DST" || -e "$$SCRIPT_DST" ]]; then \
		rm -f "$$SCRIPT_DST"; \
		printf 'Removed %s\n' "$$SCRIPT_DST"; \
	else \
		printf 'Nothing to remove: %s does not exist\n' "$$SCRIPT_DST"; \
	fi
