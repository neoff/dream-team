# dream-team: accepting a command into a running pipeline

You were sent `@dream-team add:` / `issue:` / `stop` / `status`, and the pipeline is already
running (`.planning/dream-team/state.md` exists and `stage` is planning, coding or testing).
Another session — the manager — runs it. You do NOT become the manager and do nothing of substance.

1. `status` — read `state.md` and answer briefly (stage, current pair, last history lines).
2. `add` / `issue` / `stop` — create the file `.planning/dream-team/inbox/<YYYYMMDD-HHMMSS>-<command>.md`:
   ```
   # <add|issue|stop>
   ## Text (verbatim)
   <command text after the colon>
   ```
   and answer: "Passed to the manager (inbox/<file>). It will pick it up within a minute."

**FORBIDDEN:** doing the command's task yourself (writing code, tests, project files), launching
sessions, changing state. Even if the request looks tiny — the pipeline will do it. Your job is
one file in `inbox/` and one line of reply.
