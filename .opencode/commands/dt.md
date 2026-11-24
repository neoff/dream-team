---
description: "dream-team: resume the pipeline, or start a new one if there is none; flags --new, --issue, --add"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --bg --stdin <<'DT_EOF'
<dt mode="auto">$ARGUMENTS</dt>
DT_EOF`
</dt-out>

Relay the text from the dt-out block to the user verbatim. Do nothing else: no files, no commands, no roles.
