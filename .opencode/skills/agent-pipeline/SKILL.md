---
name: agent-pipeline
description: 'Обзор парного агентского пайплайна: три антагонистичные пары (planner+critic, coder+reviewer, tester+debugger) под диспетчером-Менеджером. Исполняется агентами в .opencode/agents/.'
---

<overview>
Пайплайн разработки на трёх антагонистичных парах ролей, которыми диспетчеризует Менеджер.
Каждая роль — opencode subagent со свежим контекстом; общение только через файлы на диске.

- пара plan: planner (doer) ⇄ critic (critic) → подписанный plan.md
- пара code: coder (doer) ⇄ reviewer (critic) → одобренный код (по волнам)
- пара test: tester (doer) ⇄ debugger (critic) → вердикт clean / bugs-found

Менеджер раздаёт задачи и маршрутизирует МЕЖДУ парами; цикл ВНУТРИ пары он крутит
механически по STATUS в handoff, не оценивая качество (это делает critic-роль пары).
</overview>

<execution>
Исполняемые роли — агенты, НЕ skills:
`.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md`.
Запуск: `opencode run --agent agent-manager "<задача>"` (см. `agent-pipeline-run`).
</execution>

<stages>
init → planning → coding → testing → done
(testing: bugs-found → снова coding). Подробности — state-machine.md.
</stages>

<references>
- `workflow.md` — архитектура и контракты пар
- `state-machine.md` (в agent-manager/) — стадии, переходы, схема pipeline-state.json
- `pair-protocol.md` — механика цикла doer↔critic
- `handoff-protocol.md` — формат handoff, гигиена контекста
- `README.md` — полный обзор, запуск, артефакты, структура
</references>
