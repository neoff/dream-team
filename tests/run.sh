#!/usr/bin/env bash
#
# Тесты оркестратора dream-team на моке opencode (без моделей, ~2 мин).
#   bash tests/run.sh            # все сценарии
#   bash tests/run.sh amend stop # выбранные
# Мок (tests/bin/opencode) играет роли по сценарию «роль статус [действие]».
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dt-tests.XXXXXX")"
CLI='bash .opencode/skills/agent-manager/dt-cli.sh'
pass=0; fail=0

# case <имя> <ожид. stage> <ожид. cycle> <сценарий через ;> [хук] [resume — после прогона ещё раз dt]
run_case(){
  local name="$1" want_stage="$2" want_cycle="$3" scen="$4" hook="${5:-}" again="${6:-}" d="${WORK}/$1"
  mkdir -p "${d}"; cd "${d}" || return
  git init -q; git commit -q --allow-empty -m init
  cp -R "${ROOT}/.opencode" .
  printf '%s' "${scen}" | tr ';' '\n' > scenario
  export DT_MOCK_SCRIPT="${d}/scenario" DT_MOCK_LOG="${d}/mock.log" PATH="${ROOT}/tests/bin:${PATH}"
  export DT_POLL_SEC=1 DT_HANG_GRACE_SEC=3
  [ -n "${hook}" ] && bash -c "${hook}" &
  ${CLI} --new "задача ${name}" > out.txt 2>&1
  wait
  if [ -n "${again}" ]; then ${CLI} > out2.txt 2>&1; fi
  . .planning/agent-pipeline/state.env
  local left; left="$(grep -c . scenario || true)"
  if [ "${STAGE}" = "${want_stage}" ] && [ "${CYCLE}" = "${want_cycle}" ] && { [ "${want_stage}" = blocked ] || [ "${left}" = 0 ]; } && [ ! -f .planning/agent-pipeline/run.lock ]; then
    pass=$((pass+1)); echo "ok   ${name}"
  else
    fail=$((fail+1)); echo "FAIL ${name}: stage=${STAGE} cycle=${CYCLE} left=${left} reason=${BLOCK_REASON:-}"; tail -5 .planning/agent-pipeline/run.log
  fi
  cd "${WORK}" || return
}

want(){ [ $# -eq 0 ] || [ -z "${SEL:-}" ] || case " ${SEL} " in *" $1 "*) return 0;; *) return 1;; esac; }
SEL="$*"
F="planner done;critic approved;planner approved;coder done;reviewer approved;tester done;debugger clean"

want happy  && run_case happy done 1 "${F}"
want iters  && run_case iters done 1 "planner done plan2;critic needs-revision;planner done plan2;critic approved;planner approved;coder done;reviewer needs-revision;coder done;reviewer approved;coder done;reviewer approved;tester done;debugger needs-revision;tester done;debugger bugs-found;coder done;reviewer approved;tester done;debugger clean"
want maxiter && DT_MAX_PAIR_ITERS=2 run_case maxiter blocked 1 "planner done;critic needs-revision;planner done;critic needs-revision;planner done"
want nudge  && run_case nudge done 1 "planner done nowrite;${F}"
want nudge2 && run_case nudge2 blocked 1 "planner done nowrite;planner done nowrite;planner done"
want hang   && run_case hang done 1 "planner done hang;critic approved;planner approved;coder done;reviewer approved;tester done;debugger clean"
want junk   && run_case junk done 1 "planner done;critic approved;planner approved;coder done junk;reviewer approved;tester done stray;debugger clean"
want amend  && run_case amend done 1 "planner done;critic needs-revision sleep20;${F}" "sleep 5; ${CLI} --add 'правка' >/dev/null 2>&1"
want issue  && run_case issue done 2 "planner done sleep6;critic approved;planner approved;coder done;reviewer approved;tester done;debugger clean;${F}" "sleep 4; ${CLI} --issue 'доп' >/dev/null 2>&1"
want stop   && run_case stop done 1 "planner done;critic approved sleep20;critic approved;planner approved;coder done;reviewer approved;tester done;debugger clean" "sleep 5; ${CLI} --stop >/dev/null 2>&1" resume

echo "── ${pass} ok, ${fail} fail (каталог: ${WORK})"
[ "${fail}" = 0 ]
