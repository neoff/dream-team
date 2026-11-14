# Handoff: парный агентский пайплайн (dream-team)

Многоагентный конвейер разработки для **opencode**: три антагонистичные пары ролей под
диспетчером-Менеджером. Проверен сквозным прогоном до `done` (см. «Валидация» ниже).

## Архитектура (v3 — оркестратор-скрипт)

```
        dt-run.sh — детерминированный оркестратор (bash), НЕ модель
          │  запускает роль = отдельный `opencode run --agent agent-<роль>` (свежий контекст)
          │  читает `## STATUS` из handoff → переход по state-machine → следующая роль
      пара PLAN            пара CODE (по волнам)   пара TEST
   planner ⇄ critic     coder ⇄ reviewer       tester ⇄ debugger
```

- Внутри пары: doer делает, critic критикует, цикл до консенсуса. План закрывается двумя
  подписями (critic `approved` → planner подписывает и фиксирует `plan.md`); код — по волнам
  `### Wave X.Y:`; тест — вердикт debugger'а (второй ключ) `clean` / `bugs-found`.
- Почему скрипт: LLM-менеджер (проверено на `wirellm/main`) пропускал пары ревью/теста, не вёл
  state, не проверял правки между шагами, сам писал код, спавнил сам себя. Переходы — механика,
  и теперь их делает код: `transition()` в `dt-run.sh`, таблица — `state-machine.md`.
- Сторожа во время роли: правка (`/dt-add`) → роль прерывается → переплан; `/dt-stop`;
  таймаут; «зависший» процесс (handoff записан, а `opencode run` не выходит).
- Гигиена: сессия каждой роли экспортируется в `sessions/` и удаляется из opencode — иначе
  фоновый сервис `opencode serve --service` возобновляет прерванные сессии (зомби-роли пишут в
  тот же `.planning/`). `run.lock` = pid; сирота после `kill -9` добивается при старте.
- `agent-manager` остался только как вход слэш-команд: пересказывает ответ `dt-cli.sh`.

## Роли

Каждая роль — opencode **subagent** со свежим изолированным контекстом; общение только
через файлы на диске. Менеджер спавнит роль инструментом `subagent`, передаёт путь к
входному handoff; роль читает handoff + артефакты, работает, пишет свой handoff, возвращает
короткую квитанцию `status=... handoff=...`.

| Пара | doer | critic (антагонист) | консенсус |
|------|------|---------------------|-----------|
| plan | planner | critic | подписанный `plan.md` |
| code | coder | reviewer | одобренный код (по волнам) |
| test | tester | debugger | вердикт `clean` / `bugs-found` |

- plan: critic ищет ВСЕ дыры плана, не чинит — возвращает planner. Оба подписывают.
- code: coder — обязательный TDD (RED→GREEN), максимальное покрытие, атомарные коммиты;
  reviewer — lint/codestyle, без дублей, без мёртвого кода/неиспользуемых переменных/файлов,
  функциональность сгруппирована. Reviewer не чинит — возвращает coder.
- test: tester разрабатывает свои E2E/edge/invalid/инъекции сценарии на собранном итоге;
  debugger расследует каждый FAIL, подтверждает/опровергает с детерминированными шагами
  воспроизведения. `bugs-found` → Менеджер возвращает в пару code; `clean` → `done`.

## Гигиена контекста

После каждого шага роль пишет полный `handoffs/step-NN-<role>.md` (STATUS, DONE, ARTIFACTS,
FOR NEXT AGENT, OPEN/RISKS, CONTEXT RESET) и возвращает Менеджеру только короткую квитанцию.
Следующая роль поднимается с чистого контекста и восстанавливает всё из handoff + артефактов.
Контекст не теряется (всё на диске) и не переполняется. Менеджер тянет в свой контекст только
`pipeline-state.json` + разделы STATUS/FOR-NEXT, не артефакты целиком.

Менеджер обновляет `pipeline-state.json` ПОСЛЕ КАЖДОГО шага, ДО спавна следующей роли —
иначе resume поднимет пайплайн не с того места. state всегда = реальность на диске.

## Файлы

