# Handoff: paired agent pipeline (dream-team)

A multi-agent development pipeline for **opencode**: three antagonistic role pairs under a
Manager-dispatcher. Verified by an end-to-end run to `done` (see "Validation" below).

## Architecture (v3 — orchestrator script)

```
        dt-run.sh — deterministic orchestrator (bash), NOT a model
          │  launches a role = a separate `opencode run --agent agent-<role>` (fresh context)
          │  reads `## STATUS` from the handoff → state-machine transition → next role
      PLAN pair            CODE pair (by waves)   TEST pair
   planner ⇄ critic     coder ⇄ reviewer       tester ⇄ debugger
```

- Inside a pair: the doer does, the critic criticizes, loop until consensus. The plan is closed by two
  signatures (critic `approved` → the planner signs and fixes `plan.md`); code — by waves
  `### Wave X.Y:`; test — the debugger's (second key) verdict `clean` / `bugs-found`.
- Why a script: the LLM manager (tested on `wirellm/main`) skipped the review/test pairs, did not keep
  state, did not check amendments between steps, wrote code itself, spawned itself. Transitions are mechanics,
  and now code does them: `transition()` in `dt-run.sh`, table — `state-machine.md`.
- Watchers during a role: amendment (`/dt-add`) → the role is interrupted → replan; `/dt-stop`;
  timeout; a "hung" process (handoff written, but `opencode run` does not exit).
- Hygiene: each role's session is exported to `sessions/` and deleted from opencode — otherwise
  the background service `opencode serve --service` resumes interrupted sessions (zombie roles write into
  the same `.planning/`). `run.lock` = pid; an orphan after `kill -9` is killed on start.
- `agent-manager` remains only as the slash-command entry: it relays the reply of `dt-cli.sh`.

## Roles

Each role is an opencode **subagent** with a fresh isolated context; communication only
through files on disk. The Manager spawns a role with the `subagent` tool, passes the path to the
input handoff; the role reads the handoff + artifacts, works, writes its handoff, returns
a short receipt `status=... handoff=...`.

| Pair | doer | critic (antagonist) | consensus |
|------|------|---------------------|-----------|
| plan | planner | critic | signed `plan.md` |
| code | coder | reviewer | approved code (by waves) |
| test | tester | debugger | verdict `clean` / `bugs-found` |

- plan: the critic finds ALL holes in the plan, does not fix — returns it to the planner. Both sign.
- code: coder — mandatory TDD (RED→GREEN), maximum coverage, atomic commits;
  reviewer — lint/codestyle, no duplicates, no dead code/unused variables/files,
  functionality grouped. The reviewer does not fix — returns to the coder.
- test: the tester designs its own E2E/edge/invalid/injection scenarios on the built result;
  the debugger investigates each FAIL, confirms/refutes it with deterministic reproduction
  steps. `bugs-found` → the Manager returns to the code pair; `clean` → `done`.

## Context hygiene

After each step a role writes a full `handoffs/step-NN-<role>.md` (STATUS, DONE, ARTIFACTS,
FOR NEXT AGENT, OPEN/RISKS, CONTEXT RESET) and returns only a short receipt to the Manager.
The next role starts from a clean context and restores everything from the handoff + artifacts.
Context is not lost (everything is on disk) and does not overflow. The Manager pulls into its context only
`pipeline-state.json` + the STATUS/FOR-NEXT sections, not whole artifacts.

The Manager updates `pipeline-state.json` AFTER EVERY step, BEFORE spawning the next role —
otherwise resume would restart the pipeline from the wrong place. state always = reality on disk.

## Files

```
.opencode/agents/            # executable roles (subagents)
  agent-manager.md           #   primary — dispatcher (permissions: subagent only for 6 roles)
  agent-{planner,critic,coder,reviewer,tester,debugger}.md
.opencode/skills/
  agent-pipeline/{SKILL,README,workflow,pair-protocol,handoff-protocol}.md
  agent-pipeline-run/SKILL.md          # entry point (commands for a human)
  agent-manager/{SKILL,state-machine}.md
  agent-<role>/{SKILL,*-guide}.md      # role craft references
```

Run state and artifacts — in `.planning/agent-pipeline/` (handoffs, bug-reports,
archive, pipeline-state.json, plan.md, task-context.md).

## Launch and resume

```bash
# TUI: /dt-new <task|@prompt.md> · /dt · /dt-add · /dt-issue · /dt-status · /dt-log · /dt-stop
alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'   # terminal, same syntax
dt --new @prompt.md      # foreground (Ctrl-C = stop); dt --bg … — background
dt                       # resume exactly from the saved step (state.env: NEXT_ROLE/IN_HANDOFF)
```

opencode v2.0.32 lessons built into the scripts:
- slash commands are loaded from `{command,commands}/**/*.md` (fields template/description/agent/
  model/subagent); `` !`cmd` `` in a template runs BEFORE the model (project cwd); in `opencode run`
  the slash is not expanded;
- `opencode run -- "msg"` puts the message into the session twice — `--` is not used;
- `opencode run` without `</dev/null` in a script waits for stdin; sometimes it does not exit after the reply —
  hence the "hang" watcher;
- a role with `mode: subagent` is launched directly via `--agent`;
- model glob tools do not see the hidden `.planning/` — roles get paths explicitly.

## Recursion protection (critical)

In v3 there is no recursion by construction: the script launches roles, the entry agent is forbidden everything except
relaying. History (v2, LLM manager): the Manager was FORBIDDEN to: run `opencode`/`opencode run` from shell; spawn itself;
call the `agent-pipeline-run` skill (it is the human entry point with command examples). Roles
were started ONLY with the `subagent` tool. Violation = runaway recursion (the daemon spawns
child processes, burns tokens). This happened in the past and was closed with PROHIBITIONS in
`agent-manager.md`.

## Validation (end-to-end run)

Task: Go package `emailvalidate` with `ValidateEmail(s string) bool` on an RFC 5322 regexp, unit
tests (happy/edge/invalid/injections), maximum coverage, strict TDD.

Result — the pipeline reached `stage=done`:
- Plan: planner⇄critic pair, ~8 iterations of real criticism → signed (3 phases / 6 waves).
- Code: coder⇄reviewer pair, atomic TDD commits RED→GREEN; the reviewer caught dead code
  (`DEAD-001`) and false ReDoS claims — antagonism worked.
- Test: tester — 3× PASS with `-race`, coverage 98.6%, fuzzing 30s/13.3M execs/0 panics,
  ReDoS/CRLF injections/Unicode/concurrency PASS, bench 42.4 µs/op.
- `go build` clean, `go test -race` green. No recursion.

Known gaps / to improve:
- **The debugger does not co-sign `clean`**: with zero FAILs the tester closes the test pair
  alone. The test pair's antagonism is not complete — the debugger should explicitly
  confirm/dispute the clean verdict (adversarial co-sign).
- Multi-wave (code pair by waves) worked, but a code review of its scaling would help.
- The manager's `permissions:` (frontmatter) was only partially validated live.

## Repository status

The pipeline was moved to a separate repository `neoff/dream-team` (this repo). It contains only
`.opencode/` + documentation — without the `.planning/` test artifacts and without the `emailvalidate` code
(that was a one-off validation run). To use it in a real project: copy `.opencode/`
into the project root (git repo) and run as described above.
