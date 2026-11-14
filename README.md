# dream-team

Многоагентный конвейер разработки для [opencode](https://opencode.ai): три **антагонистичные
пары** ролей под диспетчером-Менеджером, со строгой гигиеной контекста (всё состояние — на
диске, каждая роль поднимается с чистого контекста).

```
        Менеджер (primary — раздаёт задачи и роутит МЕЖДУ парами)
          │                    │                    │
      пара PLAN            пара CODE            пара TEST
   planner ⇄ critic     coder ⇄ reviewer    tester ⇄ debugger
```

- **planner ⇄ critic** → подписанный `plan.md`
- **coder ⇄ reviewer** → одобренный код (TDD, по волнам)
- **tester ⇄ debugger** → вердикт `clean` / `bugs-found`

Внутри пары doer и critic итерируют до консенсуса; только потом пара отдаёт Менеджеру
совместный результат. Менеджер качество не оценивает — крутит цикл механически и роутит.

## Установка

Одной командой (та же команда ставит и обновляет):

```bash
curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
```

Спросит **харнес** (opencode / claude / оба) и **область** (local — в текущий проект /
global — для всех). Копирует только свои агенты/скилы, чужие файлы в целевой папке не трогает.
При local-установке в git-проекте (или если есть `.gitignore`) заносит установленные пути в
`.gitignore` (идемпотентный блок `# >>> dream-team >>>`).

Неинтерактивно (в пайпе без tty) управляется переменными:

```bash
DREAM_TEAM_HARNESS=opencode DREAM_TEAM_SCOPE=global \
  bash -c 'curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash'
# HARNESS: opencode|claude|both (default opencode) · SCOPE: global|local (default local)
```

Целевые пути: opencode — `~/.config/opencode/{agents,skills,commands}` (global) или `.opencode/…` (local);
claude — `~/.claude/{agents,skills,commands}` (global) или `.claude/…` (local). claude не тестировался.

Вручную (альтернатива): скопировать `.opencode/` в корень своего проекта.

## Как это работает

Пайплайн ведёт **детерминированный скрипт-оркестратор** `dt-run.sh`, а не модель. Он запускает
каждую роль отдельным `opencode run --agent agent-<роль>` со свежим контекстом, даёт ей
входной handoff и точный путь выходного, читает `STATUS` и переходит по state-machine
(plan → code по волнам → test → done / новый цикл). Модели работают только в ролях.

Во время работы роли оркестратор следит за правками (`/dt-add` прерывает роль за секунды и
уводит в перепланирование), командой стоп, таймаутом и «зависшим» процессом. Сессию каждой
роли он экспортирует в `.planning/agent-pipeline/sessions/` и удаляет из opencode, чтобы
фоновый сервис opencode не «воскрешал» прерванные роли.

## Команды

| TUI (opencode) | Терминал | Что делает |
| --- | --- | --- |
| `/dt-new <задача>` | `dt --new <задача>` | новая задача (`--force` — поверх незаконченной; старое → архив) |
| `/dt-new @prompt.md` | `dt --new @prompt.md` | задача из файла — для больших промптов |
| `/dt` | `dt` | продолжить с места остановки |
| `/dt-add <правка>` | `dt --add <правка>` | правка: прервать текущую роль, перепланировать с учётом уже сделанного |
| `/dt-issue <текст>` | `dt --issue <текст>` | в беклог, без прерывания; после `done` — новый цикл |
| `/dt-status` | `dt --status` | стадия, пара, итерация, волна, текущая роль, журнал |
| `/dt-log` | `dt --log [N]` · `dt --log -f` | журнал оркестратора |
| `/dt-stop` | `dt --stop` | остановить (состояние сохраняется; продолжить — `/dt`) |

```bash
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'   # терминал
dt --new @prompt.md        # на переднем плане (Ctrl-C = стоп); dt --bg … — в фоне
```

Слэш-команды запускают оркестратор в фоне и сразу отвечают — TUI остаётся свободным, следить
`/dt-status`. Ограничение слэш-команд: обратная кавычка `` ` `` в тексте обрезает его (так
opencode разбирает `` !`…` ``) — текст с кодом передавай файлом (`@prompt.md`).

Настройка — переменные окружения: `DT_MAX_PAIR_ITERS` (5), `DT_MAX_TEST_ROUNDS` (3),
`DT_TIMEOUT_<РОЛЬ>` в минутах (PLANNER 40, CRITIC 25, CODER 90, REVIEWER 30, TESTER 60,
DEBUGGER 60), `DT_MODEL` (модель ролей), `DT_KEEP_SESSIONS=1` (не удалять сессии ролей),
`DT_ADD_INTERRUPT=step` (правка — только на границе шагов).

Артефакты прогона — в `.planning/agent-pipeline/` (`run.log`, `state.env`, handoffs, план,
отчёты, баг-репорты, архивы циклов). Каталог автоматически исключается из git
(`.git/info/exclude`).

## Документация

Полное описание архитектуры, протокола handoff, state-machine, защиты от рекурсии, уроков по
resume и результатов сквозной валидации — в [HANDOFF.md](HANDOFF.md).

## Структура

```
.opencode/agents/            исполняемые роли (opencode subagents)
  agent-manager.md           primary — вход слэш-команд (пересказывает ответ оркестратора)
  agent-{planner,critic,coder,reviewer,tester,debugger}.md
.opencode/commands/          слэш-команды /dt, /dt-{new,resume,issue,add,status,stop,log}
.opencode/skills/            протоколы + craft-reference ролей
  agent-manager/dt-*.sh      оркестратор и вход (dt-run.sh, dt-cli.sh, dt.sh, dt-lib.sh)
```
