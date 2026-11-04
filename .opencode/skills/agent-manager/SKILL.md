---
name: agent-manager
description: 'Справка по роли Менеджера пайплайна. Менеджер реализован как opencode primary-агент (.opencode/agents/agent-manager.md); он раздаёт задачи парам ролей-сабагентов и маршрутизирует между парами.'
---

<note>
Менеджер — это АГЕНT, а не skill. Исполняемая роль живёт в
`.opencode/agents/agent-manager.md` (mode: primary). Этот файл — только справка.
Запуск пайплайна: см. `.opencode/skills/agent-pipeline-run/SKILL.md`.
</note>

<model>
Парная модель. Менеджер — диспетчер: раздаёт работу трём антагонистичным парам и
маршрутизирует между ними. Сам работу не делает и качество не оценивает.

- пара plan: planner (doer) ↔ critic (critic) → подписанный plan.md
- пара code: coder (doer) ↔ reviewer (critic) → одобренный код (по волнам)
- пара test: tester (doer) ↔ debugger (critic) → вердикт clean / bugs-found

Цикл ВНУТРИ пары Менеджер крутит механически (ограничение opencode: вложенность
subagent = 1). Содержательную оценку даёт critic-роль пары.
</model>

<references>
- `.opencode/skills/agent-pipeline/workflow.md` — обзор архитектуры
- `.opencode/skills/agent-manager/state-machine.md` — стадии, переходы между парами, схема pipeline-state.json (v2)
- `.opencode/skills/agent-pipeline/pair-protocol.md` — механика цикла doer↔critic
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — формат handoff, гигиена контекста
</references>

<state_files>
`.planning/agent-pipeline/`:
- `pipeline-state.json` — состояние (stage, current_pair, pair_iteration, step, roles, config)
- `handoffs/step-NN-<role>.md` — handoff каждого шага
- `task-context.md`, `plan-draft.md`, `plan.md`, `critique.md`, `approval-*.md`
- `code-summary.md`, `review-report.md`, `test-report.md`, `debug-report.md`, `clean-report.md`
- `bug-reports/*.md`
</state_files>
