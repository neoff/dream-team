---
name: agent-pipeline
description: 'Overview of the paired agent pipeline: three antagonistic pairs (planner+critic, coder+reviewer, tester+debugger) under a Manager-dispatcher. Executed by the agents in .opencode/agents/.'
---

<overview>
A development pipeline of three antagonistic role pairs, dispatched by the Manager.
Each role is an opencode subagent with a fresh context; communication only through files on disk.

- plan pair: planner (doer) ⇄ critic (critic) → signed plan.md
- code pair: coder (doer) ⇄ reviewer (critic) → approved code (by waves)
- test pair: tester (doer) ⇄ debugger (critic) → verdict clean / bugs-found

The Manager hands out tasks and routes BETWEEN pairs; it runs the loop INSIDE a pair
mechanically by the STATUS in the handoff, without judging quality (the pair's critic role does that).
</overview>

<execution>
Executable roles are agents, NOT skills:
`.opencode/agents/agent-{manager,planner,critic,coder,reviewer,tester,debugger}.md`.
Launch: `opencode run --agent agent-manager "<task>"` (see `agent-pipeline-run`).
</execution>

<stages>
init → planning → coding → testing → done
(testing: bugs-found → coding again). Details — state-machine.md.
</stages>

<references>
- `workflow.md` — architecture and pair contracts
- `state-machine.md` (in agent-manager/) — stages, transitions, pipeline-state.json schema
- `pair-protocol.md` — doer↔critic loop mechanics
- `handoff-protocol.md` — handoff format, context hygiene
- `README.md` — full overview, launch, artifacts, structure
</references>
