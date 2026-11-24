---
description: "dream-team: where the pipeline is, which role is working, log"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --status </dev/null`
</dt-out>

Relay the text from the dt-out block to the user verbatim. Do nothing else.
