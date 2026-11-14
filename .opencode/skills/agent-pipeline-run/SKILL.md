---
name: agent-pipeline-run
description: 'Точка входа агентского пайплайна dream-team: команды /dt… и dt-cli.sh. Пайплайн ведёт скрипт-оркестратор dt-run.sh, роли — отдельные opencode-агенты.'
---

<arguments>$ARGUMENTS</arguments>

<objective>
Запустить или продолжить пайплайн. Это делает человек командой (агенту здесь делать нечего):
оркестратор `agent-manager/dt-run.sh` сам ведёт пары planner⇄critic, coder⇄reviewer,
tester⇄debugger до done/blocked.
</objective>

<how_to_start>
⚠️ Команды ниже — для ЧЕЛОВЕКА. Агент, читающий это, ничего из них не запускает.

```bash
# TUI opencode
/dt-new <задача>         # или /dt-new @prompt.md — задача из файла
/dt                      # продолжить
/dt-add <правка>         # правка: прервать текущую роль и перепланировать
/dt-issue <дополнение>   # в беклог: новый цикл после done
/dt-status · /dt-log · /dt-stop

# терминал
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'
dt --new @prompt.md      # на переднем плане; dt --bg --new … — в фоне
dt --status · dt --log -f · dt --stop
```
</how_to_start>

<references>
- `.opencode/skills/agent-manager/dt-commands.md` — команды, оркестратор, сторожа, гигиена
- `.opencode/skills/agent-manager/state-machine.md` — стадии, переходы, формат состояния
- `.opencode/skills/agent-pipeline/pair-protocol.md` — цикл doer↔critic
- `.opencode/skills/agent-pipeline/handoff-protocol.md` — handoff и гигиена контекста
</references>
