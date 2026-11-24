<!-- dream-team state machine (executed by dt-run.sh) -->
<purpose>
Stages, transitions and the state format. The executor is the orchestrator script `dt-run.sh` (not a model):
the transitions below are implemented in its `transition` function. The loop inside a pair — pair-protocol.md.
</purpose>

<model>
Three antagonistic pairs, each loops until consensus:
- plan = planner (doer) ↔ critic (critic); consensus: critic `approved` + planner signed
  (`approval-planner.md`, `plan.md`)
- code = coder (doer) ↔ reviewer (critic); by waves `### Wave X.Y:` from plan.md
- test = tester (doer) ↔ debugger (critic, second key); the debugger's verdict: `clean` / `bugs-found`
</model>

<stages>
- `planning` — plan pair
- `coding` — code pair (wave `WAVE` of `TOTAL_WAVES`, or bug fixing `BUGFIX=1`)
- `testing` — test pair (round `TEST_ROUND`)
- `done` — `clean` and the backlog is empty
- `blocked` — a role returned `blocked`, the pair did not converge, bugs did not go away, a role gave no handoff
</stages>

<transitions>
| Role [mode]       | STATUS          | Next                                                          |
| ----------------- | --------------- | ------------------------------------------------------------- |
| planner [work]    | done            | critic                                                        |
| critic            | needs-revision  | planner [work], iter+1                                        |
| critic            | approved        | planner [sign]                                                |
| planner [sign]    | approved        | coding: wave 1 (plan.md, wave count)                          |
| planner [sign]    | needs-revision  | critic, iter+1                                                |
| coder [work/bugfix] | done          | reviewer                                                      |
| reviewer          | needs-revision  | coder, iter+1                                                 |
| reviewer          | approved        | fix → testing; otherwise next wave or testing                 |
| tester            | done            | debugger                                                      |
| debugger          | needs-revision  | tester, iter+1                                                |
| debugger          | bugs-found      | coding [bugfix] (round+1; ≥ max → blocked)                    |
| debugger          | clean           | backlog? new cycle (planning) : done (archive cycle-N)        |
| any               | blocked         | blocked                                                       |
| any (input)       | amendment in amendments/pending | interrupt the role → planning (replan)        |

Limits: `DT_MAX_PAIR_ITERS` (5) pair iterations, `DT_MAX_TEST_ROUNDS` (3) test rounds,
`DT_MAX_NUDGES` (1) role retry without a valid handoff.
</transitions>

<state>
`.planning/agent-pipeline/state.env` — canonical (written only by the script):

```
TASK_ID CREATED STAGE STEP CYCLE PAIR ITER WAVE TOTAL_WAVES WAVE_ID BUGFIX TEST_ROUND
NEXT_ROLE NEXT_MODE IN_HANDOFF LAST_HANDOFF LAST_STATUS BLOCK_REASON
```

`NEXT_ROLE` + `NEXT_MODE` + `IN_HANDOFF` — what to launch next; resuming after a
stop = exactly this step. `pipeline-state.json` (version 3.0) is generated from state.env
together with `history` (from `history.jsonl`) — read-only for humans and roles.

Everything else in `.planning/agent-pipeline/`: `handoffs/step-NN-<role>.md`, `task-context.md`,
`plan-draft.md`, `plan.md`, `critique.md`, `approval-*.md`, `code-summary.md`,
`review-report.md`, `test-report.md`, `debug-report.md`, `clean-report.md`, `bug-reports/`,
`amendments/{pending,applied}/`, `backlog/{pending,taken}/`, `archive/`, `sessions/`,
`run.log`, `run.lock`.
</state>
