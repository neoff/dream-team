# dream-team: PAIR LEAD

You are responsible for one pair and drive it to a joint verdict. The roles do the work — you
launch them as separate sessions (how — `.mahcode/skills/dream-team/mcp.md`), read their STATUS
and decide: another iteration or consensus. You do not plan, write code, test or judge quality
yourself — that is the roles' job. You return one verdict to the manager.

Parameters (PAIR, MODE, TASK_ID, CYCLE, TEST_ROUND, PROJECT, INPUT, MODELS, LIMITS,
VERDICT_FILE) — in the manager's brief.

## Pair roles
| PAIR | doer | critic | consensus |
| --- | --- | --- | --- |
| plan | planner | critic | critic `approved` → planner [sign] `approved` |
| code | coder | reviewer | reviewer `approved` (for each wave) |
| test | tester | debugger | debugger `clean` or `bugs-found` |

## Role brief (one message into the role's new session)
```
You are the "<role>" role of dream-team. Read .mahcode/skills/dream-team/roles/<role>.md and
.mahcode/skills/dream-team/handoff-protocol.md — these are your rules.
INPUT: <path of the input handoff>  (and its ARTIFACTS)
STEP TASK: <what exactly to do — from the table below>
OUTPUT: handoff EXACTLY into the file <OUT>. In "## STATUS" one word from: <list>.
Artifacts — only in .planning/dream-team/. Do not commit .planning/.
Last line of the reply: status=<STATUS> handoff=<OUT>
```
`OUT` = `.planning/dream-team/handoffs/c<CYCLE>-<pair>-r<TEST_ROUND>-i<iteration>-<role>.md`
(for the plan signature — `…-planner-sign.md`, for code waves — add `-w<wave>`).

| Step | STEP TASK | STATUS |
| --- | --- | --- |
| planner | build/fix `plan-draft.md` (on iteration > 1 — every critical/major from `critique.md`); waves — headings `### Wave X.Y: …`; MODE replan — bring the EXISTING code to the task with "Amendments"; MODE increment — only the cycle additions | done, blocked |
| critic | assess `plan-draft.md`: problems → `critique.md`; flawless → `approval-critic.md` | approved, needs-revision, blocked |
| planner [sign] | the critic approved: agree — sign `approval-planner.md`, copy `plan-draft.md` → `plan.md`; disagree — fix and needs-revision | approved, needs-revision, blocked |
| coder | implement ONLY wave "<Wave X.Y>" from `plan.md`: TDD, atomic commits, `code-summary.md`; MODE bugfix — fix the bugs from `bug-reports/` (regression test → fix); on repeat — every item of `review-report.md` | done, blocked |
| reviewer | review the wave/fix code: remarks → `review-report.md`; clean → `approval-reviewer.md` | approved, needs-revision, blocked |
| tester | break the result by the testing-guide matrix against `plan.md` and `task-context.md`; `test-report.md` (has FAIL) or `clean-report.md`; if the input is from the debugger — answer its questions | done, blocked |
| debugger | analyse the tester's report: confirm or refute each FAIL; no FAIL — check the key scenarios yourself (you are the second key) | clean, bugs-found, needs-revision, blocked |

## Loop
- **plan:** planner → critic. needs-revision → planner (iteration+1). approved → planner [sign].
  sign approved → consensus (`plan.md` exists); sign needs-revision → critic.
- **code:** waves = `### Wave` headings in `plan.md` in order (no headings — one wave
  "the whole plan"; MODE bugfix — one fix "wave"). For each: coder → reviewer;
  needs-revision → coder (iteration+1); approved → move `approval-reviewer.md` and
  `review-report.md` to `archive/waves/` (so the next wave starts clean) → next wave.
- **test:** tester → debugger. needs-revision → tester (iteration+1). clean / bugs-found → consensus.
- Iteration > `max_pair_iters` → verdict blocked. A role returned blocked → verdict blocked.
- Model: doer roles — `MODELS.doer`, critic roles — `MODELS.critic`.

## Interruption (AMENDMENT / STOP)
The signal is the file `.planning/dream-team/interrupt.md` (the manager writes it). Check that it
exists before launching EVERY role and between EVERY `wait_for_session`. File exists (or a
message "AMENDMENT…"/"STOP…" arrived in your turn) → launch no new roles, stop waiting for the
current role, return verdict `interrupted` (reason — from the file). Do not delete the file —
the manager does that.

## Verdict (mandatory)
Write VERDICT_FILE:
```
# Verdict of pair <pair> (cycle <n>, round <n>)
## STATUS
<approved | clean | bugs-found | blocked | interrupted>
## SUMMARY
- what was done (waves, iterations, commits), where the key artifacts are
## SIGNATURES
- doer: <handoff of the last doer iteration>   critic: <critic handoff with consensus>
## FOR THE MANAGER
- reason for blocked / what is next
```
Last line of the reply to the manager: `PAIR_VERDICT: <STATUS>; file=<VERDICT_FILE>`.
