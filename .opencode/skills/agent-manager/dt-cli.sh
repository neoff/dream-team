#!/usr/bin/env bash
#
# dream-team: единый вход (терминал и слэш-команды). cwd = корень проекта.
#
#   dt                         продолжить; нет пайплайна — нужна задача
#   dt --new <задача>          новая задача (--force — поверх незаконченной)
#   dt --new @prompt.md        задача из файла (для огромных промптов)
#   dt --add <правка>          правка: живой прогон прервёт роль и перепланирует
#   dt --issue <дополнение>    в беклог: новый цикл после done
#   dt --status                где пайплайн, кто работает, сколько идёт
#   dt --log [N] | --log -f    журнал оркестратора
#   dt --stop                  остановить (состояние сохраняется; продолжить: dt)
#   dt --bg …                  запустить оркестратор в фоне (так делают слэш-команды)
#
# Удобно: alias dt='bash .opencode/skills/agent-manager/dt-cli.sh'
# `--stdin` — сообщение читается из stdin (так зовут слэш-команды: текст как есть, через heredoc).
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
  if ! state_exists; then echo "пайплайна нет (${P}). Начать: dt --new <задача>"; return 0; fi
  state_load
  local role="" started="" sid="" el=""
  if lock_alive; then
    echo "оркестратор: работает (pid $(lock_pid))"
    if [ -f "${P}/current-role" ]; then
      role="$(sed -n 's/.*role=\([^ ]*\).*/\1/p' "${P}/current-role")"
      started="$(sed -n 's/.*started=\([^ ]*\).*/\1/p' "${P}/current-role")"
      sid="$(cat "${P}/current-session" 2>/dev/null || true)"
      el="$(( ( $(date +%s) - $(mtime "${P}/current-role") ) / 60 ))"
      echo "сейчас:      ${role} · ${el} мин · сессия ${sid:-(ещё нет id)}"
    fi
  else
    echo "оркестратор: не запущен"
  fi
  echo "стадия:      ${STAGE} · цикл ${CYCLE} · шаг ${STEP} · пара ${PAIR:-—} итер ${ITER}"
  [ "${STAGE}" = coding ] && echo "волна:       ${WAVE}/${TOTAL_WAVES} ${WAVE_ID}"
  [ -n "${NEXT_ROLE}" ] && echo "следующий:   ${NEXT_ROLE} [${NEXT_MODE}] ← $(basename "${IN_HANDOFF:-—}")"
  [ -n "${BLOCK_REASON}" ] && echo "blocked:     ${BLOCK_REASON}"
  echo "очередь:     правок $(pending_files "${P}/amendments/pending" | grep -c . || true), беклог $(pending_files "${P}/backlog/pending" | grep -c . || true)"
  if [ -f "${P}/run.log" ]; then echo "── журнал ──"; tail -n 8 "${P}/run.log"; fi
}

stop(){
  if ! lock_alive; then echo "оркестратор не запущен"; return 0; fi
  local pid; pid="$(lock_pid)"
  touch "${P}/stop.request"
  echo "останавливаю (pid ${pid}): текущая роль будет прервана, состояние сохранится…"
  local i; for i in $(seq 1 40); do kill -0 "${pid}" 2>/dev/null || { echo "остановлено. Продолжить: dt"; return 0; }; sleep 1; done
  echo "не остановился за 40 с — посылаю TERM"; kill -TERM "${pid}" 2>/dev/null
}

case "${1:-}" in
  --status|status) status; exit 0 ;;
  --stop|stop)     stop; exit 0 ;;
  --log|log)
    shift
    [ -f "${P}/run.log" ] || { echo "журнала нет"; exit 0; }
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
    echo "оркестратор запущен в фоне (pid ${pid}). Следить: /dt-status (dt --status), журнал: dt --log -f"
  else
    echo "оркестратор не стартовал — см. ${P}/run.out:"; tail -n 5 "${P}/run.out"
  fi
  exit 0
fi
exec bash "${HERE}/dt-run.sh"
