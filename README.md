# dream-team

A multi-agent development pipeline for [opencode](https://opencode.ai): three **antagonistic
pairs** of roles under a Manager-dispatcher, with strict context hygiene (all state is on
disk, every role starts from a clean context).

```
        Manager (primary — hands out tasks and routes BETWEEN pairs)
          │                    │                    │
      PLAN pair            CODE pair            TEST pair
   planner ⇄ critic     coder ⇄ reviewer    tester ⇄ debugger
```

- **planner ⇄ critic** → signed `plan.md`
- **coder ⇄ reviewer** → approved code (TDD, by waves)
- **tester ⇄ debugger** → verdict `clean` / `bugs-found`

Inside a pair the doer and critic iterate until consensus; only then does the pair hand the Manager
a joint result. The Manager does not judge quality — it runs the loop mechanically and routes.

## dream-team for mahcode (main version)

The manager is a regular mahcode session. Pair leads and roles are separate sessions launched
via the mahcode MCP (`create_session` / `send_message` / `wait_for_session`). There is no bash at runtime:
only markdown instructions and MCP calls, so this version also works on Windows.

```
you / CTO session ⇄ MANAGER ──MCP──► plan LEAD ──► planner ⇄ critic
                                    ► code LEAD ──► coder ⇄ reviewer   (by waves)
                                    ► test LEAD ──► tester ⇄ debugger
```

- A lead runs its pair to consensus itself and returns one verdict to the manager
  (`approved` / `clean` / `bugs-found` / `blocked` / `interrupted`).
- The manager only decides which pair runs next and talks to you or the CTO.

**Install into a project** (from the project root):

```bash
curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | DREAM_TEAM_HARNESS=mahcode bash
```
```powershell
irm https://raw.githubusercontent.com/neoff/dream-team/main/install.ps1 | iex     # Windows
```

Installs `.mahcode/skills/{dream-team,agent-*}`, `.mahcode/dream-team.yaml` (if missing),
the entry block in `AGENTS.md`, `.mcp.json` with the mahcode server, and runs `mahcode mcp trust`.

**Models** are set per project in `.mahcode/dream-team.yaml`: `manager`, `leads` and
`roles.<role>`. Any mahcode id works: `codex/gpt-6-luna#xhigh`, `claude-code/opus`,
`antigravity/…`, `wirellm/main`, `opencode-go/…`. The manager and leads need the mahcode MCP:
`wirellm/*` always has it, while for codex, claude-code and agy the MCP must be registered once
in their global configs:

```toml
# ~/.codex/config.toml
[mcp_servers.mahcode]
command = "mahcode"
args = ["mcp", "serve"]
```
```bash
claude mcp add --scope user mahcode -- mahcode mcp serve          # Claude Code
# Antigravity: ~/.gemini/antigravity/mcp_config.json → mcpServers.mahcode
```

**Commands** (in a mahcode session of the project or via MCP `send_message` from the CTO):
`@dream-team new: <task>` (or `new: @prompt.md`), `@dream-team add: <amendment>`,
`@dream-team issue: <addition>`, `@dream-team status`, `@dream-team continue`,
`@dream-team stop`. Artifacts live in `.planning/dream-team/` (`state.md`, `handoffs/`, `verdicts/`).
The manager replies in the language you write to it.

Current mahcode limitations (reported to its developer): stopping a parent does not interrupt a
subagent on an external engine, so roles are launched as separate sessions; `@skill` is not injected
for external engines, so the entry goes through `AGENTS.md`.

## Install (bash orchestrator for opencode)

One command (the same command installs and updates):

```bash
curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
```

Asks for the **harness** (mahcode / opencode / claude / both) and the **scope** (local — into the current project /
global — for all). Copies only its own agents/skills, other files in the target folder are left alone.
On a local install in a git project (or if there is a `.gitignore`) it adds the installed paths to
`.gitignore` (idempotent block `# >>> dream-team >>>`).

Non-interactively (in a pipe without a tty) it is controlled by variables:

```bash
DREAM_TEAM_HARNESS=opencode DREAM_TEAM_SCOPE=global \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash'
# HARNESS: mahcode|opencode|claude|both (default mahcode) · SCOPE: global|local (default local)
```

Target paths: opencode — `~/.config/opencode/{agents,skills,commands}` (global) or `.opencode/…` (local);
claude — `~/.claude/{agents,skills,commands}` (global) or `.claude/…` (local). claude is untested.

Manually (alternative): copy `.opencode/` into the root of your project.

## How it works

The pipeline is run by a **deterministic orchestrator script** `dt-run.sh`, not a model. It launches
each role as a separate `opencode run --agent agent-<role>` with a fresh context, gives it the
input handoff and the exact output path, reads `STATUS` and transitions per the state machine
(plan → code by waves → test → done / new cycle). Models work only inside roles.

While a role works the orchestrator watches for amendments (`/dt-add` interrupts the role within seconds and
goes to replanning), the stop command, timeouts and a "hung" process. It exports each role's session
to `.planning/agent-pipeline/sessions/` and deletes it from opencode, so that the
opencode background service does not "resurrect" interrupted roles.

## Commands

| TUI (opencode) | Terminal | What it does |
| --- | --- | --- |
| `/dt-new <task>` | `dt --new <task>` | new task (`--force` — over an unfinished one; old → archive) |
| `/dt-new @prompt.md` | `dt --new @prompt.md` | task from a file — for large prompts |
| `/dt` | `dt` | resume from where it stopped |
| `/dt-add <amendment>` | `dt --add <amendment>` | amendment: interrupt the current role, replan taking the done work into account |
| `/dt-issue <text>` | `dt --issue <text>` | to the backlog, no interruption; after `done` — a new cycle |
| `/dt-status` | `dt --status` | stage, pair, iteration, wave, current role, log |
| `/dt-log` | `dt --log [N]` · `dt --log -f` | orchestrator log |
| `/dt-stop` | `dt --stop` | stop (state is kept; resume — `/dt`) |

```bash
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'   # terminal
dt --new @prompt.md        # foreground (Ctrl-C = stop); dt --bg … — background
```

Slash commands start the orchestrator in the background and reply right away — the TUI stays free, watch
with `/dt-status`. Slash command limitation: a backtick `` ` `` in the text truncates it (that is how
opencode parses `` !`…` ``) — pass text with code as a file (`@prompt.md`).

Settings — environment variables: `DT_MAX_PAIR_ITERS` (5), `DT_MAX_TEST_ROUNDS` (3),
`DT_TIMEOUT_<ROLE>` in minutes (PLANNER 40, CRITIC 25, CODER 90, REVIEWER 30, TESTER 60,
DEBUGGER 60), `DT_MODEL` (role model), `DT_KEEP_SESSIONS=1` (do not delete role sessions),
`DT_ADD_INTERRUPT=step` (amendment — only at step boundaries).

Run artifacts are in `.planning/agent-pipeline/` (`run.log`, `state.env`, handoffs, plan,
reports, bug reports, cycle archives). The directory is automatically excluded from git
(`.git/info/exclude`).

## Documentation

Full description of the architecture, handoff protocol, state machine, recursion protection, resume
lessons and end-to-end validation results — in [HANDOFF.md](HANDOFF.md).

## Structure

```
.opencode/agents/            executable roles (opencode subagents)
  agent-manager.md           primary — slash-command entry (relays the orchestrator's reply)
  agent-{planner,critic,coder,reviewer,tester,debugger}.md
.opencode/commands/          slash commands /dt, /dt-{new,resume,issue,add,status,stop,log}
.opencode/skills/            protocols + role craft references
  agent-manager/dt-*.sh      orchestrator and entry (dt-run.sh, dt-cli.sh, dt.sh, dt-lib.sh)
.mahcode/                    MCP version for mahcode (skills, dream-team.yaml, AGENTS.md template)
tests/                       orchestrator tests on an opencode mock (bash tests/run.sh)
```
