# Work handoff — dream-team agent pipeline

State snapshot as of 2026-11-04 (updated by the v3/v4/v5 sections below). This folder (`wirellm`) was the
debug copy/source; it can be moved. Below is everything needed to continue from any point.

## What this is

A multi-agent pipeline for **opencode**: 3 antagonistic pairs (planner⇄critic,
coder⇄reviewer, tester⇄debugger) under a Manager-dispatcher. Full architecture description —
in `HANDOFF.md` next to this file. This file is about the work status and how to continue.

## Repositories and state (at snapshot time)

| what | repo | branch | HEAD | note |
|-----|------|-------|------|------------|
| source (debug copy) | `git@github.com:neoff/crypto-bits-ai.git` | `wirellm` | `4c5d7d8` | this folder |
| distribution | `git@github.com:neoff/dream-team.git` | `main` | `e77632b` | **public**, with install.sh |
| validation ground | `crypto-bits-ai` (locally `../wirellm-skiltest`) | `skill-test` | merge `da5ec91` | emailvalidate run to `done` |

- `crypto-bits-ai` branch `main` — EMPTY by design, do NOT touch.
- `dream-team` — clean distribution: `.opencode/` + `HANDOFF.md` + `README.md` + `install.sh` +
  `.gitignore`. Without `.planning/` and without test code.

## Install / update (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
```

Asks for the harness (mahcode / opencode / claude / both) and scope (local / global). install == update
(re-running overwrites our files). Non-interactively:
`DREAM_TEAM_HARNESS=mahcode|opencode|claude|both DREAM_TEAM_SCOPE=global|local`.
Paths: opencode `~/.config/opencode/{agents,skills}` | `.opencode/…`; claude
`~/.claude/{agents,skills}` | `.claude/…`.

## Running the pipeline (v2, historical)

```bash
cd <project with .opencode/>
opencode run --agent agent-manager "Your task"
opencode run --standalone --agent agent-manager "resume"   # resume an interrupted run
```

Resume lessons (important): there is NO `--resume` flag; resume = the message `resume` (no dashes).
Canonical — `--standalone` (root in cwd, sees `.planning/`); the shared daemon `:4096` may be
rooted in another folder → "no state". `-s <id>` — only for live viewing in the TUI
(brings up stale context, may push the step back). The resume-until-`done` loop is run by a wrapper
OUTSIDE, not by the manager (shell-opencode is forbidden for it — anti-recursion).

## Done

- Re-architecture into antagonistic pairs + dispatcher; roles are subagents with a fresh context,
  exchange through handoff files on disk; per-step sync of `pipeline-state.json`.
- Runaway recursion closed (PROHIBITIONS for the manager on shell-opencode / self-spawn / skill entry).
- Stop-short fix: the manager does not report to the user before `done`/`blocked`.
- Resume fix (the message `resume`, not a flag) + the `--standalone` lesson.
- Path fix for `state-machine.md` (lives in `agent-manager/`).
- End-to-end validation on `emailvalidate` → `done`: TDD RED→GREEN, coverage 98.6%, fuzzing
  13.3M execs, `-race`, ReDoS/CRLF — clean. No recursion.
- Moved to a separate public repo `dream-team` + `install.sh` (curl|bash, install==update),
  tested end-to-end (local/global, update idempotency, .gitignore block).

## v3: orchestrator script instead of an LLM manager (2026-11-05)

- The pipeline is run by `skills/agent-manager/dt-run.sh` (bash, deterministic): role = a separate
  `opencode run --standalone --agent agent-<role>`, exact input/output handoff paths,
  transition by `## STATUS` (`transition()`), state in `state.env` (JSON is generated).
  `dt-lib.sh` — shared (state, pid lock, archives, new/replan/cycle/finalize), `dt.sh` — input
  parsing, `dt-cli.sh` — entry (`--status/--log/--stop/--bg/--stdin`). `agent-manager` — only
  relays the reply for slash commands.
- Why: the LLM manager on `wirellm/main` skipped the review/test pairs, did not keep state, did not
  replan between steps, wrote code itself, spawned itself (`permissions` did not hold).
- Watchers: an amendment interrupts the role within seconds → replan; stop; timeout; a "hung" `opencode
  run`; an orphan after kill -9. Hygiene: role sessions → export to `sessions/` + delete (otherwise
  the background service resurrects them — zombies); uncommitted role junk → `stray/step-NN/`;
  `.planning/` → `.git/info/exclude`.
- Tests: `bash tests/run.sh` — 10 scenarios on an opencode mock (`tests/bin/opencode`), ~2 min.
- Live check (scratchpad, `wirellm/main`): Fib → `/dt-add Seq` during the coder (interrupted within
  1 s, replan with a Seq wave) → 4 waves → test (debugger `clean`) → CLI backlog → cycle 2 → done.
  51 steps, 40 sessions, all deleted, no processes/lock left, tests green.
