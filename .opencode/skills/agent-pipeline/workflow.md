<!-- agent-pipeline workflow (pair model, subagents) -->
<purpose>
Pipeline orchestration with three antagonistic pairs. The Manager is the deterministic
orchestrator script `agent-manager/dt-run.sh` (not a model): it hands out tasks and routes
between pairs. Roles are separate `opencode run --agent agent-<role>` with a fresh context,
communicating only through files on disk.
</purpose>

<architecture>
```
            ┌─────────── Manager (primary, dispatcher) ───────────┐
            │  hands out tasks, runs pairs mechanically, routes    │
            └──────────────┬───────────────┬───────────────┬──────┘
                           │               │               │
                    PLAN pair        CODE pair        TEST pair
                  planner⇄critic   coder⇄reviewer  tester⇄debugger
                  (doer ⇄ critic)  (doer ⇄ critic) (doer ⇄ critic)
```
- Inside a pair doer and critic are antagonists: the doer does, the critic criticizes, loop until agreement.
- Each role is a separate subagent (clean context). No shared dialogue.
- The only shared memory — files in `.planning/agent-pipeline/` (+ handoffs).
- The pair loop is run by the orchestrator (see pair-protocol.md) strictly mechanically by STATUS,
  without interfering in quality assessment. Launch details — agent-manager/dt-commands.md.
</architecture>

<core_principle>
The Manager is a dispatcher, NOT an executor and NOT a judge of quality. It decides only transitions BETWEEN
pairs and mechanically runs the loop inside a pair by the STATUS in the handoff. Assessment comes from the pair's critic
role (critic / reviewer / debugger). No role moves on without the Manager.
</core_principle>

<references>
- `state-machine.md` — stages, transitions between pairs, pipeline-state.json schema
- `pair-protocol.md` — doer↔critic loop mechanics inside a pair
- `handoff-protocol.md` — handoff format and context hygiene (do not lose / do not overflow)
Agents: `.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md`
</references>

<pairs_contract>

### PLAN pair — planner (doer) ⇄ critic (critic)
Input: task-context.md. Loop: planner builds plan-draft → critic hunts holes (critique) →
planner fixes → … until zero critical/major. Consensus: approval-planner.md + approval-critic.md.
Output to the Manager: signed plan.md.

### CODE pair — coder (doer) ⇄ reviewer (critic)
Input: plan.md (wave) or bug-reports/. Loop: coder implements by TDD (code-summary) →
reviewer checks (lint, style, duplicates, dead code, SOLID, plan, tests) → coder fixes →
… until a clean review. Consensus: approval-reviewer.md. Output: approved wave code.

### TEST pair — tester (doer) ⇄ debugger (critic)
Input: the built result + plan.md. Loop: tester breaks the application (test-report) → debugger
investigates each FAIL, confirms/refutes (debug-report + bug-reports) → aligns the
verdict with the tester → … until consensus. Output to the Manager: `clean` (no bugs) or `bugs-found`
(confirmed ones exist). Manager: clean → done; bugs-found → the CODE pair again.
</pairs_contract>

<context_discipline>
After EVERY step, before handing over:
1. The role writes a full handoff (status + what was done + artifacts + what the next one should do).
2. The role returns only a short receipt to the Manager and exits (its context disappears).
3. The next role starts from a CLEAN context and restores everything from the handoff+artifacts.
So context is not lost (everything is on disk) and does not overflow (nobody drags someone else's context).
Details — handoff-protocol.md.
</context_discipline>

<stall_detection>
The Manager tracks stalls:
- A role returned STATUS=blocked (ambiguity/environment error) → stage blocked, report to the user.
- The pair did not converge within `config.max_pair_iters` iterations → blocked.
- Repeated role stall (nudge > max_nudges) → blocked.
</stall_detection>
