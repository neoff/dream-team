<!-- dream-team: /dt commands and the dt-run.sh orchestrator -->
<purpose>
How the pipeline launch works. The pipeline is run NOT by a model but by the deterministic orchestrator script
`dt-run.sh`: it launches the roles itself, reads their STATUS, writes the state, handles amendments and the
backlog. Models work only inside roles (planner, critic, coder, reviewer, tester, debugger).
</purpose>

<files>
| File          | What it does                                                                |
| ------------- | --------------------------------------------------------------------------- |
| `dt-cli.sh`   | single entry: terminal and slash commands (`--status`, `--log`, `--stop`, `--bg`) |
| `dt.sh`       | message parsing → `ACTION=stop` (+MSG) or `ACTION=run`; intake, `new`         |
| `dt-run.sh`   | orchestrator: role loop per the state machine, watchers, session hygiene     |
| `dt-lib.sh`   | shared: state, lock, archives, `new` / `replan` / `cycle` / `finalize`        |
</files>

<commands>
| Slash command (TUI)       | Terminal (`alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'`) | What it does |
| ------------------------- | ------------------------ | ---------- |
| `/dt`                     | `dt`                     | resume; no pipeline → a task is needed (`/dt <task>`) |
| `/dt-new <task>`          | `dt --new <task>`        | new task; old → archive. Over an unfinished one — only with `--force` |
| `/dt-new @prompt.md`      | `dt --new @prompt.md`    | task from a file (huge prompts; backticks/quotes — no limits) |
| `/dt-resume`              | `dt --resume`            | resume from where it stopped |
| `/dt-add <amendment>`     | `dt --add <amendment>`   | task amendment: a live run interrupts the current role and replans |
| `/dt-issue <addition>`    | `dt --issue <text>`      | to the backlog: after `done` — a new cycle (done work + additions) |
| `/dt-status`              | `dt --status`            | stage, pair, iteration, wave, current role, elapsed time, log |
| `/dt-log`                 | `dt --log [N]`, `dt --log -f` | orchestrator log (`.planning/agent-pipeline/run.log`) |
| `/dt-stop`                | `dt --stop`              | stop: the role is interrupted, state is kept; resume — `/dt` |

Slash commands start the orchestrator in the background (`--bg`) and return immediately; the TUI stays free.
From the terminal `dt …` without `--bg` runs in the foreground (Ctrl-C = `--stop`).
`@path` text in `/dt-add`, `/dt-issue` is also read from the file.
Slash command limitation: a backtick in the text truncates it (that is how opencode parses
`` !`…` ``) — use `@file` for text with code.
</commands>

<orchestrator>
The `dt-run.sh` loop (one role = one `opencode run --agent agent-<role>` with a fresh context):

```
plan:  planner → critic ─needs-revision→ planner … ─approved→ planner[sign] ─approved→ code
code:  by waves (`### Wave X.Y:` in plan.md): coder → reviewer ─needs-revision→ coder …
       ─approved→ next wave | test
test:  tester → debugger ─needs-revision→ tester … ─bugs-found→ code[fix] → reviewer → test
       ─clean→ backlog empty ? done : new cycle (plan)
any role ─blocked→ blocked · pair iterations > DT_MAX_PAIR_ITERS → blocked
test rounds ≥ DT_MAX_TEST_ROUNDS → blocked
```

The role gets the input handoff path and the EXACT output path in its prompt; the orchestrator reads
the first word under `## STATUS`. No handoff / wrong STATUS → one retry with a remark
(`DT_MAX_NUDGES`), then blocked. State — `state.env` (canonical), `pipeline-state.json`
(generated), `history.jsonl`, `run.log`.

Watchers during a role (polled every `DT_POLL_SEC`, 3 s):
- `amendments/pending` not empty → the role is interrupted → replan (`DT_ADD_INTERRUPT=step` —
  wait for the step to finish);
- `stop.request` (`/dt-stop`) or Ctrl-C → the role is interrupted, the step repeats on resume;
- role timeout (`DT_TIMEOUT_<ROLE>`, min) and "hang" (handoff written, the process does not exit
  for longer than `DT_HANG_GRACE_SEC`) → the process is terminated, the result is taken from the handoff.

Hygiene:
- each role's session is exported to `sessions/step-NN-<role>.session.json` and deleted from
  opencode (`DT_KEEP_SESSIONS=1` — keep). Otherwise the opencode background service "resurrects"
  interrupted sessions, and zombie roles appear;
- `run.lock` = orchestrator pid; a second one does not start. An orphan role after `kill -9` is killed
  on the next start;
- `.planning/` is added to `.git/info/exclude`; reports a role put in the root
  are moved to `stray/`.
</orchestrator>

<transitions_on_input>
- **new**: old state → `archive/task-<id>-<ts>/`, scaffold, `task-context.md` (task
  verbatim), handoff to the planner, `state.env`.
- **add**: amendment → `amendments/pending/add-<ts>.md`. A live run picks it up within seconds;
  otherwise the orchestrator is started, and it replans right away: amendment → `amendments/applied/`,
  "Amendments" section in `task-context.md`, pass artifacts → `archive/replan-step-NN/`, the code
  stays and is taken into account in the new plan.
- **issue**: addition → `backlog/pending/issue-<ts>.md`. On `clean` the orchestrator archives
  the cycle into `archive/cycle-N/`, appends "Cycle N+1 — additions" to `task-context.md` and
  starts a new cycle with the planner.
- **resume**: on `done` with an empty backlog / `blocked` without amendments — refusal without starting a model.
</transitions_on_input>
