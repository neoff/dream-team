<!-- agent-pipeline workflow (pair model, subagents) -->
<purpose>
Оркестрация пайплайна тремя антагонистичными парами. Менеджер (primary) раздаёт задачи и
маршрутизирует между парами. Роли — opencode subagent'ы со свежим контекстом, общаются
только через файлы на диске.
</purpose>

<architecture>
```
            ┌─────────── Менеджер (primary, диспетчер) ───────────┐
            │  раздаёт задачи, крутит пары механически, роутит     │
            └──────────────┬───────────────┬───────────────┬──────┘
                           │               │               │
                    пара PLAN        пара CODE        пара TEST
                  planner⇄critic   coder⇄reviewer  tester⇄debugger
                  (doer ⇄ critic)  (doer ⇄ critic) (doer ⇄ critic)
```
- Внутри пары doer и critic антагонисты: doer делает, critic критикует, цикл до согласия.
- Каждая роль — отдельный subagent (чистый контекст). Нет общего диалога.
- Единственная общая память — файлы в `.planning/agent-pipeline/` (+ handoff'ы).
- opencode: вложенность subagent = 1, поэтому цикл пары крутит Менеджер (см. pair-protocol.md),
  но строго механически, не вмешиваясь в оценку качества.
</architecture>

<core_principle>
Менеджер — диспетчер, НЕ исполнитель и НЕ судья качества. Он решает только переходы МЕЖДУ
парами и механически гоняет цикл внутри пары по STATUS в handoff. Оценку даёт critic-роль
пары (critic / reviewer / debugger). Ни одна роль не переходит дальше без Менеджера.
</core_principle>

<references>
- `state-machine.md` — стадии, переходы между парами, схема pipeline-state.json
- `pair-protocol.md` — механика цикла doer↔critic внутри пары
- `handoff-protocol.md` — формат handoff и гигиена контекста (не терять / не переполнять)
Агенты: `.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md`
</references>

<pairs_contract>

### Пара PLAN — planner (doer) ⇄ critic (critic)
Вход: task-context.md. Цикл: planner строит plan-draft → critic ищет дыры (critique) →
planner правит → … до zero critical/major. Консенсус: approval-planner.md + approval-critic.md.
Выход Менеджеру: подписанный plan.md.

### Пара CODE — coder (doer) ⇄ reviewer (critic)
Вход: plan.md (волна) или bug-reports/. Цикл: coder реализует по TDD (code-summary) →
reviewer проверяет (lint, стиль, дубликаты, мёртвый код, SOLID, план, тесты) → coder правит →
… до чистого ревью. Консенсус: approval-reviewer.md. Выход: одобренный код волны.

### Пара TEST — tester (doer) ⇄ debugger (critic)
Вход: собранный итог + plan.md. Цикл: tester ломает приложение (test-report) → debugger
расследует каждый FAIL, подтверждает/опровергает (debug-report + bug-reports) → согласование
вердикта с tester → … до консенсуса. Выход Менеджеру: `clean` (нет багов) или `bugs-found`
(есть подтверждённые). Менеджер: clean → done; bugs-found → снова пара CODE.
</pairs_contract>

<context_discipline>
После КАЖДОГО шага, перед передачей:
1. Роль пишет полный handoff (статус + что сделано + артефакты + что делать следующему).
2. Роль возвращает Менеджеру только короткую квитанцию и завершается (её контекст исчезает).
3. Следующая роль поднимается с ЧИСТОГО контекста и восстанавливает всё из handoff+артефактов.
Так контекст не теряется (всё на диске) и не переполняется (никто не тащит чужой контекст).
Детали — handoff-protocol.md.
</context_discipline>

<stall_detection>
Менеджер отслеживает застревание:
- Роль вернула STATUS=blocked (неоднозначность/ошибка среды) → стадия blocked, отчёт пользователю.
- Пара не сошлась за `config.max_pair_iters` итераций → blocked.
- Повторный застой роли (nudge > max_nudges) → blocked.
</stall_detection>
