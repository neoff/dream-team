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

Целевые пути: opencode — `~/.config/opencode/{agents,skills}` (global) или `.opencode/…` (local);
claude — `~/.claude/{agents,skills}` (global) или `.claude/…` (local). claude не тестировался.

Вручную (альтернатива): скопировать `.opencode/` в корень своего проекта.

## Запуск

```bash
cd /path/to/your/project      # каталог с .opencode/

# новая задача
opencode run --agent agent-manager "Создать REST API для пользователей с JWT"

# продолжить прерванный прогон (сообщение 'resume', не флаг)
opencode run --standalone --agent agent-manager "resume"
```

Артефакты прогона — в `.planning/agent-pipeline/` (handoffs, state, план, баг-репорты).

## Документация

Полное описание архитектуры, протокола handoff, state-machine, защиты от рекурсии, уроков по
resume и результатов сквозной валидации — в [HANDOFF.md](HANDOFF.md).

## Структура

```
.opencode/agents/            исполняемые роли (opencode subagents)
  agent-manager.md           primary — диспетчер
  agent-{planner,critic,coder,reviewer,tester,debugger}.md
.opencode/skills/            протоколы + craft-reference ролей
```
