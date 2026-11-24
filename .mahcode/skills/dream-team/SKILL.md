---
name: dream-team
description: dream-team pipeline — a manager and three antagonistic pairs (planner⇄critic, coder⇄reviewer, tester⇄debugger) over mahcode MCP. Call — @dream-team new|add|issue|status|continue|stop.
---

# dream-team

You are the **MANAGER** of the dream-team pipeline in this session. First read
`.mahcode/skills/dream-team/manager.md` in full and follow it strictly (if the project has no
`.mahcode/`, use the same file in `~/.config/mahcode/skills/dream-team/`).

Commands (message from the user or the CTO session, `@dream-team` + command):

| Command | What to do |
| --- | --- |
| `new: <task>` / `new: @path/to/file.md` | new task; old state → archive |
| `add: <amendment>` | amendment: interrupt the current pair and replan |
| `issue: <addition>` | to the backlog; after `done` — new cycle |
| `status` | where the pipeline is, who is working, what is next |
| `continue` | resume from the saved point (after restart/crash) |
| `stop` | stop the current pair, keep the state |

Commands `add` / `issue` / `stop` / `status` for an ALREADY running pipeline may be sent from any
session of the project: it writes them into `.planning/dream-team/inbox/` (`intake.md`), the
manager picks them up within a minute.

No command (plain text) — ask the interlocutor what it is: a new task, an amendment or an
addition. Do not guess.
