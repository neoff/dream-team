# Agent Pipeline — парный агентский пайплайн для OpenCode

## Обзор

Разработка через три антагонистичные пары ролей, которыми диспетчеризует Менеджер.
Каждая роль — отдельный opencode **subagent** со свежим контекстом; роли общаются только
через файлы на диске (handoff + артефакты), поэтому контекст не теряется и не переполняется.

```
                 Менеджер (primary, диспетчер)
         раздаёт задачи, крутит пары, маршрутизирует
          │                  │                   │
      пара PLAN          пара CODE           пара TEST
   planner ⇄ critic   coder ⇄ reviewer   tester ⇄ debugger
    (doer ⇄ critic)    (doer ⇄ critic)    (doer ⇄ critic)
          │                  │                   │
     plan.md подписан   код одобрен        вердикт: clean / bugs-found
          └──────────────────┴───────────────────┘
                 всё возвращается Менеджеру,
       он решает переход к следующей паре (или done/coding)
```

Внутри пары doer и critic — антагонисты: doer делает, critic критикует, цикл до согласия.
Только после консенсуса пара отдаёт Менеджеру результат «готово, согласовано», и Менеджер
маршрутизирует дальше. Менеджер **внутрь пары не вмешивается** — он лишь механически гоняет
цикл по STATUS в handoff (ограничение opencode: вложенность subagent = 1 уровень, поэтому
цикл физически крутит primary, но как тупой диспетчер).

## Роли (opencode агенты)

| Роль         | Агент (`.opencode/agents/`) | Пара | Функция в паре | Ответственность                                      |
| ------------ | --------------------------- | ---- | -------------- | ---------------------------------------------------- |
| **Manager**  | `agent-manager` (primary)   | —    | диспетчер      | раздаёт задачи, крутит пары, роутит, финал/эскалация |
| **Planner**  | `agent-planner`             | plan | doer           | декомпозиция на фазы/волны/задачи, TDD-стратегия     |
| **Critic**   | `agent-critic`              | plan | critic         | безжалостный аудит плана, поиск всех проблем         |
| **Coder**    | `agent-coder`               | code | doer           | реализация по TDD, атомарные коммиты                 |
| **Reviewer** | `agent-reviewer`            | code | critic         | линт, стиль, дубликаты, мёртвый код, SOLID, план     |
| **Tester**   | `agent-tester`              | test | doer           | E2E, edge, негатив, security, нагрузка               |
| **Debugger** | `agent-debugger`            | test | critic         | root cause, подтверждение/опровержение, баг-репорты  |

Детальные правила ремесла каждой роли — в `.opencode/skills/agent-<role>/` (SKILL.md + guide),
агент их читает как reference.

## Ключевые принципы

1. **Антагонистичные пары** — doer делает, critic критикует, до согласия обоих.
2. **Менеджер — диспетчер, не судья** — качество оценивают critic/reviewer/debugger, не он.
3. **Свежий контекст у каждой роли** — роль = subagent, поднимается с нуля, читает только
   свой handoff + названные артефакты.
4. **Handoff после каждого шага** — перед передачей роль пишет полный статус+handoff; всё
   важное на диске, контекст не теряется и не переполняется.
5. **TDD строго** — Кодер пишет падающий тест ПЕРВЫМ.
6. **Critic/Reviewer/Debugger не правят** — только указывают; правит doer.
7. **Клятвы на крови** — Critic, Reviewer, Debugger подписывают результаты.
8. **Stall detection** — роль=blocked или пара не сошлась за `max_pair_iters` → blocked.

## Запуск

Менеджер — primary-агент (не skill):

```bash
cd <корень-проекта>   # каталог, где лежит .opencode/

# новый прогон
opencode run --agent agent-manager "Создать REST API для пользователей с JWT авторизацией"

# продолжить прерванный
opencode run --agent agent-manager "resume"
```

