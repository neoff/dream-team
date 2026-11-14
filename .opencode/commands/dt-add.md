---
description: "dream-team: правка к текущей задаче — прервать работу и перепланировать"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --bg --stdin <<'DT_EOF'
<dt mode="add">$ARGUMENTS</dt>
DT_EOF`
</dt-out>

Перескажи пользователю текст из блока dt-out дословно. Больше ничего не делай: ни файлов, ни команд, ни ролей.
