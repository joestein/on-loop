## Portable runtime rules

These rules adapt the bundled workflow to the current coding tool and take
precedence over tool-specific assumptions in the reference documents.

- Use the model and provider selected in the host tool. Role names describe
  responsibilities, not model IDs. Do not switch providers, request another
  provider's key, or assume Opus/Sonnet are available.
- Resolve instruction paths such as `agents/coding.md`, `commands/on-test.md`,
  `skills/quality-gate/SKILL.md`, and `shared/AGENT_PERSONA.md` relative to this
  skill's `references/` directory. Resolve project paths (`.on-loop/`, source
  files, roadmap, Git metadata) relative to the user's project. Never write
  session state or application code into the installed skill directory.
- Read `references/shared/AGENT_PERSONA.md` and
  `references/shared/COMMUNICATION_PROTOCOL.md` before starting a workflow.
  Read the relevant role document before each phase. `@shared/...` references
  mean read the bundled document; do not assume automatic context inclusion.
- Map Read/Glob/Grep to the host's file-reading and search tools, Write/Edit
  to its editing tools, and Bash to its command runner. Respect host permissions.
  If a required capability is unavailable, report the blocked operation and
  preserve resumable state rather than claiming it ran.
- When the host supports delegation and permits its use, dispatch roles with
  their bundled instructions, session path, project path, and required context.
  Otherwise perform the roles sequentially in the current session, writing
  separate role notes and applying the same quality gates. DOC and BUILD can
  run sequentially. Do not claim independent review or parallel execution when
  one session performed those roles.
- Only the orchestrator role writes phase state. Security and reviewer roles
  may write their own notes but must not change application source. Native
  Claude tool allowlists are not installed by this adapter; these role limits
  are instructions, not a replacement for the host's permission controls.
- Respect the host's workspace instructions. Cloud tasks already run in an
  isolated checkout; use it and do not create another Git worktree unless the
  user explicitly requests one. When using the current checkout, record its
  actual path as `worktree_path`. Never remove the current checkout on cleanup.
  In other environments, follow the user's workspace policy. The historical
  `.claude/worktrees/` path in references does not require Claude Code.
- Read and update the host's project instructions (`AGENTS.md` for Codex,
  `GEMINI.md` for Gemini CLI, and `AGENTS.md` for OpenCode) where the bundled
  documentation instructions mention `CLAUDE.md`. Preserve existing project
  conventions. Use actual host-provided commit attribution, or omit it.
- Claude Stop/PostToolUse hooks are not installed in other hosts. Explicitly
  append changes to the session's `changes.log` and update state at phase
  boundaries. Report active sessions at completion or interruption.
- Obtain any required authorization through the host before pushing, opening
  a PR, tagging, or performing destructive cleanup. Use existing authentication;
  do not copy credentials into session logs. GitHub CLI/API access is needed
  only for workflows that use GitHub, not local planning, coding, or review.
- The source of this workflow is a Claude plugin. Instructions about changing
  `.claude-plugin` versions apply only when those files exist in the project
  being developed. Do not create Claude metadata in unrelated projects.

Follow the selected workflow below with the user's supplied arguments.
