---
description: "dream-team: остановить оркестратор (состояние сохранится; продолжить — /dt)"
agent: agent-manager
---
<dt-out>
!`CLI=.opencode/skills/agent-manager/dt-cli.sh; [ -f "$CLI" ] || CLI="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; bash "$CLI" --stop </dev/null`
</dt-out>

Перескажи пользователю текст из блока dt-out дословно. Больше ничего не делай.
