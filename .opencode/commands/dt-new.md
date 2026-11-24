---
description: "dream-team: new task (text or @file; --force — over an unfinished one)"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --bg --stdin <<'DT_EOF'
<dt mode="new">$ARGUMENTS</dt>
DT_EOF`
</dt-out>

Relay the text from the dt-out block to the user verbatim. Do nothing else: no files, no commands, no roles.