- opencode v2.0.32 lessons: commands from `{command,commands}/**/*.md`; `` !`cmd` `` in a template runs
  BEFORE the model; `run -- "msg"` duplicates the message; without `</dev/null` `run` waits for stdin; the service
  `opencode serve --service` resumes interrupted sessions; a role with `mode: subagent`
  is launched via `--agent`; model globs do not see `.planning/`.

## Open / TODO

1. **claude harness** not adapted (postponed). With the orchestrator it became simpler: only a way
   to run a role in Claude Code (`claude -p --agent …`) instead of `opencode run` in `run_role` is needed.
2. Slash commands in the TUI were checked by simulating template expansion, not by hand in the TUI — run
   `/dt-new`, `/dt-status`, `/dt-add` in a live TUI.
3. Roles still put `coverage.out` and temp files in the root (the watcher moves them to `stray/`) —
   the hint in the tester/reviewer/coder guides can be tightened.
4. A global install (`~/.config/opencode`) with the orchestrator has not been run.

## File map

```
.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md
.opencode/skills/agent-pipeline/{SKILL,README,workflow,pair-protocol,handoff-protocol}.md
.opencode/skills/agent-pipeline-run/SKILL.md
.opencode/skills/agent-manager/{SKILL,state-machine,dt-commands}.md
.opencode/skills/agent-manager/dt-{run,cli,lib}.sh, dt.sh   # orchestrator and entry
.opencode/commands/dt*.md                                  # slash commands
tests/run.sh, tests/bin/opencode                           # orchestrator mock tests
.opencode/skills/agent-<role>/{SKILL,*-guide}.md
.mahcode/                                                  # v4 MCP version for mahcode
HANDOFF.md        # pipeline architecture (detailed)
WORK-HANDOFF.md   # this file
```

## How to continue after moving the folder

1. The folder is self-contained (`.opencode/` + both handoffs). Git history — in the `crypto-bits-ai` repo,
   branch `wirellm`; you can re-init or clone `dream-team` if you like.
2. Make edits in `.opencode/` / `.mahcode/`, push to `main` of `dream-team` — the distribution updates,
   `curl|bash` pulls it.
3. Next step per plan — item 1 of "Open": native Claude Code adaptation.

## v4: mahcode + MCP, no bash (2026-11-22)
- Scheme: manager (mahcode session; entry — a block in AGENTS.md, `@dream-team new|add|issue|status|continue|stop`)
  → pair leads as separate sessions via the mahcode MCP → roles also as top-level sessions. Models —
  `.mahcode/dream-team.yaml` (manager / leads / roles.*). Files: `.mahcode/skills/dream-team/`
  (SKILL, manager, lead, mcp, intake, handoff-protocol, roles/), `.mahcode/templates/AGENTS.dream-team.md`.
  Install: `install.sh` (DREAM_TEAM_HARNESS=mahcode, the default) and `install.ps1` (Windows).
- Lessons: on external engines `@skill` is not injected (entry through AGENTS.md) and steer into the current turn
  does not arrive → signals via files: `inbox/` (commands to the manager, any session writes them) and `interrupt.md`
  (manager → lead). Engines cut an MCP call after 300 s → `wait_for_session` only in ≤ 60 s chunks.
- The mahcode MCP is registered globally: ~/.codex/config.toml, ~/.claude.json,
  ~/.gemini/antigravity/mcp_config.json (backups *.bak-20261121-*).
- Live tests (scratchpad mc-e2e2/3, manager+leads codex/gpt-6-luna, roles wirellm/main):
  plan → code (waves) → test → done; `add:` from a separate session → inbox → interrupt → replan →
  Seq implemented. `issue:` got lost in the test: the intake session on wirellm/main wrote the file in the wrong format
  and started writing code itself → the manager now parses the inbox by content, the prohibition in intake
  is tightened. The issue → cycle 2 path has NOT been re-run.
- mahcode (session c1caad): subagents on external engines fixed (3948adc / 0a3f9d1, daemon restarted);
  the agent profile for primary sessions and MCP passthrough to external engines — await the user's decision.

## v5: everything in English (2026-11-24)
- All prompts, skills, agents, commands, script messages, tests and docs translated to English: fewer
  tokens per turn. Agents reply to the user in the user's language (manager.md, agent-manager.md).
- Coupled strings changed together: `## User text` (dt.sh intake ↔ dt-lib.sh user_text), `EXACTLY into the file`
  (dt-run.sh prompt ↔ tests/bin/opencode), `AMENDMENT`/`STOP` in interrupt.md (manager.md ↔ lead.md),
  "You are the LEAD of the … pair" / "You are the "…" role" (manager.md / lead.md ↔ AGENTS template).
- `bash tests/run.sh` — 10/10 after the translation. Already-installed projects need `install.sh` re-run
  to pick up the new AGENTS.md block (it replaces the block by markers).
