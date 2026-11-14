# Рабочий хендоф — агентский пайплайн dream-team

Снимок состояния на 2026-11-04. Эта папка (`wirellm`) — дебаг-копия/источник; её можно
переносить. Ниже всё, чтобы продолжить с любого места.

## Что это

Многоагентный конвейер для **opencode**: 3 антагонистичные пары (planner⇄critic,
coder⇄reviewer, tester⇄debugger) под диспетчером-Менеджером. Полное описание архитектуры —
в `HANDOFF.md` рядом. Этот файл — про статус работы и как продолжить.

## Репозитории и состояние (на момент снимка)

| что | репо | ветка | HEAD | примечание |
|-----|------|-------|------|------------|
| источник (дебаг-копия) | `git@github.com:neoff/crypto-bits-ai.git` | `wirellm` | `4c5d7d8` | эта папка |
| дистрибутив | `git@github.com:neoff/dream-team.git` | `main` | `e77632b` | **public**, с install.sh |
| площадка валидации | `crypto-bits-ai` (локально `../wirellm-skiltest`) | `skill-test` | merge `da5ec91` | прогон emailvalidate до `done` |

- `crypto-bits-ai` ветка `main` — ПУСТАЯ по задумке, НЕ трогать.
- `dream-team` — чистый дистрибутив: `.opencode/` + `HANDOFF.md` + `README.md` + `install.sh` +
  `.gitignore`. Без `.planning/` и без тестового кода.

## Установка / обновление (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
```

Спрашивает харнес (opencode / claude / оба) и область (local / global). install == update
(повторный запуск перезаписывает наши файлы). Неинтерактивно:
`DREAM_TEAM_HARNESS=opencode|claude|both DREAM_TEAM_SCOPE=global|local`.
Пути: opencode `~/.config/opencode/{agents,skills}` | `.opencode/…`; claude
`~/.claude/{agents,skills}` | `.claude/…`.

## Запуск пайплайна

```bash
cd <проект с .opencode/>
opencode run --agent agent-manager "Твоя задача"
opencode run --standalone --agent agent-manager "resume"   # продолжить прерванный прогон
```

Уроки resume (важно): `--resume`-флага НЕТ; resume = сообщение `resume` (без дефисов).
Канон — `--standalone` (корень в cwd, видит `.planning/`); общий демон `:4096` может быть
укоренён в другой папке → «состояния нет». `-s <id>` — только для живого просмотра в TUI
(поднимает устаревший контекст, может дёрнуть step назад). Петлю resume-до-`done` крутит
обёртка СНАРУЖИ, не менеджер (ему запрещён shell-opencode — анти-рекурсия).

## Сделано

- Переархитектура в антагонистичные пары + диспетчер; роли — subagents со свежим контекстом,
  обмен через handoff-файлы на диске; per-step sync `pipeline-state.json`.
- Закрыта runaway-рекурсия (ЗАПРЕТЫ менеджеру на shell-opencode / самоспавн / skill-вход).
- Фикс стоп-шорта: менеджер не отчитывается юзеру до `done`/`blocked`.
- Фикс resume (сообщение `resume`, не флаг) + урок про `--standalone`.
- Фикс пути `state-machine.md` (лежит в `agent-manager/`).
- Сквозная валидация на `emailvalidate` → `done`: TDD RED→GREEN, coverage 98.6%, фаззинг
  13.3M execs, `-race`, ReDoS/CRLF — чисто. Рекурсии нет.
- Вынос в отдельный public-репо `dream-team` + `install.sh` (curl|bash, install==update),
  протестирован end-to-end (local/global, update-идемпотентность, .gitignore-блок).

## v3: оркестратор-скрипт вместо LLM-менеджера (2026-11-05)

- Пайплайн ведёт `skills/agent-manager/dt-run.sh` (bash, детерминированно): роль = отдельный
  `opencode run --standalone --agent agent-<роль>`, точные пути входного/выходного handoff,
  переход по `## STATUS` (`transition()`), state в `state.env` (JSON генерируется).
  `dt-lib.sh` — общее (state, lock по pid, архивы, new/replan/cycle/finalize), `dt.sh` — разбор
  входа, `dt-cli.sh` — вход (`--status/--log/--stop/--bg/--stdin`). `agent-manager` — только
  пересказ ответа для слэш-команд.
- Почему: LLM-менеджер на `wirellm/main` пропускал пары review/test, не вёл state, не делал
  replan между шагами, сам писал код, спавнил себя (`permissions` не держали).
- Сторожа: правка прерывает роль за секунды → переплан; stop; таймаут; «зависший» `opencode
  run`; сирота после kill -9. Гигиена: сессии ролей → export в `sessions/` + delete (иначе
  фоновый сервис воскрешает их — зомби); незакоммиченный мусор ролей → `stray/step-NN/`;
  `.planning/` → `.git/info/exclude`.
- Тесты: `bash tests/run.sh` — 10 сценариев на моке opencode (`tests/bin/opencode`), ~2 мин.
- Живая проверка (scratchpad, `wirellm/main`): Fib → `/dt-add Seq` во время кодера (прерван за
  1 с, переплан с волной Seq) → 4 волны → test (debugger `clean`) → беклог CLI → цикл 2 → done.
  51 шаг, 40 сессий, все удалены, процессов/lock не осталось, тесты зелёные.
- Уроки opencode v2.0.32: команды из `{command,commands}/**/*.md`; `` !`cmd` `` в шаблоне идёт
  ДО модели; `run -- "msg"` дублирует сообщение; без `</dev/null` `run` ждёт stdin; сервис
  `opencode serve --service` возобновляет прерванные сессии; роль с `mode: subagent`
  запускается через `--agent`; glob моделей не видит `.planning/`.

## Открыто / TODO

1. **claude-харнес** не адаптирован (отложено). С оркестратором стало проще: нужен лишь способ
   запускать роль в Claude Code (`claude -p --agent …`) вместо `opencode run` в `run_role`.
2. Слэш-команды в TUI проверены симуляцией раскрытия шаблона, не руками в TUI — прогнать
   `/dt-new`, `/dt-status`, `/dt-add` в живом TUI.
3. Роли всё ещё кладут `coverage.out` и временные файлы в корень (сторож убирает в `stray/`) —
   можно ужесточить подсказку в guide'ах tester/reviewer/coder.
4. Глобальная установка (`~/.config/opencode`) с оркестратором не прогонялась.

## Карта файлов

```
.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md
.opencode/skills/agent-pipeline/{SKILL,README,workflow,pair-protocol,handoff-protocol}.md
.opencode/skills/agent-pipeline-run/SKILL.md
.opencode/skills/agent-manager/{SKILL,state-machine,dt-commands}.md
.opencode/skills/agent-manager/dt-{run,cli,lib}.sh, dt.sh   # оркестратор и вход
.opencode/commands/dt*.md                                  # слэш-команды
tests/run.sh, tests/bin/opencode                           # мок-тесты оркестратора
.opencode/skills/agent-<role>/{SKILL,*-guide}.md
HANDOFF.md        # архитектура пайплайна (детально)
WORK-HANDOFF.md   # этот файл
```

## Как продолжить после переноса папки

1. Папка самодостаточна (`.opencode/` + оба handoff). Git-история — в репо `crypto-bits-ai`
   ветка `wirellm`; при желании можно переинициализировать или склонировать `dream-team`.
2. Правки вести в `.opencode/`, затем синк в `dream-team` (rsync `.opencode/` + docs) и push
   в `main` — дистрибутив обновится, `curl|bash` подтянет.
3. Следующий шаг по плану — пункт 1 из «Открыто»: нативная адаптация под Claude Code.
