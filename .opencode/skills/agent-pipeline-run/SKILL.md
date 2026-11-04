---
name: agent-pipeline-run
description: 'Точка входа агентского пайплайна. Запускает задачу через primary-агента agent-manager, который раздаёт работу парам ролей-сабагентов.'
---

<arguments>$ARGUMENTS</arguments>

<objective>
Передать задачу Менеджеру пайплайна. Менеджер (opencode primary-агент) раздаёт работу трём
парам сабагентов (planner+critic, coder+reviewer, tester+debugger) и маршрутизирует между
ними до done/blocked.
</objective>

<how_to_start>
⚠️ Команды ниже — для ЧЕЛОВЕКА в терминале. Если ты — агент (тем более сам agent-manager),
НЕ исполняй их через shell: запуск `opencode run` из агента порождает рекурсию (менеджер
запускает менеджера) и жжёт токены. Агент стартует пайплайн не отсюда, а по своему
системному промпту (`.opencode/agents/agent-manager.md`).

Менеджер — это АГЕНT (`.opencode/agents/agent-manager.md`, mode: primary), а не skill.
Человек запускает одним из способов:

```bash
# CLI, разово
opencode run --agent agent-manager "Создать REST API для пользователей с JWT авторизацией"

# интерактивно: выбрать агента agent-manager и дать задачу
opencode
> (switch agent → agent-manager) Создать CLI утилиту CSV→JSON с валидацией схемы

# продолжить прерванный прогон
opencode run --agent agent-manager "resume"
```
</how_to_start>

<arguments_spec>
- `<task>` — описание задачи (всё до первого `--флага`)
- `resume` (как сообщение) — продолжить прерванный пайплайн из pipeline-state.json
- `--phase <n>` / `--wave <n>` — точка входа при многофазном плане
</arguments_spec>

<references>
- `.opencode/skills/agent-pipeline/workflow.md` — обзор парной архитектуры
- `.opencode/skills/agent-manager/state-machine.md` — стадии и переходы между парами
- `.opencode/skills/agent-pipeline/pair-protocol.md` — цикл doer↔critic
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — handoff и гигиена контекста
</references>
