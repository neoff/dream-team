---
name: agent-pipeline-run
description: 'Entry point of the dream-team agent pipeline: /dt… commands and dt-cli.sh. The pipeline is run by the orchestrator script dt-run.sh, roles are separate opencode agents.'
---

<arguments>$ARGUMENTS</arguments>

<objective>
Start or resume the pipeline. A human does this with a command (an agent has nothing to do here):
the orchestrator `agent-manager/dt-run.sh` runs the planner⇄critic, coder⇄reviewer,
tester⇄debugger pairs itself until done/blocked.
</objective>

<how_to_start>
⚠️ The commands below are for a HUMAN. An agent reading this runs none of them.

```bash
# opencode TUI
/dt-new <task>           # or /dt-new @prompt.md — task from a file
/dt                      # resume
/dt-add <amendment>      # amendment: interrupt the current role and replan
/dt-issue <addition>     # to the backlog: a new cycle after done
/dt-status · /dt-log · /dt-stop

# terminal
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'
dt --new @prompt.md      # foreground; dt --bg --new … — background
dt --status · dt --log -f · dt --stop
```
</how_to_start>

<references>
- `.opencode/skills/agent-manager/dt-commands.md` — commands, orchestrator, watchers, hygiene
- `.opencode/skills/agent-manager/state-machine.md` — stages, transitions, state format
- `.opencode/skills/agent-pipeline/pair-protocol.md` — doer↔critic loop
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — handoff and context hygiene
</references>
