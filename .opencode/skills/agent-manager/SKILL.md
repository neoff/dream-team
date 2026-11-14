---
name: agent-manager
description: 'Справка по оркестратору пайплайна dream-team (dt-run.sh) и агенту-входу agent-manager. Пайплайн ведёт скрипт, а не модель.'
---

<note>
Пайплайн ведёт детерминированный скрипт `.opencode/skills/agent-manager/dt-run.sh`:
запускает роли отдельными `opencode run --agent agent-<роль>`, читает STATUS из handoff,
пишет состояние, обрабатывает правки (/dt-add) и беклог (/dt-issue).
Агент `agent-manager` (`.opencode/agents/agent-manager.md`) — только вход для слэш-команд:
пересказывает ответ скрипта, сам ничего не делает.
</note>

<references>
- `dt-commands.md` — команды /dt…, оркестратор, сторожа, гигиена сессий
- `state-machine.md` — стадии, переходы, формат состояния (state.env)
- `.opencode/skills/agent-pipeline/pair-protocol.md` — цикл doer↔critic
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — формат handoff
</references>
