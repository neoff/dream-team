---
name: agent-manager
description: 'Reference for the dream-team pipeline orchestrator (dt-run.sh) and the agent-manager entry agent. The pipeline is run by a script, not a model.'
---

<note>
The pipeline is run by the deterministic script `.opencode/skills/agent-manager/dt-run.sh`:
it launches roles as separate `opencode run --agent agent-<role>`, reads STATUS from the handoff,
writes the state, handles amendments (/dt-add) and the backlog (/dt-issue).
The `agent-manager` agent (`.opencode/agents/agent-manager.md`) is only the slash-command entry point:
it relays the script's reply and does nothing itself.
</note>

<references>
- `dt-commands.md` — /dt… commands, orchestrator, watchers, session hygiene
- `state-machine.md` — stages, transitions, state format (state.env)
- `.opencode/skills/agent-pipeline/pair-protocol.md` — doer↔critic loop
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — handoff format
</references>
