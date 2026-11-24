#!/usr/bin/env bash
#
# dream-team: deterministic pipeline orchestrator (instead of an LLM Manager).
#
#   bash .opencode/skills/agent-manager/dt-run.sh      # cwd = project root
#
# Runs three antagonistic pairs per the state machine:
#   plan: planner → critic → … → planner(sign) → code: coder → reviewer (by waves)
#   → test: tester → debugger → clean | bugs-found(→ code) → backlog? new cycle : done
# Each role is a separate `opencode run --agent agent-<role>` with a fresh context. The role
# gets the input handoff path and the EXACT path of its output handoff; the orchestrator reads
# `## STATUS` from it and decides the transition. Only the orchestrator writes the state (state.env).
#
# While a role works it watches:
#   amendments/pending — amendment (/dt-add): the role is interrupted, replan (DT_ADD_INTERRUPT=step —
#                        wait for the step to finish);
#   stop.request       — /dt-stop: the role is interrupted, state is kept (resume: /dt);
#   role timeout and a "hung" process (handoff written, but the process does not exit).
# After each role its session is exported to sessions/ and deleted from opencode — otherwise
# the opencode background service "resurrects" interrupted sessions (zombie roles).
#
# Settings (env): DT_MAX_PAIR_ITERS=5 DT_MAX_TEST_ROUNDS=3 DT_MAX_NUDGES=1
#   DT_TIMEOUT_<ROLE>=min (PLANNER 40, CRITIC 25, CODER 90, REVIEWER 30, TESTER 60, DEBUGGER 60)
#   DT_HANG_GRACE_SEC=180 DT_KEEP_SESSIONS=0 DT_ADD_INTERRUPT=now|step DT_MODEL=<provider/model>
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dt-lib.sh
. "${HERE}/dt-lib.sh"