```
.opencode/agents/            # исполняемые роли (subagents)
  agent-manager.md           #   primary — диспетчер (permissions: subagent только 6 ролей)
  agent-{planner,critic,coder,reviewer,tester,debugger}.md
.opencode/skills/
  agent-pipeline/{SKILL,README,workflow,pair-protocol,handoff-protocol}.md
  agent-pipeline-run/SKILL.md          # точка входа (команды для человека)
  agent-manager/{SKILL,state-machine}.md
  agent-<role>/{SKILL,*-guide}.md      # craft-reference ролей
```

Состояние и артефакты прогона — в `.planning/agent-pipeline/` (handoffs, bug-reports,
archive, pipeline-state.json, plan.md, task-context.md).

## Запуск и продолжение

```bash
# TUI: /dt-new <задача|@prompt.md> · /dt · /dt-add · /dt-issue · /dt-status · /dt-log · /dt-stop
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'   # терминал, тот же синтаксис
dt --new @prompt.md      # передний план (Ctrl-C = стоп); dt --bg … — в фоне
dt                       # продолжить ровно с сохранённого шага (state.env: NEXT_ROLE/IN_HANDOFF)
```

Уроки opencode v2.0.32, учтённые в скриптах:
- слэш-команды грузятся из `{command,commands}/**/*.md` (поля template/description/agent/
  model/subagent); `` !`cmd` `` в шаблоне выполняется ДО модели (cwd проекта); в `opencode run`
  слэш не раскрывается;
- `opencode run -- "msg"` кладёт сообщение в сессию дважды — `--` не используется;
- `opencode run` без `</dev/null` в скрипте ждёт stdin; иногда не выходит после ответа —
  отсюда сторож «зависания»;
- роль с `mode: subagent` запускается напрямую через `--agent`;
- glob-инструменты моделей не видят скрытый `.planning/` — роли получают пути явно.

## Защита от рекурсии (критично)

В v3 рекурсии нет по построению: роли запускает скрипт, агенту-входу запрещено всё, кроме
пересказа. История (v2, LLM-менеджер): Менеджеру было ЗАПРЕЩЕНО: запускать `opencode`/`opencode run` из shell; спавнить самого себя;
вызывать skill `agent-pipeline-run` (это точка входа для человека с примерами команд). Роли
поднимаются ТОЛЬКО инструментом `subagent`. Нарушение = runaway-рекурсия (демон плодит
дочерние процессы, жжёт токены). В прошлом это уже случалось и было закрыто ЗАПРЕТАМИ в
`agent-manager.md`.

## Валидация (сквозной прогон)

Задача: Go-пакет `emailvalidate` с `ValidateEmail(s string) bool` на RFC 5322 regexp, юнит-
тесты (happy/edge/invalid/инъекции), максимальное покрытие, строгий TDD.

Результат — пайплайн дошёл до `stage=done`:
- План: пара planner⇄critic, ~8 итераций реальной критики → подписан (3 фазы / 6 волн).
- Код: пара coder⇄reviewer, атомарные TDD-коммиты RED→GREEN; reviewer ловил мёртвый код
  (`DEAD-001`) и ложные claim про ReDoS — антагонизм работал.
- Тест: tester — 3× PASS с `-race`, coverage 98.6%, фаззинг 30s/13.3M execs/0 паник,
  ReDoS/CRLF-инъекции/Unicode/concurrency PASS, бенч 42.4 µs/op.
- `go build` clean, `go test -race` зелёный. Рекурсии не было.

Известные пробелы / доработать:
- **Debugger не переподписывает `clean`**: при нуле FAIL tester закрывает пару test в
  одиночку. Антагонизм пары test до конца не доведён — стоит заставить debugger явно
  подтверждать/оспаривать clean-вердикт (adversarial co-sign).
- Многоволновость (code-пара по волнам) отработала, но код-ревью её масштабирования полезен.
- `permissions:` у менеджера (frontmatter) валидирован живьём лишь частично.

## Статус репозитория

Пайплайн вынесен в отдельный репозиторий `neoff/dream-team` (этот репо). Содержит только
`.opencode/` + документацию — без тестовых артефактов `.planning/` и без кода `emailvalidate`
(это был разовый прогон-валидация). Для применения в реальном проекте: скопировать `.opencode/`
в корень проекта (git-репо) и запускать, как описано выше.
