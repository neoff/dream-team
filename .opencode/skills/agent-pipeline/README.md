# Agent Pipeline — paired agent pipeline for OpenCode

## Overview

Development through three antagonistic role pairs, dispatched by the Manager.
Each role is a separate opencode **subagent** with a fresh context; roles communicate only
through files on disk (handoff + artifacts), so context is neither lost nor overflowed.

```
                 Manager (primary, dispatcher)
         hands out tasks, runs pairs, routes
          │                  │                   │
      PLAN pair          CODE pair           TEST pair
   planner ⇄ critic   coder ⇄ reviewer   tester ⇄ debugger
    (doer ⇄ critic)    (doer ⇄ critic)    (doer ⇄ critic)
          │                  │                   │
     plan.md signed     code approved      verdict: clean / bugs-found
          └──────────────────┴───────────────────┘
                 everything returns to the Manager,
       it decides the transition to the next pair (or done/coding)
```

Inside a pair the doer and critic are antagonists: the doer does, the critic criticizes, loop until agreement.
Only after consensus does the pair hand the Manager a "done, agreed" result, and the Manager
routes further. The Manager **does not interfere inside a pair** — it only mechanically runs
the loop by the STATUS in the handoff (opencode limitation: subagent nesting = 1 level, so
the primary physically runs the loop, but as a dumb dispatcher).

## Roles (opencode agents)

| Role         | Agent (`.opencode/agents/`) | Pair | Function in pair | Responsibility                                     |
| ------------ | --------------------------- | ---- | ---------------- | -------------------------------------------------- |
| **Manager**  | `agent-manager` (primary)   | —    | dispatcher       | hands out tasks, runs pairs, routes, final/escalation |
| **Planner**  | `agent-planner`             | plan | doer             | decomposition into phases/waves/tasks, TDD strategy |
| **Critic**   | `agent-critic`              | plan | critic           | ruthless plan audit, finding all problems          |
| **Coder**    | `agent-coder`               | code | doer             | TDD implementation, atomic commits                 |
| **Reviewer** | `agent-reviewer`            | code | critic           | lint, style, duplicates, dead code, SOLID, plan    |
| **Tester**   | `agent-tester`              | test | doer             | E2E, edge, negative, security, load                |
| **Debugger** | `agent-debugger`            | test | critic           | root cause, confirm/refute, bug reports            |

Each role's detailed craft rules are in `.opencode/skills/agent-<role>/` (SKILL.md + guide);
the agent reads them as a reference.

## Key principles

1. **Antagonistic pairs** — the doer does, the critic criticizes, until both agree.
2. **The Manager is a dispatcher, not a judge** — quality is assessed by critic/reviewer/debugger, not by it.
3. **Fresh context for every role** — role = subagent, starts from scratch, reads only
   its handoff + the named artifacts.
4. **Handoff after every step** — before handing over the role writes a full status+handoff; everything
   important is on disk, context is neither lost nor overflowed.
5. **Strict TDD** — the Coder writes the failing test FIRST.
6. **Critic/Reviewer/Debugger do not fix** — they only point out; the doer fixes.
7. **Blood oaths** — Critic, Reviewer, Debugger sign their results.
8. **Stall detection** — role=blocked or the pair did not converge within `max_pair_iters` → blocked.

## Launch

The Manager is a primary agent (not a skill):

```bash
cd <project-root>   # directory containing .opencode/

# new run
opencode run --agent agent-manager "Create a REST API for users with JWT authorization"

# resume an interrupted one
opencode run --agent agent-manager "resume"
```

or interactively: start opencode, switch the agent to `agent-manager`, give the task.
Wrapper reference: skill `/agent-pipeline-run`.

## Artifacts (in `.planning/agent-pipeline/`)

```
pipeline-state.json      # State (single source of truth)
task-context.md          # Task verbatim + how it was understood
handoffs/
  step-00-manager.md     # Handoff of each step (status, what was done, what is next)
  step-01-planner.md
  ...
plan-draft.md            # Plan draft (plan pair)
plan.md                  # Final plan (after planner+critic approval)
critique.md              # Critic's remarks
approval-planner.md      # Planner's signature
approval-critic.md       # Critic's signature (oath)
code-summary.md          # Coder's report
review-report.md         # Reviewer's remarks
approval-reviewer.md     # Reviewer's signature
test-report.md           # Tester's report (FAIL cases)
debug-report.md          # Debugger's investigation
clean-report.md          # Clean report (no bugs)
bug-reports/
  bug-001.md             # Confirmed bug with a deterministic repro
  ...
archive/                 # Where the Manager archives artifacts on completion
```

## State machine (between pairs)

```
init → planning → coding → testing → done
                    ▲          │
                    └──────────┘
                 bugs-found (code pair again)

planning: the plan pair loops until approval-critic + approval-planner
coding:   the code pair loops until approval-reviewer (by waves)
testing:  the test pair loops until an agreed verdict (clean | bugs-found)
```

The loop INSIDE a pair (doer→critic→doer…) — in `pair-protocol.md`, not shown here.

## Protocol documents

- `workflow.md` — architecture overview and pair contracts
- `state-machine.md` — stages, transitions between pairs, pipeline-state.json schema (v2)
- `pair-protocol.md` — doer↔critic loop and consensus mechanics
- `handoff-protocol.md` — handoff format, context hygiene (do not lose / do not overflow)

## Configuration (in pipeline-state.json)

```json
{
  "config": {
    "max_pair_iters": 5,
    "tdd_required": true,
    "coverage_threshold": 80,
    "timeouts_minutes": { "planner": 10, "critic": 5, "coder": 15, "reviewer": 5, "tester": 10, "debugger": 10 },
    "max_nudges": 2
  }
}
```

## Structure

```
.opencode/
├── agents/                      # Executable roles (opencode subagents)
│   ├── agent-manager.md         #   primary — dispatcher
│   ├── agent-planner.md         #   subagent (plan pair, doer)
│   ├── agent-critic.md          #   subagent (plan pair, critic)
│   ├── agent-coder.md           #   subagent (code pair, doer)
│   ├── agent-reviewer.md        #   subagent (code pair, critic)
│   ├── agent-tester.md          #   subagent (test pair, doer)
│   └── agent-debugger.md        #   subagent (test pair, critic)
└── skills/
    ├── agent-pipeline/          # Protocols and overview
    │   ├── README.md
    │   ├── workflow.md
    │   ├── pair-protocol.md
    │   └── handoff-protocol.md
    ├── agent-pipeline-run/      # Entry point (how to launch the manager)
    │   └── SKILL.md
    ├── agent-manager/           # Reference + state machine
    │   ├── SKILL.md
    │   └── state-machine.md
    ├── agent-planner/           # Role craft references
    │   ├── SKILL.md
    │   └── planning-guide.md
    ├── agent-critic/
    │   ├── SKILL.md
    │   └── critique-guide.md
    ├── agent-coder/
    │   ├── SKILL.md
    │   └── coding-guide.md
    ├── agent-reviewer/
    │   ├── SKILL.md
    │   └── review-guide.md
    ├── agent-tester/
    │   ├── SKILL.md
    │   └── testing-guide.md
    └── agent-debugger/
        ├── SKILL.md
        └── debugging-guide.md
```
