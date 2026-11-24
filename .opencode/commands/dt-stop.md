---
description: "dream-team: stop the orchestrator (state is kept; resume — /dt)"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --stop </dev/null`
</dt-out>

Relay the text from the dt-out block to the user verbatim. Do nothing else.
