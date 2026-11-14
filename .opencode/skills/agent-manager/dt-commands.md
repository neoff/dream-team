<!-- dream-team: команды /dt и оркестратор dt-run.sh -->
<purpose>
Как устроен запуск пайплайна. Пайплайн ведёт НЕ модель, а детерминированный скрипт-оркестратор
`dt-run.sh`: он сам запускает роли, читает их STATUS, пишет состояние, обрабатывает правки и
беклог. Модели работают только внутри ролей (planner, critic, coder, reviewer, tester, debugger).
</purpose>

<files>
| Файл          | Что делает                                                                  |
| ------------- | --------------------------------------------------------------------------- |
| `dt-cli.sh`   | единый вход: терминал и слэш-команды (`--status`, `--log`, `--stop`, `--bg`) |
| `dt.sh`       | разбор сообщения → `ACTION=stop` (+MSG) или `ACTION=run`; intake, `new`       |
| `dt-run.sh`   | оркестратор: цикл ролей по state-machine, сторожа, гигиена сессий            |
| `dt-lib.sh`   | общее: state, lock, архивы, `new` / `replan` / `cycle` / `finalize`           |
</files>

<commands>
| Слэш-команда (TUI)        | Терминал (`alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'`) | Что делает |
| ------------------------- | ------------------------ | ---------- |
| `/dt`                     | `dt`                     | продолжить; пайплайна нет → нужна задача (`/dt <задача>`) |
| `/dt-new <задача>`        | `dt --new <задача>`      | новая задача; старое → архив. Незаконченную — только `--force` |
| `/dt-new @prompt.md`      | `dt --new @prompt.md`    | задача из файла (огромные промпты; бэктики/кавычки — без ограничений) |
| `/dt-resume`              | `dt --resume`            | продолжить с места остановки |
| `/dt-add <правка>`        | `dt --add <правка>`      | правка задачи: живой прогон прерывает текущую роль и перепланирует |
| `/dt-issue <дополнение>`  | `dt --issue <текст>`     | в беклог: после `done` — новый цикл (сделанное + дополнения) |
| `/dt-status`              | `dt --status`            | стадия, пара, итерация, волна, текущая роль, сколько идёт, журнал |
| `/dt-log`                 | `dt --log [N]`, `dt --log -f` | журнал оркестратора (`.planning/agent-pipeline/run.log`) |
| `/dt-stop`                | `dt --stop`              | остановить: роль прерывается, состояние сохраняется; продолжить — `/dt` |

Слэш-команды запускают оркестратор в фоне (`--bg`) и сразу возвращают ответ; TUI свободен.
Из терминала `dt …` без `--bg` ведёт прогон на переднем плане (Ctrl-C = `--stop`).
Текст `@путь` в `/dt-add`, `/dt-issue` тоже читается из файла.
Ограничение слэш-команд: обратная кавычка в тексте обрезает его (так opencode разбирает
`` !`…` ``) — для текста с кодом используй `@файл`.
</commands>

<orchestrator>
Цикл `dt-run.sh` (одна роль = один `opencode run --agent agent-<роль>` со свежим контекстом):

```
plan:  planner → critic ─needs-revision→ planner … ─approved→ planner[подпись] ─approved→ code
code:  по волнам (`### Wave X.Y:` в plan.md): coder → reviewer ─needs-revision→ coder …
       ─approved→ следующая волна | test
test:  tester → debugger ─needs-revision→ tester … ─bugs-found→ code[фикс] → reviewer → test
       ─clean→ беклог пуст ? done : новый цикл (plan)
любая роль ─blocked→ blocked · итераций пары > DT_MAX_PAIR_ITERS → blocked
раундов тестирования ≥ DT_MAX_TEST_ROUNDS → blocked
```

Роль получает в промпте путь входного handoff и ТОЧНЫЙ путь выходного; оркестратор читает
первое слово под `## STATUS`. Нет handoff / неверный STATUS → один повтор с замечанием
(`DT_MAX_NUDGES`), затем blocked. Состояние — `state.env` (канон), `pipeline-state.json`
(генерируется), `history.jsonl`, `run.log`.

Сторожа во время роли (опрос каждые `DT_POLL_SEC`, 3 с):
- `amendments/pending` не пуст → роль прерывается → переплан (`DT_ADD_INTERRUPT=step` —
  дождаться конца шага);
- `stop.request` (`/dt-stop`) или Ctrl-C → роль прерывается, шаг повторится при продолжении;
- таймаут роли (`DT_TIMEOUT_<РОЛЬ>`, мин) и «зависание» (handoff записан, процесс не выходит
  дольше `DT_HANG_GRACE_SEC`) → процесс завершается, результат берётся из handoff.

Гигиена:
- сессия каждой роли экспортируется в `sessions/step-NN-<роль>.session.json` и удаляется из
  opencode (`DT_KEEP_SESSIONS=1` — оставить). Иначе фоновый сервис opencode «воскрешает»
  прерванные сессии, и появляются зомби-роли;
- `run.lock` = pid оркестратора; второй не стартует. Роль-сирота после `kill -9` добивается
  при следующем старте;
- `.planning/` вносится в `.git/info/exclude`; отчёты, которые роль положила в корень,
  переносятся в `stray/`.
</orchestrator>

<transitions_on_input>
- **new**: старое состояние → `archive/task-<id>-<ts>/`, каркас, `task-context.md` (задача
  дословно), handoff planner'у, `state.env`.
- **add**: правка → `amendments/pending/add-<ts>.md`. Живой прогон подхватит за секунды;
  иначе запускается оркестратор, и он сразу перепланирует: правка → `amendments/applied/`,
  раздел «Правки» в `task-context.md`, артефакты прохода → `archive/replan-step-NN/`, код
  остаётся и учитывается в новом плане.
- **issue**: дополнение → `backlog/pending/issue-<ts>.md`. На `clean` оркестратор архивирует
  цикл в `archive/cycle-N/`, дописывает «Цикл N+1 — дополнения» в `task-context.md` и
  начинает новый цикл с planner'а.
- **resume**: при `done` и пустом беклоге / `blocked` без правок — отказ без запуска модели.
</transitions_on_input>
