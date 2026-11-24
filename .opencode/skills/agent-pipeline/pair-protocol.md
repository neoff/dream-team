<!-- agent-pipeline pair protocol: antagonistic doer<->critic loop -->
<purpose>
Mechanics of an antagonistic pair. The Manager executes this loop MECHANICALLY:
alternates doer and critic (each a fresh subagent) until the critic agrees.
The Manager does NOT assess the plan/code/tests itself — assessment is the critic role's job.
</purpose>

<why_manager_drives>
The Manager here is the orchestrator script `dt-run.sh`. It is a "dumb dispatcher" by construction: it looks
only at the STATUS in the handoff and decides "another iteration or consensus". It makes no substantive
quality decisions — the critic roles do (critic / reviewer / debugger). Each role is a
separate opencode process with a fresh context. Transition table — agent-manager/state-machine.md.
</why_manager_drives>

<pairs>
| Pair   | Doer (does)        | Critic (assesses)    | Doer output      | Consensus signal                          |
| ------ | ------------------ | -------------------- | ---------------- | ----------------------------------------- |
| plan   | agent-planner      | agent-critic         | plan-draft.md    | approval-critic.md + approval-planner.md  |
| code   | agent-coder        | agent-reviewer       | code-summary.md  | approval-reviewer.md                      |
| test   | agent-tester       | agent-debugger       | test-report.md   | debugger gave a verdict, tester agrees    |
</pairs>

<loop>
For pair P the Manager does:

1. **Spawn DOER** (subagent, fresh context) with prompt = path to the input handoff.
   - The doer reads the handoff + its ARTIFACTS + its guide.
   - The doer does its iteration, writes the output artifact + handoff (STATUS=done → critic).
   - Returns the receipt `status=done handoff=...`.

2. **Spawn CRITIC** (subagent, fresh context) with prompt = path to the doer's handoff.
   - The critic reads the doer's output, ruthlessly hunts problems.
   - Problems exist → writes a report (critique.md / review-report.md / debug-report.md)
     + handoff (STATUS=needs-revision → doer). Returns the receipt.
   - No problems → writes approval + handoff (STATUS=approved). Returns the receipt.

3. **The Manager looks at the STATUS of the last handoff:**
   - `needs-revision` → increment iter, back to step 1 (the DOER reads the critic's report and fixes).
   - consensus signal reached → the pair is finished, the Manager writes the pair's joint-handoff
     and routes per the state machine to the next pair.
   - `iter > config.max_pair_iters` without consensus → STATUS=blocked, escalation to the user.

Antagonism (mandatory):
- The doer NEVER signs approval for itself. Consensus = approval from the critic.
- The critic fixes nothing itself — only points out. The doer fixes.
- The more real problems the critic found — the better (it is praised for that).
- Both signatures (doer + critic) go into the joint-handoff: both confirm they agree.
</loop>

<test_pair_special>
The test pair differs in its output (its consensus is not "approved" but an agreed VERDICT):

1. tester (doer) runs E2E/edge/load, writes test-report.md (found FAILs).
2. debugger (critic) investigates each FAIL: confirms the bug (root cause + repro) OR
   refutes it (why it is not a bug, plan reference).
3. If the tester disputes the debugger's classification → another iteration (pair debugging),
   until both agree on the final verdict.
4. Pair consensus = tester and debugger agree on the report content. Then a joint-handoff
   to the Manager with one of two STATUS values:
   - `clean` — no confirmed bugs (all FAILs refuted/flaky/env) → everything works.
   - `bugs-found` — confirmed bugs exist (bug-reports/*.md ready).

The Manager per the state machine: `clean` → done; `bugs-found` → the code pair again (fix per bug-reports).
This is what "tester+debugger return to the manager with a joint report, the manager
routes between pairs" means.
</test_pair_special>

<manager_context_discipline>
On every iteration the Manager:
- takes into its context only STATUS + FOR NEXT AGENT of the input handoff and `pipeline-state.json`;
- does NOT read plan-draft/diffs/reports in full — passes the path to the next role;
- updates state (step++, iter, active_role, last_handoff) and saves it;
- role replies are short receipts and do not bloat the context.
</manager_context_discipline>
