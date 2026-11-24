#!/usr/bin/env bash
#
# dream-team: single entry point (terminal and slash commands). cwd = project root.
#
#   dt                         resume; no pipeline — a task is needed
#   dt --new <task>            new task (--force — over an unfinished one)
#   dt --new @prompt.md        task from a file (for huge prompts)
#   dt --add <amendment>       amendment: a live run interrupts the role and replans
#   dt --issue <addition>      to the backlog: a new cycle after done
#   dt --status                where the pipeline is, who is working, elapsed time
#   dt --log [N] | --log -f    orchestrator log
#   dt --stop                  stop (state is kept; resume: dt)
#   dt --bg …                  start the orchestrator in the background (slash commands do this)
#
# Handy: alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'
# `--stdin` — the message is read from stdin (slash commands call it so: text as is, via heredoc).
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dt-lib.sh
. "${HERE}/dt-lib.sh"

bg=0; from_stdin=0
while :; do
  case "${1:-}" in
    --bg)    bg=1; shift ;;
    --stdin) from_stdin=1; shift ;;
    *) break ;;
  esac
done

status(){
  if ! state_exists; then echo "no pipeline (${P}). Start: dt --new <task>"; return 0; fi
  state_load
  local role="" started="" sid="" el=""
  if lock_alive; then
    echo "orchestrator: running (pid $(lock_pid))"
    if [ -f "${P}/current-role" ]; then
      role="$(sed -n 's/.*role=\([^ ]*\).*/\1/p' "${P}/current-role")"
      started="$(sed -n 's/.*started=\([^ ]*\).*/\1/p' "${P}/current-role")"
      sid="$(cat "${P}/current-session" 2>/dev/null || true)"
      el="$(( ( $(date +%s) - $(mtime "${P}/current-role") ) / 60 ))"
      echo "now:         ${role} · ${el} min · session ${sid:-(no id yet)}"
    fi
  else
    echo "orchestrator: not running"
  fi
  echo "stage:       ${STAGE} · cycle ${CYCLE} · step ${STEP} · pair ${PAIR:-—} iter ${ITER}"
  [ "${STAGE}" = coding ] && echo "wave:        ${WAVE}/${TOTAL_WAVES} ${WAVE_ID}"
  [ -n "${NEXT_ROLE}" ] && echo "next:        ${NEXT_ROLE} [${NEXT_MODE}] ← $(basename "${IN_HANDOFF:-—}")"
  [ -n "${BLOCK_REASON}" ] && echo "blocked:     ${BLOCK_REASON}"
  echo "queue:       amendments $(pending_files "${P}/amendments/pending" | grep -c . || true), backlog $(pending_files "${P}/backlog/pending" | grep -c . || true)"
  if [ -f "${P}/run.log" ]; then echo "── log ──"; tail -n 8 "${P}/run.log"; fi
}

stop(){
  if ! lock_alive; then echo "the orchestrator is not running"; return 0; fi
  local pid; pid="$(lock_pid)"
  touch "${P}/stop.request"
  echo "stopping (pid ${pid}): the current role will be interrupted, state will be kept…"
  local i; for i in $(seq 1 40); do kill -0 "${pid}" 2>/dev/null || { echo "stopped. Resume: dt"; return 0; }; sleep 1; done
  echo "did not stop within 40 s — sending TERM"; kill -TERM "${pid}" 2>/dev/null
}

case "${1:-}" in
  --status|status) status; exit 0 ;;
  --stop|stop)     stop; exit 0 ;;
  --log|log)
    shift
    [ -f "${P}/run.log" ] || { echo "no log"; exit 0; }
    if [ "${1:-}" = -f ]; then exec tail -n 30 -F "${P}/run.log"; else tail -n "${1:-40}" "${P}/run.log"; fi
    exit 0 ;;
esac

if [ "${from_stdin}" = 1 ]; then msg="$(cat)"; else msg="$*"; fi

out="$(printf '%s' "${msg}" | bash "${HERE}/dt.sh")"
text="$(printf '%s\n' "${out}" | sed -n 's/^MSG=//p')"
[ -n "${text}" ] && printf '%s\n' "${text}"
printf '%s\n' "${out}" | grep -qx 'ACTION=run' || exit 0

if [ "${bg}" = 1 ]; then
  mkdir -p "${P}"
  nohup bash "${HERE}/dt-run.sh" </dev/null >>"${P}/run.out" 2>&1 &
  pid=$!
  sleep 2
  if kill -0 "${pid}" 2>/dev/null; then
    echo "orchestrator started in the background (pid ${pid}). Watch: /dt-status (dt --status), log: dt --log -f"
  else
    echo "the orchestrator did not start — see ${P}/run.out:"; tail -n 5 "${P}/run.out"
  fi
  exit 0
fi
exec bash "${HERE}/dt-run.sh"
