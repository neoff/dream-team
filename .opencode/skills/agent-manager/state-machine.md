<!-- dream-team state machine (исполняет dt-run.sh) -->
<purpose>
Стадии, переходы и формат состояния. Исполнитель — скрипт-оркестратор `dt-run.sh` (не модель):
переходы ниже реализованы в его функции `transition`. Цикл внутри пары — pair-protocol.md.
</purpose>

<model>
Три антагонистичные пары, каждая крутится до консенсуса:
- plan = planner (doer) ↔ critic (critic); консенсус: critic `approved` + planner подписал
  (`approval-planner.md`, `plan.md`)
- code = coder (doer) ↔ reviewer (critic); по волнам `### Wave X.Y:` из plan.md
- test = tester (doer) ↔ debugger (critic, второй ключ); вердикт debugger'а: `clean` / `bugs-found`
</model>

<stages>
- `planning` — пара plan
- `coding` — пара code (волна `WAVE` из `TOTAL_WAVES`, либо фикс багов `BUGFIX=1`)
- `testing` — пара test (раунд `TEST_ROUND`)
- `done` — `clean` и беклог пуст
- `blocked` — роль вернула `blocked`, пара не сошлась, баги не ушли, роль не дала handoff
</stages>

<transitions>
| Роль [режим]      | STATUS          | Дальше                                                        |
| ----------------- | --------------- | ------------------------------------------------------------- |
| planner [work]    | done            | critic                                                        |
| critic            | needs-revision  | planner [work], итер+1                                        |
| critic            | approved        | planner [sign]                                                |
| planner [sign]    | approved        | coding: волна 1 (plan.md, подсчёт волн)                       |
| planner [sign]    | needs-revision  | critic, итер+1                                                |
| coder [work/bugfix] | done          | reviewer                                                      |
| reviewer          | needs-revision  | coder, итер+1                                                 |
| reviewer          | approved        | фикс → testing; иначе следующая волна или testing             |
| tester            | done            | debugger                                                      |
| debugger          | needs-revision  | tester, итер+1                                                |
| debugger          | bugs-found      | coding [bugfix] (раунд+1; ≥ max → blocked)                    |
| debugger          | clean           | беклог? новый цикл (planning) : done (архив cycle-N)          |
| любая             | blocked         | blocked                                                       |
| любая (вход)      | правка в amendments/pending | прервать роль → planning (переплан)               |

Лимиты: `DT_MAX_PAIR_ITERS` (5) итераций пары, `DT_MAX_TEST_ROUNDS` (3) раундов теста,
`DT_MAX_NUDGES` (1) повтор роли без корректного handoff.
</transitions>

<state>
`.planning/agent-pipeline/state.env` — канон (пишет только скрипт):

```
TASK_ID CREATED STAGE STEP CYCLE PAIR ITER WAVE TOTAL_WAVES WAVE_ID BUGFIX TEST_ROUND
NEXT_ROLE NEXT_MODE IN_HANDOFF LAST_HANDOFF LAST_STATUS BLOCK_REASON
```

`NEXT_ROLE` + `NEXT_MODE` + `IN_HANDOFF` — что запускать следующим; продолжение после
остановки = ровно этот шаг. `pipeline-state.json` (version 3.0) генерируется из state.env
вместе с `history` (из `history.jsonl`) — только для чтения людьми и ролями.

Остальное в `.planning/agent-pipeline/`: `handoffs/step-NN-<роль>.md`, `task-context.md`,
`plan-draft.md`, `plan.md`, `critique.md`, `approval-*.md`, `code-summary.md`,
`review-report.md`, `test-report.md`, `debug-report.md`, `clean-report.md`, `bug-reports/`,
`amendments/{pending,applied}/`, `backlog/{pending,taken}/`, `archive/`, `sessions/`,
`run.log`, `run.lock`.
</state>
