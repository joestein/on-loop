# Using On-Loop with other coding tools

The portable adapter packages the existing 18 command workflows and 4 supporting
skills as 22 self-contained [Agent Skills](https://agentskills.io). It includes
the same role instructions, session schemas, roadmap coordination, and quality
gates as the Claude Code plugin. No model API client or provider key is bundled.

## Install in a project

Use Python 3.9 or later. Run from your On-Loop checkout, choosing the tool and
the project where you want to use the workflows:

```bash
python3 bin/on-loop-export --tool codex --destination /path/to/your-project
python3 bin/on-loop-export --tool gemini --destination /path/to/your-project
python3 bin/on-loop-export --tool opencode --destination /path/to/your-project
```

| Tool | Project skill directory | Model selection |
|------|-------------------------|-----------------|
| Codex | `.agents/skills/` | Inherits the host's selected model/provider |
| Gemini CLI | `.gemini/skills/` | Inherits the host's selected model/provider |
| OpenCode | `.opencode/skills/` | Inherits the host's selected model/provider |
| Other Agent Skills hosts (`--tool agent-skills`) | `.agents/skills/` | Inherits the host's selected model/provider |

Each installed skill includes its reference documents and license. The export
does not depend on the original On-Loop checkout after installation and does not
copy Git metadata, session logs, credentials, or Claude's hooks/settings. It does
not install the host coding tool itself or the separate `on-loop-tag` CLI.

Identical exports can be repeated. If a generated file differs, the exporter
stops before writing anything. Preserve local changes, then remove the affected
On-Loop skill directories and export again to update. Existing unrelated skills
are left alone. Symlinked destination paths are refused.

Restart the host or reload its skills. In Codex, invoke a workflow explicitly:

```text
$on-loop Build a paginated tasks API
$on-test src/tasks
$on-review Review the current changes
$on-loop-status
```

In Gemini CLI, use `/skills list` to check discovery, then ask it to activate the
`on-loop` (or `on-test`, `on-review`, etc.) skill with your request. In OpenCode,
ask it to load the named skill through its native `skill` tool. These are Agent
Skills, not registrations of Claude's slash-command syntax in other hosts.

## What changes across tools

The host chooses the model. A provider is usable only if that coding tool
supports it and its authentication/network access are configured. This adapter
does not make every model available in every tool or establish model quality.

Roles use native delegation when the host permits it. Otherwise the current
session performs each phase sequentially and writes separate role notes; that
fallback does not provide independent review. Security/reviewer instructions
still prohibit application edits, but native permission enforcement stays with
the host. The export does not recreate Claude's tool allowlists.

The adapter explicitly records changes and state because Claude's Stop and
PostToolUse hooks are not installed. Documentation uses the host's project
instruction file. Commits use actual host attribution, when supplied. In an
isolated cloud checkout, the workflow reuses that checkout unless the user asks
for another worktree. GitHub operations still require `gh` and appropriate access.

## Validation

```bash
make test-portable
make lint test check
```

The portable tests exercise all target paths, complete reference bundles, model
inheritance, repeated installation, conflicts, symlink protection, and CLI errors.
They run locally without provider credentials. A passing export test does not
establish that a live model completed the SDLC pipeline in another host.

Discovery paths follow the host documentation:
[Codex](https://developers.openai.com/codex/skills),
[Gemini CLI](https://geminicli.com/docs/cli/skills/), and
[OpenCode](https://opencode.ai/docs/skills/).
