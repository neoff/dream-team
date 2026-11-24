# dream-team: how to start a session via mahcode MCP

The manager launches leads, leads launch roles — the same way, with the tools of the `mahcode`
MCP server (`create_session`, `send_message`, `wait_for_session`, `get_session_status`).
Not via shell and not via the built-in `subagent` (it does not work on external engines yet).

## Launch and wait for the result

1. `create_session`:
   - `directory` — ABSOLUTE path of the project root (the same one that holds `.planning/`);
   - `title` — `dt <TASK_ID> <what>`, e.g. `dt 20261121-1530 plan-lead`, `dt 20261121-1530 plan-i2-critic`;
   - `model` — from `.mahcode/dream-team.yaml` (`leads` for a lead, `roles.<role>` for a role);
   - `ttl_seconds` — `limits.session_ttl` (mahcode deletes the session itself after inactivity).
   Write the returned `id` into state (`.planning/dream-team/state.md`) BEFORE sending the brief.
2. `send_message(session_id=id, content=<brief>)` — WITHOUT `wait` (returns immediately).
3. Then `wait_for_session(session_id=id, timeout_seconds=60)` again and again while
   `processing=true` or `timed_out=true`. **Never set timeout above 60 s and never use
   `wait=true` in send_message**: engines (codex etc.) cut an MCP call after 300 s, after which
   the mahcode MCP server gets stuck and the following calls fail too. Do NOT send new briefs
   into a busy session.
   Between waits (every ≤ 60 s) you get control back — for the manager this is the moment to
   process new messages from the interlocutor (see manager.md).
4. The result is the `latest_result` field (the session's last reply). But the truth is the
   handoff file the session had to write: read its `## STATUS`.

## If the session failed
- No handoff or STATUS not in the list → ONE retry: `send_message` into the same session:
  "You did not write a valid handoff to <path> (STATUS from: …). Finish and write it." Second
  failure → `blocked` with the reason.
- `status=faulted` (the session crashed) → one retry in a NEW session with the same brief; second
  failure → `blocked`.

## Urgent signals (amendment, stop) — files only
Do not rely on `send_message(..., mode="steer")` into a busy session: on external engines (codex,
claude, agy) a turn is one process and steer does not reach the model. Signals are files:
`.planning/dream-team/inbox/*` (commands to the manager) and `.planning/dream-team/interrupt.md`
(manager → lead). That is why waiting is always short `wait_for_session` calls of ≤ 60 s — check
the files between them.

## Don'ts
- Do not create a second session for the same step while the first is alive (`get_session_status`).
- Do not keep other sessions' artifact contents in your context — pass paths.