MAX_ITERS="${DT_MAX_PAIR_ITERS:-5}"
MAX_TEST_ROUNDS="${DT_MAX_TEST_ROUNDS:-3}"
MAX_NUDGES="${DT_MAX_NUDGES:-1}"
HANG_GRACE="${DT_HANG_GRACE_SEC:-180}"
KEEP_SESSIONS="${DT_KEEP_SESSIONS:-0}"
ADD_INTERRUPT="${DT_ADD_INTERRUPT:-now}"
POLL="${DT_POLL_SEC:-3}"
STOP=0
SKILLS_DIR="$(dirname "${HERE}")"                 # …/skills (local or global)
AGENTS_DIR="$(dirname "${SKILLS_DIR}")/agents"
case "${SKILLS_DIR}" in "$(pwd)"/*) SKILLS_DIR=".${SKILLS_DIR#"$(pwd)"}"; AGENTS_DIR=".${AGENTS_DIR#"$(pwd)"}" ;; esac

timeout_min(){
  case "$1" in
    planner)  echo "${DT_TIMEOUT_PLANNER:-40}" ;;
    critic)   echo "${DT_TIMEOUT_CRITIC:-25}" ;;
    coder)    echo "${DT_TIMEOUT_CODER:-90}" ;;
    reviewer) echo "${DT_TIMEOUT_REVIEWER:-30}" ;;
    tester)   echo "${DT_TIMEOUT_TESTER:-60}" ;;
    debugger) echo "${DT_TIMEOUT_DEBUGGER:-60}" ;;
    *)        echo 30 ;;
  esac
}

log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${P}/run.log"; }
die(){ log "ERROR: $*"; exit 1; }

# --- role statuses ---------------------------------------------------------------
allowed_statuses(){ # $1 role $2 mode
  case "$1:$2" in
    planner:sign) echo "approved needs-revision blocked" ;;
    planner:*)    echo "done blocked" ;;
    critic:*)     echo "approved needs-revision blocked" ;;
    coder:*)      echo "done blocked" ;;
    reviewer:*)   echo "approved needs-revision blocked" ;;
    tester:*)     echo "done blocked" ;;
    debugger:*)   echo "clean bugs-found needs-revision blocked" ;;
  esac
}

read_status(){ # $1 handoff -> first word under "## STATUS", lowercased
  [ -f "$1" ] || return 0
  awk 'f && NF { print; exit } /^##[[:space:]]*STATUS/ { f=1 }' "$1" \
    | sed 's/[`*]//g; s/\[//g; s/\]//g' | awk '{print $1}' | sed 's/^status[=:]//' | tr 'A-Z' 'a-z'
}

in_list(){ local x; for x in $2; do [ "$x" = "$1" ] && return 0; done; return 1; }

# --- step task for a role ---------------------------------------------------------
mode_text(){ # $1 role $2 mode
  case "$1:$2" in
    planner:work) echo "Build or refine .planning/agent-pipeline/plan-draft.md from the input handoff. On
iteration > 1 fix EVERY critical/major remark from critique.md (minor — fix or
justify). Mark waves with headings \`### Wave X.Y: <name>\`. Do not sign approval." ;;
    planner:sign) echo "The critic approved the plan (approval-critic.md). Re-read plan-draft.md. Agree — sign
.planning/agent-pipeline/approval-planner.md (the oath from planning-guide.md) and copy
plan-draft.md to .planning/agent-pipeline/plan.md; STATUS=approved. See a problem — fix
plan-draft.md and set STATUS=needs-revision (the critic will look again)." ;;
    critic:*) echo "Assess .planning/agent-pipeline/plan-draft.md by your rules. critical/major or
needed fixes exist — write critique.md, STATUS=needs-revision. The plan is flawless — write
approval-critic.md, STATUS=approved." ;;
    coder:bugfix) echo "Fix ALL confirmed bugs from .planning/agent-pipeline/bug-reports/ (see debug-report.md):
for each — regression test (RED) → fix (GREEN) → run all tests → atomic commit.
Update code-summary.md. On a repeat per reviewer remarks — fix everything from review-report.md." ;;
    coder:*) echo "Implement ONLY wave \"${WAVE_ID}\" (wave ${WAVE} of ${TOTAL_WAVES}) from .planning/agent-pipeline/plan.md:
strict TDD (RED → GREEN → REFACTOR), run all tests, atomic commits. Do not touch other
waves. Update code-summary.md. On a repeat per reviewer remarks — fix ALL items of
review-report.md." ;;
    reviewer:*) if [ "${BUGFIX}" = 1 ]; then echo "Review the bug fix (bug-reports/, code-summary.md, commits) by your rules."
      else echo "Review the code of wave \"${WAVE_ID}\" (code-summary.md, the wave's commits) by your rules."; fi
      echo "Blocking remarks exist — review-report.md, STATUS=needs-revision. Clean —
approval-reviewer.md, STATUS=approved." ;;
    tester:*) echo "Test the built result by the matrix from testing-guide.md (happy, boundary, invalid,
errors, security, concurrency, performance) against plan.md and task-context.md. Repeat each FAIL
3×. Report — .planning/agent-pipeline/test-report.md (has FAIL) or clean-report.md (none).
If the input handoff is from the debugger — answer its questions/clarify the repro. STATUS=done." ;;
    debugger:*) echo "Analyse test-report.md / clean-report.md: reproduce and classify each FAIL
(CONFIRMED_BUG / NOT_A_BUG / FLAKY / ENVIRONMENT). Even with no FAILs independently check
the plan's key scenarios before signing clean — you are the pair's second key. Verdict in STATUS:
clean (no confirmed bugs; clean-report.md), bugs-found (bug-reports/bug-NNN.md +
debug-report.md), needs-revision (clarification/recheck needed from the tester — what exactly, in the handoff)." ;;
  esac
}

build_prompt(){ # $1 role $2 mode $3 in $4 out $5 extra note
  cat <<EOF
You are the "$1" role of the dream-team pipeline. You were launched by the orchestrator (dt-run.sh) instead of the Manager:
everything your rules say about the Manager refers to it. Your rules are in
${AGENTS_DIR}/agent-$1.md and ${SKILLS_DIR}/agent-$1/ (paths .opencode/skills/… in the rules = ${SKILLS_DIR}/…).

INPUT: handoff \`$3\` — start with it (and its ARTIFACTS).

TASK OF THIS STEP:
$(mode_text "$1" "$2")

OUTPUT (mandatory):
1. Write your handoff EXACTLY into the file \`$4\` in the format of
   ${SKILLS_DIR}/agent-pipeline/handoff-protocol.md. In the \`## STATUS\` section — exactly one
   word from: $(allowed_statuses "$1" "$2").
2. All your artifacts — only in .planning/agent-pipeline/. Put nothing in the project root
   (reports, cover.out, coverage.out — also in .planning/agent-pipeline/).
3. Do not add .planning/ to git. Committing code is allowed and required (coder role).
4. Do not launch other roles or agents, do not call opencode from shell.
5. Last line of the reply: \`status=<STATUS> handoff=$4\`.
$5
EOF
}

# --- opencode sessions ------------------------------------------------------------------
find_sid(){ # $1 role jsonl log, $2 agent, $3 start time (sec) -> session id
  local sid id g
  sid="$(grep -o '"sessionID":"[^"]*"' "$1" 2>/dev/null | head -1 | cut -d'"' -f4)"
  if [ -n "${sid}" ]; then printf '%s' "${sid}"; return 0; fi
  # the --format json stream may not have caught up: look for a fresh session of this agent in this directory
  for id in $(opencode session list 2>/dev/null | head -8 | cut -f1); do
    g="$(tmo 20 opencode api session.get --param sessionID="${id}" 2>/dev/null)"
    printf '%s' "${g}" | grep -q "\"agent\":\"$2\"" || continue
    printf '%s' "${g}" | grep -q "\"directory\":\"$(pwd)\"" || continue
    c="$(printf '%s' "${g}" | grep -oE '"created":[0-9]+' | head -1 | grep -oE '[0-9]+$')"
    [ -n "${c}" ] && [ "$((c / 1000))" -ge "$(( $3 - 5 ))" ] && { printf '%s' "${id}"; return 0; }
  done
}

session_cleanup(){ # $1 sid $2 export file $3 was it interrupted (1/0)
  [ -n "$1" ] || { log "  ! session id not found — check opencode session list"; return 0; }
  if [ "$3" = 1 ]; then tmo 20 opencode api session.interrupt --param sessionID="$1" --param resume=false >/dev/null 2>&1 || true; fi
  tmo 90 opencode session export "$1" > "$2" 2>/dev/null || rm -f "$2"
  if [ "${KEEP_SESSIONS}" != 1 ]; then
    tmo 30 opencode session delete "$1" >/dev/null 2>&1 || log "  ! failed to delete session $1"
  fi
  rm -f "${P}/current-session"
}

kill_tree(){ # $1 pid of the group leader
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null
  local i; for i in 1 2 3 4 5; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
  kill -KILL -- "-$1" 2>/dev/null || kill -KILL "$1" 2>/dev/null
}

# Run a role. Sets RR_RESULT (ok|amend|stopped|timeout|hung|crashed), RR_SID.
run_role(){ # $1 role $2 in $3 out $4 prompt
  local role="$1" out="$3" jsonl tmo start pid result=ok sid="" now om rc
  jsonl="${P}/sessions/$(basename "${out}" .md).jsonl"
  tmo="$(timeout_min "${role}")"
  start="$(date +%s)"
  set -m
  if [ -n "${DT_MODEL:-}" ]; then
    opencode run --standalone --agent "agent-${role}" --model "${DT_MODEL}" --format json "$4" </dev/null >"${jsonl}" 2>&1 &
  else
    opencode run --standalone --agent "agent-${role}" --format json "$4" </dev/null >"${jsonl}" 2>&1 &
  fi
  pid=$!
  set +m
  printf 'pid=%s role=%s started=%s out=%s\n' "${pid}" "${role}" "$(now_iso)" "${out}" > "${P}/current-role"
  while kill -0 "${pid}" 2>/dev/null; do
    sleep "${POLL}"
    if [ -z "${sid}" ]; then
      sid="$(grep -o '"sessionID":"[^"]*"' "${jsonl}" 2>/dev/null | head -1 | cut -d'"' -f4)"
      [ -n "${sid}" ] && printf '%s\n' "${sid}" > "${P}/current-session"
    fi
    if [ "${STOP}" = 1 ] || [ -f "${P}/stop.request" ]; then result=stopped; break; fi
    if [ "${ADD_INTERRUPT}" = now ] && has_pending "${P}/amendments/pending"; then result=amend; break; fi
    now="$(date +%s)"
    if [ $((now - start)) -gt $((tmo * 60)) ]; then result=timeout; break; fi
    if [ -f "${out}" ] && grep -q '^##[[:space:]]*STATUS' "${out}"; then
      om="$(mtime "${out}")"
      if [ $((now - om)) -gt "${HANG_GRACE}" ]; then result=hung; break; fi
    fi
  done
  local interrupted=0
  if kill -0 "${pid}" 2>/dev/null; then interrupted=1; kill_tree "${pid}"; fi
  wait "${pid}" 2>/dev/null; rc=$?
  if [ "${result}" = ok ] && [ "${rc}" != 0 ] && [ ! -f "${out}" ]; then result=crashed; fi
  [ -n "${sid}" ] || sid="$(find_sid "${jsonl}" "agent-${role}" "${start}")"
  session_cleanup "${sid}" "${P}/sessions/$(basename "${out}" .md).session.json" "${interrupted}"
  rm -f "${P}/current-role"
  RR_RESULT="${result}"; RR_SID="${sid}"
  log "  ← ${role}: ${result} in $(( ($(date +%s) - start) / 60 )) min (session ${sid:-?})"
}

# --- repository hygiene ---------------------------------------------------------------
# Role junk: everything untracked (and not in .gitignore) that appeared during the role and was not
# committed is moved to stray/step-NN/ preserving paths. The coder must commit sources.
untracked(){ git ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.planning/' | grep -v '^\.opencode/' | LC_ALL=C sort; }
hygiene_before(){
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { UNTRACKED_BEFORE=""; return 0; }
  UNTRACKED_BEFORE="$(untracked)"
}
repo_hygiene(){
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local f dst moved=""
  while IFS= read -r f; do
    [ -n "${f}" ] || continue
    dst="${P}/stray/step-$(nn "${STEP}")/${f}"
    mkdir -p "$(dirname "${dst}")" && mv "${f}" "${dst}" && moved="${moved} ${f}"
    [ "$(dirname "${f}")" = . ] || rmdir -p "$(dirname "${f}")" 2>/dev/null || true
  done < <(LC_ALL=C comm -13 <(printf '%s\n' "${UNTRACKED_BEFORE:-}") <(untracked))
  [ -n "${moved}" ] && log "  ! the role left uncommitted files —${moved} → ${P}/stray/step-$(nn "${STEP}")/"
  if [ -n "$(git ls-files "${P}" 2>/dev/null | head -1)" ]; then
    log "  ! files of ${P}/ got into git (the role committed .planning) — check the history"
  fi
  return 0
}

ensure_git_exclude(){
  local ex
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 0
  mkdir -p "$(dirname "${ex}")"; touch "${ex}"
  grep -qx '.planning/' "${ex}" || printf '.planning/\n' >> "${ex}"
}

# --- state machine transitions --------------------------------------------------------------
block(){ STAGE=blocked; BLOCK_REASON="$1"; history_add blocked "\"reason\": $(json_str "$1")"; state_save; log "⛔ blocked: $1"; }

next_iter(){ # next pair iteration; false = limit exceeded (already blocked)
  ITER=$((ITER + 1))
  if [ "${ITER}" -gt "${MAX_ITERS}" ]; then block "pair ${PAIR} did not converge within ${MAX_ITERS} iterations"; return 1; fi
  return 0
}

wave_ids(){ grep -E '^#{2,4}[[:space:]]*Wave[[:space:]]' "${P}/plan.md" 2>/dev/null | sed -E 's/^#+[[:space:]]*Wave[[:space:]]+//' ; }

start_wave(){ # WAVE is already set
  local ho id
  id="$(wave_ids | sed -n "${WAVE}p")"
  WAVE_ID="Wave ${id:-${WAVE}}"; [ "${TOTAL_WAVES}" = 1 ] && [ -z "${id}" ] && WAVE_ID="the whole plan"
  STAGE=coding; PAIR=code; ITER=1; BUGFIX=0
  STEP=$((STEP + 1)); ho="${P}/handoffs/step-$(nn "${STEP}")-manager.md"
  write_handoff "${ho}" coder "The plan is signed by both sides. Starting wave ${WAVE} of ${TOTAL_WAVES}: ${WAVE_ID}." \
    "- \`${P}/plan.md\` — the approved plan (implement only ${WAVE_ID})
- \`${P}/task-context.md\` — the task
$( [ -f "${P}/code-summary.md" ] && echo "- \`${P}/code-summary.md\` — what is already done")" \
    "- Implement ${WAVE_ID} strictly per the plan and TDD; when finished — code-summary.md and a handoff to the reviewer."
  NEXT_ROLE=coder; NEXT_MODE=work; IN_HANDOFF="${ho}"
  history_add wave-start "\"wave\": ${WAVE}, \"wave_id\": $(json_str "${WAVE_ID}")"
}

start_coding(){
  [ -f "${P}/plan.md" ] || { cp "${P}/plan-draft.md" "${P}/plan.md" 2>/dev/null && log "  plan.md was not created by the planner — copied from plan-draft.md"; }
  [ -f "${P}/plan.md" ] || { block "no plan.md after the plan was signed"; return; }
  [ -f "${P}/approval-planner.md" ] || log "  ! the planner confirmed the plan without approval-planner.md"
  TOTAL_WAVES="$(wave_ids | grep -c . || true)"; [ "${TOTAL_WAVES}" -gt 0 ] 2>/dev/null || TOTAL_WAVES=1
  WAVE=1; start_wave
}

archive_wave_approval(){ # reviewer consensus closed — remove the signature so the next wave starts clean
  local d="${P}/archive/waves"; mkdir -p "${d}"
  [ -f "${P}/approval-reviewer.md" ] && mv "${P}/approval-reviewer.md" "${d}/step-$(nn "${STEP}")-approval-reviewer.md"
  [ -f "${P}/review-report.md" ] && mv "${P}/review-report.md" "${d}/step-$(nn "${STEP}")-review-report.md"
  return 0
}

start_testing(){
  local ho d="${P}/archive/test-round-$((TEST_ROUND + 1))-step-$(nn "${STEP}")" f
  for f in test-report.md debug-report.md clean-report.md; do
    if [ -f "${P}/${f}" ]; then mkdir -p "${d}"; mv "${P}/${f}" "${d}/"; fi
  done
  STAGE=testing; PAIR=test; ITER=1; BUGFIX=0
  STEP=$((STEP + 1)); ho="${P}/handoffs/step-$(nn "${STEP}")-manager.md"
  write_handoff "${ho}" tester "The code of all waves is approved by the reviewer. Starting testing (round $((TEST_ROUND + 1)))." \
    "- \`${P}/plan.md\` — the plan (how to run, acceptance criteria)
- \`${P}/task-context.md\` — the task
- \`${P}/code-summary.md\` — what was implemented" \
    "- Try to break the result: test-case matrix from testing-guide.md; report to the debugger."
  NEXT_ROLE=tester; NEXT_MODE=work; IN_HANDOFF="${ho}"
  history_add test-start "\"round\": $((TEST_ROUND + 1))"
}

start_bugfix(){ # $1 debugger handoff
  TEST_ROUND=$((TEST_ROUND + 1))
  if [ "${TEST_ROUND}" -ge "${MAX_TEST_ROUNDS}" ]; then block "bugs remain after ${MAX_TEST_ROUNDS} test rounds"; return; fi
  STAGE=coding; PAIR=code; ITER=1; BUGFIX=1; WAVE_ID="bug fix (round ${TEST_ROUND})"
  NEXT_ROLE=coder; NEXT_MODE=bugfix; IN_HANDOFF="$1"
  history_add bugfix-start "\"round\": ${TEST_ROUND}"
}

transition(){ # $1 role $2 status $3 out
  local role="$1" st="$2" out="$3"
  LAST_HANDOFF="${out}"; LAST_STATUS="${st}"
  history_add "${role}:${st}" "\"handoff\": $(json_str "${out}")"
  if [ "${st}" = blocked ]; then block "role ${role} returned blocked (see ${out})"; return; fi
  case "${role}:${NEXT_MODE}:${st}" in
    planner:work:done)               NEXT_ROLE=critic;  NEXT_MODE=work; IN_HANDOFF="${out}" ;;
    planner:sign:approved)           start_coding ;;
    planner:sign:needs-revision)     next_iter && { NEXT_ROLE=critic; NEXT_MODE=work; IN_HANDOFF="${out}"; } ;;
    critic:*:needs-revision)         next_iter && { NEXT_ROLE=planner; NEXT_MODE=work; IN_HANDOFF="${out}"; } ;;
    critic:*:approved)               NEXT_ROLE=planner; NEXT_MODE=sign; IN_HANDOFF="${out}" ;;
    coder:*:done)                    NEXT_ROLE=reviewer; IN_HANDOFF="${out}" ;;
    reviewer:*:needs-revision)       next_iter && { NEXT_ROLE=coder; IN_HANDOFF="${out}"; } ;;
    reviewer:*:approved)
      archive_wave_approval
      if [ "${BUGFIX}" = 1 ]; then start_testing
      elif [ "${WAVE}" -lt "${TOTAL_WAVES}" ]; then WAVE=$((WAVE + 1)); start_wave
      else start_testing; fi ;;
    tester:*:done)                   NEXT_ROLE=debugger; NEXT_MODE=work; IN_HANDOFF="${out}" ;;
    debugger:*:needs-revision)       next_iter && { NEXT_ROLE=tester; NEXT_MODE=work; IN_HANDOFF="${out}"; } ;;
    debugger:*:bugs-found)           start_bugfix "${out}" ;;
    debugger:*:clean)
      if do_cycle; then log "✓ cycle $((CYCLE - 1)) clean; backlog has additions → cycle ${CYCLE}"
      else do_finalize; log "✓ DONE. Artifacts → ${DT_FINALIZED}"; fi ;;
    *) block "unexpected status \"${st}\" from ${role} (${NEXT_MODE})" ;;
  esac
  state_save
}

# One step: run NEXT_ROLE, read the status, transition.
step_once(){
  local role="${NEXT_ROLE}" mode="${NEXT_MODE:-work}" in="${IN_HANDOFF}" out st note="" attempt=0 allowed
  allowed="$(allowed_statuses "${role}" "${mode}")"
  [ -n "${allowed}" ] || { block "unknown role/mode: ${role}/${mode}"; return; }
  while :; do
    STEP=$((STEP + 1)); out="${P}/handoffs/step-$(nn "${STEP}")-${role}.md"
    state_save
    log "→ step $(nn "${STEP}") ${role}${mode:+ [${mode}]} · pair ${PAIR} iter ${ITER}$( [ "${STAGE}" = coding ] && echo " · ${WAVE_ID}") · input $(basename "${in}")"
    hygiene_before
    run_role "${role}" "${in}" "${out}" "$(build_prompt "${role}" "${mode}" "${in}" "${out}" "${note}")"
    repo_hygiene
    case "${RR_RESULT}" in
      stopped) log "■ stopped by /dt-stop; resume: /dt"; history_add stopped "\"role\": \"${role}\""; state_save; return 2 ;;
      amend)   log "✎ amendment during ${role} — interrupting and replanning"; do_replan; return 0 ;;
    esac
    st="$(read_status "${out}")"
    if in_list "${st}" "${allowed}"; then
      log "  STATUS=${st}"
      transition "${role}" "${st}" "${out}"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "${attempt}" -gt "${MAX_NUDGES}" ]; then
      block "role ${role} gave no valid handoff (${RR_RESULT}, STATUS=\"${st:-none}\", expected: ${allowed})"
      return 0
    fi
    log "  ! invalid result (${RR_RESULT}, STATUS=\"${st:-none}\") — retry ${attempt}/${MAX_NUDGES}"
    note="ATTENTION: the previous run of this step did not write a valid handoff (result: ${RR_RESULT},
STATUS \"${st:-none}\"). Finish the step's work and be sure to write the handoff to the given file."
  done
}

cleanup(){ rm -f "${P}/stop.request" "${P}/current-role" "${P}/current-session"; lock_release; }

# The previous orchestrator was killed hard (kill -9, reboot) — its role may be left orphaned
# and keep writing into the pipeline. Kill it and its session before starting.
reap_orphan(){
  [ -f "${P}/current-role" ] || return 0
  local pid sid
  pid="$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "${P}/current-role")"
  sid="$(cat "${P}/current-session" 2>/dev/null || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null && ps -p "${pid}" -o command= | grep -q 'opencode'; then
    log "  ! found an orphan role from a previous run (pid ${pid}) — stopping it"
    kill_tree "${pid}"
  fi
  if [ -n "${sid}" ]; then session_cleanup "${sid}" "${P}/sessions/orphan-${sid}.session.json" 1; fi
  rm -f "${P}/current-role" "${P}/current-session"
}

main(){
  state_exists || die "no pipeline (${P}): first dt --new <task>"
  if lock_alive; then die "the orchestrator is already running (pid $(lock_pid))"; fi
  ensure_dirs
  lock_take
  trap cleanup EXIT
  trap 'STOP=1' INT TERM
  rm -f "${P}/stop.request"
  reap_orphan
  ensure_git_exclude
  state_load || die "cannot read the state"
  [ -n "${IN_HANDOFF}" ] || IN_HANDOFF="$(ls -t "${P}"/handoffs/*.md 2>/dev/null | head -1)"
  log "══ orchestrator start (pid $$): stage=${STAGE} cycle=${CYCLE} step=${STEP} next=${NEXT_ROLE:-—}"

  if has_pending "${P}/amendments/pending"; then log "✎ amendments pending — replanning"; do_replan; fi
  if [ "${STAGE}" = done ]; then
    if do_cycle; then log "backlog → cycle ${CYCLE}"; else log "everything is done, the backlog is empty"; return 0; fi
  fi
  if [ "${STAGE}" = blocked ]; then log "pipeline blocked: ${BLOCK_REASON}"; return 1; fi
  state_save

  while :; do
    case "${STAGE}" in
      planning|coding|testing) ;;
      done)    log "══ DONE (cycle ${CYCLE}). Result: ${DT_FINALIZED:-${P}/archive}"; return 0 ;;
      blocked) log "══ BLOCKED: ${BLOCK_REASON}. Amend the task (/dt-add) and /dt"; return 1 ;;
      *)       die "unknown stage ${STAGE}" ;;
    esac
    step_once; [ $? = 2 ] && return 0
    if [ "${ADD_INTERRUPT}" = step ] && has_pending "${P}/amendments/pending"; then
      log "✎ amendment — replanning"; do_replan
    fi
  done
}

main "$@"
