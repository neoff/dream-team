<!-- agent-pipeline pair protocol: antagonistic doer<->critic loop -->
<purpose>
Механика работы антагонистичной пары. Менеджер исполняет этот цикл МЕХАНИЧЕСКИ:
чередует doer и critic (каждый — свежий subagent), пока critic не согласится.
Менеджер НЕ оценивает план/код/тесты сам — оценка это работа critic-роли.
</purpose>

<why_manager_drives>
opencode даёт вложенность subagent = 1 уровень: subagent не может спавнить другого
subagent. Поэтому цикл внутри пары не может крутить отдельный «агент-пары» — его крутит
единственный primary (Менеджер). Но Менеджер остаётся «тупым диспетчером»: он смотрит
только на STATUS в handoff и решает «ещё итерация или консенсус». Содержательных решений
о качестве он не принимает — это делают critic-роли (critic / reviewer / debugger).
</why_manager_drives>

<pairs>
| Пара   | Doer (делает)      | Critic (оценивает)   | Выход doer       | Сигнал консенсуса                         |
| ------ | ------------------ | -------------------- | ---------------- | ----------------------------------------- |
| plan   | agent-planner      | agent-critic         | plan-draft.md    | approval-critic.md + approval-planner.md  |
| code   | agent-coder        | agent-reviewer       | code-summary.md  | approval-reviewer.md                      |
| test   | agent-tester       | agent-debugger       | test-report.md   | debugger вынес вердикт, tester согласен   |
</pairs>

<loop>
Для пары P Менеджер делает:

1. **Спавн DOER** (subagent, свежий контекст) с prompt = путь к входному handoff.
   - Doer читает handoff + его ARTIFACTS + свой guide.
   - Doer делает свою итерацию, пишет выходной артефакт + handoff (STATUS=done → critic).
   - Возвращает квитанцию `status=done handoff=...`.

2. **Спавн CRITIC** (subagent, свежий контекст) с prompt = путь к handoff от doer.
   - Critic читает выход doer, безжалостно ищет проблемы.
   - Если проблемы есть → пишет отчёт (critique.md / review-report.md / debug-report.md)
     + handoff (STATUS=needs-revision → doer). Возвращает квитанцию.
   - Если проблем нет → пишет approval + handoff (STATUS=approved). Возвращает квитанцию.

3. **Менеджер смотрит STATUS последнего handoff:**
   - `needs-revision` → инкремент iter, вернуться к шагу 1 (DOER читает отчёт critic'а и правит).
   - сигнал консенсуса достигнут → пара закончила, Менеджер пишет joint-handoff пары
     и роутит по state-machine к следующей паре.
   - `iter > config.max_pair_iters` без консенсуса → STATUS=blocked, эскалация пользователю.

Антагонизм (обязательно):
- Doer НИКОГДА не подписывает approval за себя. Consensus = approval от critic.
- Critic ничего не правит сам — только указывает. Правит doer.
- Чем больше реальных проблем нашёл critic — тем лучше (его за это хвалят).
- Обе подписи (doer + critic) кладутся в joint-handoff: оба подтверждают, что согласны.
</loop>

<test_pair_special>
Пара test отличается выходом (её консенсус — не «approved», а согласованный ВЕРДИКТ):

1. tester (doer) гоняет E2E/edge/нагрузку, пишет test-report.md (найденные FAIL).
2. debugger (critic) расследует каждый FAIL: подтверждает баг (root cause + repro) ИЛИ
   опровергает (почему это не баг, ссылка на план).
3. Если tester оспаривает классификацию debugger'а → ещё итерация (pair debugging),
   пока оба не согласятся с итоговым вердиктом.
4. Консенсус пары = tester и debugger согласны с содержимым отчёта. Тогда joint-handoff
   Менеджеру с одним из двух STATUS:
   - `clean` — подтверждённых багов нет (все FAIL опровергнуты/flaky/env) → всё работает.
   - `bugs-found` — есть подтверждённые баги (bug-reports/*.md готовы).

Менеджер по state-machine: `clean` → done; `bugs-found` → снова пара code (фикс по bug-reports).
Это и есть «tester+debugger возвращаются к менеджеру с совместным отчётом, менеджер
маршрутизирует между парами».
</test_pair_special>

<manager_context_discipline>
На каждой итерации Менеджер:
- в свой контекст берёт только STATUS + FOR NEXT AGENT входного handoff и `pipeline-state.json`;
- НЕ читает plan-draft/дифы/отчёты целиком — передаёт путь следующей роли;
- обновляет state (step++, iter, active_role, last_handoff) и сохраняет;
- ответы ролей — короткие квитанции, не раздувают контекст.
</manager_context_discipline>
