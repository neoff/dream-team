<!-- agent-pipeline handoff & context-hygiene protocol -->
<purpose>
A single protocol for passing work between agents. Guarantees: context is NOT lost
(everything important is on disk) and does NOT overflow (each role starts from a clean context,
reads only its handoff + explicitly named artifacts).
</purpose>

<core_rules>

### 1. Every role works in a FRESH context

A role is an opencode subagent. At launch its context is empty. It does NOT see
the previous dialogue or the context of other roles. The only input:

- the path to the input handoff file (the Manager gives it in the prompt),
- the artifacts listed in the `ARTIFACTS` section of that handoff.

The role reads ONLY that (plus its guide). Pull nothing else into context.

### 2. Before passing on — a mandatory handoff

Before finishing, the role WRITES a handoff file (format below). It is a full snapshot:
what was done, where the result is, what the next one should do. After writing, the role returns
to the Manager ONLY one short receipt line:

```
status=<status> handoff=.planning/dream-team/handoffs/step-NN-<role>.md
```

Do NOT dump artifact bodies, diffs, logs into the reply — all of that is already on disk and in
the handoff. A short receipt = the Manager's context does not grow.

### 3. The Manager does not load artifacts into its context

The Manager reads only: `pipeline-state.json`, the `STATUS` and `FOR NEXT AGENT` sections
of input handoffs. Full plans/diffs/reports it does NOT read — it passes them to the next role
by path. So the primary agent's context stays small for the whole pipeline.

### 4. Disk is the only shared memory

Roles and pairs communicate only through files in `.planning/dream-team/`.
If something is not in the handoff or artifacts — it does not exist for the next
role. A role that failed to write something must come back and write it, not rely
on "context".

</core_rules>

<handoff_format>

Path: `.planning/dream-team/handoffs/step-NN-<role>.md`
(`NN` — global step counter from `pipeline-state.json.step`, zero-padded.)

```markdown
# Handoff: <role> → <next-role|manager> (pair: <plan|code|test>, iter <n>)

## STATUS

<done | needs-revision | approved | rejected | bugs-found | clean | blocked>

## DONE

- Concretely what was done in this step (1–7 items, to the point).

## ARTIFACTS (read ONLY these, nothing else is needed)

- `path/to/file` — one line: what it is and why the next one needs it.

## FOR NEXT AGENT

- Exact instruction: what to do next, what to look at first.

## OPEN / RISKS

- Unresolved items, assumptions, doubtful spots (or "none").

## CONTEXT RESET

This handoff + the listed ARTIFACTS = EVERYTHING needed. The previous dialogue is not required
and not available. Start from a clean context.
```

</handoff_format>

<status_values>
- `done` — the doer finished its iteration, passes to the critic for assessment.
- `needs-revision` — the critic found problems, returns to the doer for rework.
- `approved` — the critic agrees, the pair reached consensus (plan/code).
- `bugs-found` — test pair: tester+debugger agree there are confirmed bugs.
- `clean` — test pair: no confirmed bugs, everything works.
- `rejected` — gross mismatch, escalation needed.
- `blocked` — the role cannot continue (ambiguity/environment error) → to the Manager for escalation.
</status_values>

<context_budget>
Signs of overflow (the role must compress, not bloat):
- Reply to the Manager longer than ~3 lines → violation, return only the receipt.
- Handoff longer than ~1 screen → move details to an artifact, leave a link in the handoff.
- The role reads files not listed in its ARTIFACTS → context hygiene violation.
</context_budget>
