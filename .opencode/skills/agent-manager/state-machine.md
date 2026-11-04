<!-- agent-manager state machine (pair model) -->
<purpose>
Стадии, переходы и схема pipeline-state.json. Модель — ПАРНАЯ: Менеджер маршрутизирует
между тремя парами, а цикл внутри пары (doer↔critic) описан в pair-protocol.md.
</purpose>

<model>
Три антагонистичные пары, каждая крутится внутри себя до консенсуса:
- plan  = planner (doer) ↔ critic (critic)
- code  = coder (doer) ↔ reviewer (critic)
- test  = tester (doer) ↔ debugger (critic)

Менеджер НЕ входит внутрь пары содержательно: он механически гоняет цикл по pair-protocol
и переключает стадии МЕЖДУ парами по таблице ниже.
</model>

<stages>
- `init` — создан контекст/состояние
- `planning` — работает пара plan (до двойного approval)
- `coding` — работает пара code (до approval ревьювера), по волнам
- `testing` — работает пара test (до согласованного вердикта)
- `done` — вердикт `clean`, пайплайн завершён
- `blocked` — пара застряла (iter > max) или роль вернула blocked → нужен пользователь
</stages>

<pair_transitions>
Переключения МЕЖДУ парами (это вся маршрутизация Менеджера):

| Стадия   | Событие от пары (joint-handoff STATUS)        | Новая стадия | Что раздаёт Менеджер                         |
| -------- | --------------------------------------------- | ------------ | -------------------------------------------- |
| init     | —                                             | planning     | task-context.md → паре plan                  |
| planning | консенсус plan (approval-critic+planner)      | coding       | plan.md → паре code (первая волна)           |
| coding   | консенсус code (approval-reviewer) и волны ещё | coding       | следующая волна → паре code                  |
| coding   | консенсус code и все волны готовы             | testing      | собранный итог + plan.md → паре test         |
| testing  | `clean`                                       | done         | финализация, архив                           |
| testing  | `bugs-found`                                  | coding       | bug-reports/ → паре code (фикс)              |
| любая    | роль вернула `blocked` ИЛИ iter > max_pair_iters | blocked   | стоп, отчёт пользователю                     |

Цикл ВНУТРИ пары (doer→critic→doer…) здесь не отражён — это pair-protocol.md.
</pair_transitions>

<state_schema>

```json
{
  "version": "2.0",
  "task_id": "uuid_or_hash",
  "task_description": "string",
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "stage": "init|planning|coding|testing|done|blocked",
  "step": 0,
  "current_pair": "plan|code|test|null",
  "pair_iteration": 0,
  "current_phase": 1,
  "current_wave": 1,
  "total_phases": 1,
  "active_role": "manager|planner|critic|coder|reviewer|tester|debugger",
  "last_handoff": ".planning/agent-pipeline/handoffs/step-00-manager.md",
  "roles": {
    "planner":  {"status": "pending", "nudge_count": 0, "last_handoff": null},
    "critic":   {"status": "pending", "nudge_count": 0, "last_handoff": null},
    "coder":    {"status": "pending", "nudge_count": 0, "last_handoff": null},
    "reviewer": {"status": "pending", "nudge_count": 0, "last_handoff": null},
    "tester":   {"status": "pending", "nudge_count": 0, "last_handoff": null},
    "debugger": {"status": "pending", "nudge_count": 0, "last_handoff": null}
  },
  "artifacts": {
    "task_context": ".planning/agent-pipeline/task-context.md",
    "plan": ".planning/agent-pipeline/plan.md",
    "plan_draft": ".planning/agent-pipeline/plan-draft.md",
    "critique": ".planning/agent-pipeline/critique.md",
    "approval_planner": ".planning/agent-pipeline/approval-planner.md",
    "approval_critic": ".planning/agent-pipeline/approval-critic.md",
    "code_summary": ".planning/agent-pipeline/code-summary.md",
    "review_report": ".planning/agent-pipeline/review-report.md",
    "approval_reviewer": ".planning/agent-pipeline/approval-reviewer.md",
    "test_report": ".planning/agent-pipeline/test-report.md",
    "debug_report": ".planning/agent-pipeline/debug-report.md",
    "clean_report": ".planning/agent-pipeline/clean-report.md",
    "bug_reports_dir": ".planning/agent-pipeline/bug-reports/",
    "handoffs_dir": ".planning/agent-pipeline/handoffs/"
  },
  "history": [
    {"step": 0, "stage": "init", "role": "manager", "action": "created", "timestamp": "ISO8601"}
  ],
  "config": {
    "max_pair_iters": 5,
    "tdd_required": true,
    "coverage_threshold": 80,
    "timeouts_minutes": {"planner": 10, "critic": 5, "coder": 15, "reviewer": 5, "tester": 10, "debugger": 10},
    "max_nudges": 2
  }
}
```

</state_schema>

<pair_consensus_signals>
Как Менеджер понимает, что пара достигла консенсуса (детали в pair-protocol.md):
- plan: существуют `approval-critic.md` И `approval-planner.md`.
- code: существует `approval-reviewer.md` для текущей волны.
- test: последний handoff пары имеет STATUS `clean` или `bugs-found` (tester и debugger
  согласны с вердиктом). `clean` → done; `bugs-found` → снова пара code.
</pair_consensus_signals>

<context_hygiene>
Менеджер держит в контексте только: `pipeline-state.json` + STATUS/FOR-NEXT входных handoff.
Полные артефакты не читает — передаёт пути. Роли — свежий контекст, общение через файлы.
См. handoff-protocol.md.
</context_hygiene>
