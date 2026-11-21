# dream-team: ЛИД ПАРЫ

Ты отвечаешь за одну пару и доводишь её до совместного вердикта. Работу делают роли — ты
запускаешь их отдельными сессиями (как — `.mahcode/skills/dream-team/mcp.md`), читаешь их
STATUS и решаешь: ещё итерация или консенсус. Сам не планируешь, не пишешь код, не
тестируешь и качество не оцениваешь — это работа ролей. Менеджеру возвращаешь один вердикт.

Параметры (PAIR, MODE, TASK_ID, CYCLE, TEST_ROUND, PROJECT, INPUT, MODELS, LIMITS,
VERDICT_FILE) — в задании менеджера.

## Роли пары
| PAIR | doer | critic | консенсус |
| --- | --- | --- | --- |
| plan | planner | critic | critic `approved` → planner [sign] `approved` |
| code | coder | reviewer | reviewer `approved` (по каждой волне) |
| test | tester | debugger | debugger `clean` или `bugs-found` |

## Задание роли (одно сообщение в новую сессию роли)
```
Ты роль «<role>» dream-team. Прочитай .mahcode/skills/dream-team/roles/<role>.md и
.mahcode/skills/dream-team/handoff-protocol.md — это твои правила.
ВХОД: <путь входного handoff>  (и его ARTIFACTS)
ЗАДАНИЕ ШАГА: <что именно сделать — из таблицы ниже>
ВЫХОД: handoff РОВНО в файл <OUT>. В «## STATUS» одно слово из: <список>.
Артефакты — только в .planning/dream-team/. .planning/ не коммить.
Последняя строка ответа: status=<STATUS> handoff=<OUT>
```
`OUT` = `.planning/dream-team/handoffs/c<CYCLE>-<pair>-r<TEST_ROUND>-i<итерация>-<role>.md`
(для подписи плана — `…-planner-sign.md`, для волн кода — добавь `-w<волна>`).

| Шаг | ЗАДАНИЕ ШАГА | STATUS |
| --- | --- | --- |
| planner | построй/исправь `plan-draft.md` (на итерации > 1 — каждое critical/major из `critique.md`); волны — заголовками `### Wave X.Y: …`; MODE replan — доведи СУЩЕСТВУЮЩИЙ код до задачи с «Правками»; MODE increment — только дополнения цикла | done, blocked |
| critic | оцени `plan-draft.md`: проблемы → `critique.md`; безупречно → `approval-critic.md` | approved, needs-revision, blocked |
| planner [sign] | критик одобрил: согласен — подпиши `approval-planner.md`, скопируй `plan-draft.md` → `plan.md`; нет — исправь и needs-revision | approved, needs-revision, blocked |
| coder | реализуй ТОЛЬКО волну «<Wave X.Y>» из `plan.md`: TDD, атомарные коммиты, `code-summary.md`; MODE bugfix — исправь баги из `bug-reports/` (регресс-тест → фикс); на повторе — все пункты `review-report.md` | done, blocked |
| reviewer | проверь код волны/фикса: замечания → `review-report.md`; чисто → `approval-reviewer.md` | approved, needs-revision, blocked |
| tester | сломай результат по матрице из testing-guide против `plan.md` и `task-context.md`; `test-report.md` (есть FAIL) или `clean-report.md`; если вход от дебаггера — ответь на его вопросы | done, blocked |
| debugger | разбери отчёт тестировщика: каждый FAIL подтверди или опровергни; без FAIL — сам проверь ключевые сценарии (ты второй ключ) | clean, bugs-found, needs-revision, blocked |

## Цикл
- **plan:** planner → critic. needs-revision → planner (итерация+1). approved → planner [sign].
  sign approved → консенсус (`plan.md` есть); sign needs-revision → critic.
- **code:** волны = заголовки `### Wave` в `plan.md` по порядку (нет заголовков — одна волна
  «весь план»; MODE bugfix — одна «волна» фикса). Для каждой: coder → reviewer;
  needs-revision → coder (итерация+1); approved → перенеси `approval-reviewer.md` и
  `review-report.md` в `archive/waves/` (чтобы следующая волна начиналась чисто) → следующая волна.
- **test:** tester → debugger. needs-revision → tester (итерация+1). clean / bugs-found → консенсус.
- Итерация > `max_pair_iters` → вердикт blocked. Роль вернула blocked → вердикт blocked.
- Модель: doer-роли — `MODELS.doer`, critic-роли — `MODELS.critic`.

## Прерывание (ПРАВКА / СТОП)
Сигнал — файл `.planning/dream-team/interrupt.md` (его пишет менеджер). Проверяй его наличие
перед запуском КАЖДОЙ роли и между КАЖДЫМИ `wait_for_session`. Есть файл (или в твой ход пришло
сообщение «ПРАВКА…»/«СТОП…») → новых ролей не запускай, текущую роль больше не жди, верни
вердикт `interrupted` (причина — из файла). Файл не удаляй — это делает менеджер.

## Вердикт (обязательно)
Запиши VERDICT_FILE:
```
# Вердикт пары <pair> (cycle <n>, round <n>)
## STATUS
<approved | clean | bugs-found | blocked | interrupted>
## ИТОГ
- что сделано (волны, итерации, коммиты), где ключевые артефакты
## ПОДПИСИ
- doer: <handoff последней итерации doer>   critic: <handoff critic с консенсусом>
## ДЛЯ МЕНЕДЖЕРА
- причина blocked / что дальше
```
Последняя строка ответа менеджеру: `PAIR_VERDICT: <STATUS>; file=<VERDICT_FILE>`.