или интерактивно: запустить opencode, переключить агента на `agent-manager`, дать задачу.
Справка-обёртка: skill `/agent-pipeline-run`.

## Артефакты (в `.planning/agent-pipeline/`)

```
pipeline-state.json      # Состояние (единственный источник истины)
task-context.md          # Задача дословно + как понята
handoffs/
  step-00-manager.md     # Handoff каждого шага (статус, что сделано, что дальше)
  step-01-planner.md
  ...
plan-draft.md            # Черновик плана (пара plan)
plan.md                  # Итоговый план (после approval planner+critic)
critique.md              # Замечания Критика
approval-planner.md      # Подпись Планировщика
approval-critic.md       # Подпись Критика (клятва)
code-summary.md          # Отчёт Кодера
review-report.md         # Замечания Ревьювера
approval-reviewer.md     # Подпись Ревьювера
test-report.md           # Отчёт Тестировщика (FAIL-кейсы)
debug-report.md          # Расследование Дебаггера
clean-report.md          # Чистый отчёт (багов нет)
bug-reports/
  bug-001.md             # Подтверждённый баг с детерминированным repro
  ...
archive/                 # Куда Менеджер архивирует артефакты по завершении
```

## State machine (между парами)

```
init → planning → coding → testing → done
                    ▲          │
                    └──────────┘
                 bugs-found (снова пара code)

planning: пара plan крутится до approval-critic + approval-planner
coding:   пара code крутится до approval-reviewer (по волнам)
testing:  пара test крутится до согласованного вердикта (clean | bugs-found)
```

Цикл ВНУТРИ пары (doer→critic→doer…) — в `pair-protocol.md`, тут не показан.

## Документы протокола

- `workflow.md` — обзор архитектуры и контрактов пар
- `state-machine.md` — стадии, переходы между парами, схема pipeline-state.json (v2)
- `pair-protocol.md` — механика цикла doer↔critic и консенсуса
- `handoff-protocol.md` — формат handoff, гигиена контекста (не терять / не переполнять)

## Конфигурация (в pipeline-state.json)

```json
{
  "config": {
    "max_pair_iters": 5,
    "tdd_required": true,
    "coverage_threshold": 80,
    "timeouts_minutes": { "planner": 10, "critic": 5, "coder": 15, "reviewer": 5, "tester": 10, "debugger": 10 },
    "max_nudges": 2
  }
}
```

## Структура

```
.opencode/
├── agents/                      # Исполняемые роли (opencode subagents)
│   ├── agent-manager.md         #   primary — диспетчер
│   ├── agent-planner.md         #   subagent (пара plan, doer)
│   ├── agent-critic.md          #   subagent (пара plan, critic)
│   ├── agent-coder.md           #   subagent (пара code, doer)
│   ├── agent-reviewer.md        #   subagent (пара code, critic)
│   ├── agent-tester.md          #   subagent (пара test, doer)
│   └── agent-debugger.md        #   subagent (пара test, critic)
└── skills/
    ├── agent-pipeline/          # Протоколы и обзор
    │   ├── README.md
    │   ├── workflow.md
    │   ├── pair-protocol.md
    │   └── handoff-protocol.md
    ├── agent-pipeline-run/      # Точка входа (как запустить менеджера)
    │   └── SKILL.md
    ├── agent-manager/           # Справка + state-machine
    │   ├── SKILL.md
    │   └── state-machine.md
    ├── agent-planner/           # Craft-reference ролей
    │   ├── SKILL.md
    │   └── planning-guide.md
    ├── agent-critic/
    │   ├── SKILL.md
    │   └── critique-guide.md
    ├── agent-coder/
    │   ├── SKILL.md
    │   └── coding-guide.md
    ├── agent-reviewer/
    │   ├── SKILL.md
    │   └── review-guide.md
    ├── agent-tester/
    │   ├── SKILL.md
    │   └── testing-guide.md
    └── agent-debugger/
        ├── SKILL.md
        └── debugging-guide.md
```
