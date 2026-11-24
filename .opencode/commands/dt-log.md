---
description: "dream-team: last 40 lines of the orchestrator log"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --log </dev/null`
</dt-out>

Relay the text from the dt-out block to the user verbatim. Do nothing else.
