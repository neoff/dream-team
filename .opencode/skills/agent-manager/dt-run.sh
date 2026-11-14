#!/usr/bin/env bash
#
# dream-team: детерминированный оркестратор пайплайна (вместо LLM-Менеджера).
#
#   bash .opencode/skills/agent-manager/dt-run.sh      # cwd = корень проекта
#
# Крутит три антагонистичные пары по state-machine:
#   plan: planner → critic → … → planner(подпись) → code: coder → reviewer (по волнам)
#   → test: tester → debugger → clean | bugs-found(→ code) → беклог? новый цикл : done
# Каждая роль — отдельный `opencode run --agent agent-<роль>` со свежим контекстом. Роль
# получает путь входного handoff и ТОЧНЫЙ путь своего выходного handoff; оркестратор читает
# из него `## STATUS` и решает переход. Состояние пишет только оркестратор (state.env).
#
# Во время работы роли следит за:
#   amendments/pending — правка (/dt-add): роль прерывается, переплан (DT_ADD_INTERRUPT=step —
#                        дождаться конца шага);
#   stop.request       — /dt-stop: роль прерывается, состояние сохраняется (продолжить: /dt);
#   таймаут роли и «зависший» процесс (handoff записан, а процесс не выходит).
# После каждой роли её сессия экспортируется в sessions/ и удаляется из opencode — иначе
# фоновый сервис opencode «воскрешает» прерванные сессии (зомби-роли).
#
# Настройка (env): DT_MAX_PAIR_ITERS=5 DT_MAX_TEST_ROUNDS=3 DT_MAX_NUDGES=1
#   DT_TIMEOUT_<РОЛЬ>=мин (PLANNER 40, CRITIC 25, CODER 90, REVIEWER 30, TESTER 60, DEBUGGER 60)
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
SKILLS_DIR="$(dirname "${HERE}")"                 # …/skills (локально или глобально)
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
die(){ log "ОШИБКА: $*"; exit 1; }

# --- статусы ролей ---------------------------------------------------------------
allowed_statuses(){ # $1 роль $2 режим
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

read_status(){ # $1 handoff -> первое слово под «## STATUS», в нижнем регистре
  [ -f "$1" ] || return 0
  awk 'f && NF { print; exit } /^##[[:space:]]*STATUS/ { f=1 }' "$1" \
    | sed 's/[`*]//g; s/\[//g; s/\]//g' | awk '{print $1}' | sed 's/^status[=:]//' | tr 'A-Z' 'a-z'
}

in_list(){ local x; for x in $2; do [ "$x" = "$1" ] && return 0; done; return 1; }

# --- задание шага для роли ---------------------------------------------------------
mode_text(){ # $1 роль $2 режим
  case "$1:$2" in
    planner:work) echo "Построй или доработай .planning/agent-pipeline/plan-draft.md по входному handoff. На
итерации > 1 исправь КАЖДОЕ critical/major замечание из critique.md (minor — исправь или
обоснуй). Волны размечай заголовками \`### Wave X.Y: <название>\`. Approval не подписывай." ;;
    planner:sign) echo "Критик одобрил план (approval-critic.md). Перечитай plan-draft.md. Согласен — подпиши
.planning/agent-pipeline/approval-planner.md (клятва из planning-guide.md) и скопируй
plan-draft.md в .planning/agent-pipeline/plan.md; STATUS=approved. Видишь проблему — исправь
plan-draft.md и поставь STATUS=needs-revision (критик посмотрит снова)." ;;
    critic:*) echo "Оцени .planning/agent-pipeline/plan-draft.md по своим правилам. Есть critical/major или
нужные правки — запиши critique.md, STATUS=needs-revision. План безупречен — запиши
approval-critic.md, STATUS=approved." ;;
    coder:bugfix) echo "Исправь ВСЕ подтверждённые баги из .planning/agent-pipeline/bug-reports/ (см. debug-report.md):
на каждый — регресс-тест (RED) → фикс (GREEN) → прогон всех тестов → атомарный коммит.
Обнови code-summary.md. При повторе по замечаниям ревьювера — исправь всё из review-report.md." ;;
    coder:*) echo "Реализуй ТОЛЬКО волну «${WAVE_ID}» (волна ${WAVE} из ${TOTAL_WAVES}) из .planning/agent-pipeline/plan.md:
строгий TDD (RED → GREEN → REFACTOR), прогон всех тестов, атомарные коммиты. Другие волны не
трогай. Обнови code-summary.md. При повторе по замечаниям ревьювера — исправь ВСЕ пункты
review-report.md." ;;
    reviewer:*) if [ "${BUGFIX}" = 1 ]; then echo "Проверь фикс багов (bug-reports/, code-summary.md, коммиты) по своим правилам."
      else echo "Проверь код волны «${WAVE_ID}» (code-summary.md, коммиты волны) по своим правилам."; fi
      echo "Есть блокирующие замечания — review-report.md, STATUS=needs-revision. Чисто —
approval-reviewer.md, STATUS=approved." ;;
    tester:*) echo "Протестируй собранный результат по матрице из testing-guide.md (happy, boundary, invalid,
errors, security, concurrency, performance) против plan.md и task-context.md. Каждый FAIL
повтори 3×. Отчёт — .planning/agent-pipeline/test-report.md (есть FAIL) или clean-report.md (нет).
Если входной handoff от дебаггера — ответь на его вопросы/уточни repro. STATUS=done." ;;
    debugger:*) echo "Разбери test-report.md / clean-report.md: каждый FAIL воспроизведи и классифицируй
(CONFIRMED_BUG / NOT_A_BUG / FLAKY / ENVIRONMENT). Даже при отсутствии FAIL независимо проверь
ключевые сценарии плана, прежде чем подписать clean — ты второй ключ пары. Вердикт в STATUS:
clean (подтверждённых багов нет; clean-report.md), bugs-found (bug-reports/bug-NNN.md +
debug-report.md), needs-revision (нужно уточнение/перепроверка от tester — что именно, в handoff)." ;;
  esac
}

build_prompt(){ # $1 роль $2 режим $3 in $4 out $5 доп.замечание
  cat <<EOF
Ты — роль «$1» пайплайна dream-team. Тебя запустил оркестратор (dt-run.sh) вместо Менеджера:
всё, что в твоих правилах сказано про Менеджера, относится к нему. Свои правила — в
${AGENTS_DIR}/agent-$1.md и ${SKILLS_DIR}/agent-$1/ (пути .opencode/skills/… в правилах = ${SKILLS_DIR}/…).

ВХОД: handoff \`$3\` — начни с него (и его ARTIFACTS).

ЗАДАНИЕ ЭТОГО ШАГА:
$(mode_text "$1" "$2")

ВЫХОД (обязательно):
1. Свой handoff запиши РОВНО в файл \`$4\` по формату
   ${SKILLS_DIR}/agent-pipeline/handoff-protocol.md. В разделе \`## STATUS\` — ровно одно
   слово из: $(allowed_statuses "$1" "$2").
2. Все свои артефакты — только в .planning/agent-pipeline/. В корень проекта ничего не клади
   (отчёты, cover.out, coverage.out — тоже в .planning/agent-pipeline/).
3. Не добавляй .planning/ в git. Код коммитить можно и нужно (роль coder).
4. Других ролей и агентов не запускай, opencode из shell не вызывай.
5. Последняя строка ответа: \`status=<STATUS> handoff=$4\`.
$5
EOF
}

# --- сессии opencode ------------------------------------------------------------------
find_sid(){ # $1 jsonl-лог роли, $2 агент, $3 время старта (сек) -> id сессии
  local sid id g
  sid="$(grep -o '"sessionID":"[^"]*"' "$1" 2>/dev/null | head -1 | cut -d'"' -f4)"
  if [ -n "${sid}" ]; then printf '%s' "${sid}"; return 0; fi
  # поток --format json мог не успеть: ищем свежую сессию этого агента в этом каталоге
  for id in $(opencode session list 2>/dev/null | head -8 | cut -f1); do
    g="$(tmo 20 opencode api session.get --param sessionID="${id}" 2>/dev/null)"
    printf '%s' "${g}" | grep -q "\"agent\":\"$2\"" || continue
    printf '%s' "${g}" | grep -q "\"directory\":\"$(pwd)\"" || continue
    c="$(printf '%s' "${g}" | grep -oE '"created":[0-9]+' | head -1 | grep -oE '[0-9]+$')"
    [ -n "${c}" ] && [ "$((c / 1000))" -ge "$(( $3 - 5 ))" ] && { printf '%s' "${id}"; return 0; }
  done
}

session_cleanup(){ # $1 sid $2 файл экспорта $3 прерывали ли (1/0)
  [ -n "$1" ] || { log "  ! id сессии не найден — проверь opencode session list"; return 0; }
  if [ "$3" = 1 ]; then tmo 20 opencode api session.interrupt --param sessionID="$1" --param resume=false >/dev/null 2>&1 || true; fi
  tmo 90 opencode session export "$1" > "$2" 2>/dev/null || rm -f "$2"
  if [ "${KEEP_SESSIONS}" != 1 ]; then
    tmo 30 opencode session delete "$1" >/dev/null 2>&1 || log "  ! не удалось удалить сессию $1"
  fi
  rm -f "${P}/current-session"
}

kill_tree(){ # $1 pid лидера группы
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null
  local i; for i in 1 2 3 4 5; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
  kill -KILL -- "-$1" 2>/dev/null || kill -KILL "$1" 2>/dev/null
}

# Запустить роль. Ставит RR_RESULT (ok|amend|stopped|timeout|hung|crashed), RR_SID.
run_role(){ # $1 роль $2 in $3 out $4 prompt
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
  log "  ← ${role}: ${result} за $(( ($(date +%s) - start) / 60 )) мин (сессия ${sid:-?})"
}

# --- гигиена репозитория ---------------------------------------------------------------
# Мусор ролей: всё неотслеживаемое (и не в .gitignore), что появилось за время роли и не было
# закоммичено, уезжает в stray/step-NN/ с сохранением путей. Исходники кодер обязан коммитить.
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
  [ -n "${moved}" ] && log "  ! роль оставила незакоммиченные файлы —${moved} → ${P}/stray/step-$(nn "${STEP}")/"
  if [ -n "$(git ls-files "${P}" 2>/dev/null | head -1)" ]; then
    log "  ! в git попали файлы ${P}/ (роль закоммитила .planning) — проверь историю"
  fi
  return 0
}

ensure_git_exclude(){
  local ex
  ex="$(git rev-parse --git-path info/exclude 2>/dev/null)" || return 0
  mkdir -p "$(dirname "${ex}")"; touch "${ex}"
  grep -qx '.planning/' "${ex}" || printf '.planning/\n' >> "${ex}"
}

# --- переходы state-machine --------------------------------------------------------------
block(){ STAGE=blocked; BLOCK_REASON="$1"; history_add blocked "\"reason\": $(json_str "$1")"; state_save; log "⛔ blocked: $1"; }

next_iter(){ # следующая итерация пары; false = превышен лимит (уже blocked)
  ITER=$((ITER + 1))
  if [ "${ITER}" -gt "${MAX_ITERS}" ]; then block "пара ${PAIR} не сошлась за ${MAX_ITERS} итераций"; return 1; fi
  return 0
}

wave_ids(){ grep -E '^#{2,4}[[:space:]]*Wave[[:space:]]' "${P}/plan.md" 2>/dev/null | sed -E 's/^#+[[:space:]]*Wave[[:space:]]+//' ; }

start_wave(){ # WAVE уже выставлен
  local ho id
  id="$(wave_ids | sed -n "${WAVE}p")"
  WAVE_ID="Wave ${id:-${WAVE}}"; [ "${TOTAL_WAVES}" = 1 ] && [ -z "${id}" ] && WAVE_ID="весь план"
  STAGE=coding; PAIR=code; ITER=1; BUGFIX=0
  STEP=$((STEP + 1)); ho="${P}/handoffs/step-$(nn "${STEP}")-manager.md"
  write_handoff "${ho}" coder "План подписан обеими сторонами. Старт волны ${WAVE} из ${TOTAL_WAVES}: ${WAVE_ID}." \
    "- \`${P}/plan.md\` — утверждённый план (реализуй только ${WAVE_ID})
- \`${P}/task-context.md\` — задача
$( [ -f "${P}/code-summary.md" ] && echo "- \`${P}/code-summary.md\` — что уже сделано")" \
    "- Реализуй ${WAVE_ID} строго по плану и TDD; по завершении — code-summary.md и handoff ревьюверу."
  NEXT_ROLE=coder; NEXT_MODE=work; IN_HANDOFF="${ho}"
  history_add wave-start "\"wave\": ${WAVE}, \"wave_id\": $(json_str "${WAVE_ID}")"
}

start_coding(){
  [ -f "${P}/plan.md" ] || { cp "${P}/plan-draft.md" "${P}/plan.md" 2>/dev/null && log "  plan.md не создан planner'ом — скопировал из plan-draft.md"; }
  [ -f "${P}/plan.md" ] || { block "нет plan.md после подписи плана"; return; }
  [ -f "${P}/approval-planner.md" ] || log "  ! planner подтвердил план без approval-planner.md"
  TOTAL_WAVES="$(wave_ids | grep -c . || true)"; [ "${TOTAL_WAVES}" -gt 0 ] 2>/dev/null || TOTAL_WAVES=1
  WAVE=1; start_wave
}

archive_wave_approval(){ # консенсус ревьювера закрыт — убрать подпись, чтобы следующая волна шла с чистого
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
  write_handoff "${ho}" tester "Код всех волн одобрен ревьювером. Старт тестирования (раунд $((TEST_ROUND + 1)))." \
    "- \`${P}/plan.md\` — план (как запускать, критерии приёмки)
- \`${P}/task-context.md\` — задача
- \`${P}/code-summary.md\` — что реализовано" \
    "- Попробуй сломать результат: матрица тест-кейсов из testing-guide.md; отчёт дебаггеру."
  NEXT_ROLE=tester; NEXT_MODE=work; IN_HANDOFF="${ho}"
  history_add test-start "\"round\": $((TEST_ROUND + 1))"
}

start_bugfix(){ # $1 handoff дебаггера
  TEST_ROUND=$((TEST_ROUND + 1))
  if [ "${TEST_ROUND}" -ge "${MAX_TEST_ROUNDS}" ]; then block "баги остаются после ${MAX_TEST_ROUNDS} раундов тестирования"; return; fi
  STAGE=coding; PAIR=code; ITER=1; BUGFIX=1; WAVE_ID="фикс багов (раунд ${TEST_ROUND})"
  NEXT_ROLE=coder; NEXT_MODE=bugfix; IN_HANDOFF="$1"
  history_add bugfix-start "\"round\": ${TEST_ROUND}"
}

transition(){ # $1 роль $2 статус $3 out
  local role="$1" st="$2" out="$3"
  LAST_HANDOFF="${out}"; LAST_STATUS="${st}"
  history_add "${role}:${st}" "\"handoff\": $(json_str "${out}")"
  if [ "${st}" = blocked ]; then block "роль ${role} вернула blocked (см. ${out})"; return; fi
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
      if do_cycle; then log "✓ цикл $((CYCLE - 1)) чист; в беклоге дополнения → цикл ${CYCLE}"
      else do_finalize; log "✓ DONE. Артефакты → ${DT_FINALIZED}"; fi ;;
    *) block "неожиданный статус «${st}» от ${role} (${NEXT_MODE})" ;;
  esac
  state_save
}

# Один шаг: запустить NEXT_ROLE, прочитать статус, перейти.
step_once(){
  local role="${NEXT_ROLE}" mode="${NEXT_MODE:-work}" in="${IN_HANDOFF}" out st note="" attempt=0 allowed
  allowed="$(allowed_statuses "${role}" "${mode}")"
  [ -n "${allowed}" ] || { block "неизвестная роль/режим: ${role}/${mode}"; return; }
  while :; do
    STEP=$((STEP + 1)); out="${P}/handoffs/step-$(nn "${STEP}")-${role}.md"
    state_save
    log "→ шаг $(nn "${STEP}") ${role}${mode:+ [${mode}]} · пара ${PAIR} итер ${ITER}$( [ "${STAGE}" = coding ] && echo " · ${WAVE_ID}") · вход $(basename "${in}")"
    hygiene_before
    run_role "${role}" "${in}" "${out}" "$(build_prompt "${role}" "${mode}" "${in}" "${out}" "${note}")"
    repo_hygiene
    case "${RR_RESULT}" in
      stopped) log "■ остановлено по /dt-stop; продолжить: /dt"; history_add stopped "\"role\": \"${role}\""; state_save; return 2 ;;
      amend)   log "✎ правка во время ${role} — прерываю и перепланирую"; do_replan; return 0 ;;
    esac
    st="$(read_status "${out}")"
    if in_list "${st}" "${allowed}"; then
      log "  STATUS=${st}"
      transition "${role}" "${st}" "${out}"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "${attempt}" -gt "${MAX_NUDGES}" ]; then
      block "роль ${role} не дала корректный handoff (${RR_RESULT}, STATUS=«${st:-нет}», ожидал: ${allowed})"
      return 0
    fi
    log "  ! некорректный результат (${RR_RESULT}, STATUS=«${st:-нет}») — повтор ${attempt}/${MAX_NUDGES}"
    note="ВНИМАНИЕ: предыдущий запуск этого шага не записал корректный handoff (результат: ${RR_RESULT},
STATUS «${st:-нет}»). Доделай работу шага и обязательно запиши handoff в указанный файл."
  done
}

cleanup(){ rm -f "${P}/stop.request" "${P}/current-role" "${P}/current-session"; lock_release; }

# Прошлый оркестратор убит жёстко (kill -9, перезагрузка) — его роль могла остаться сиротой
# и продолжать писать в пайплайн. Добить её и её сессию до старта.
reap_orphan(){
  [ -f "${P}/current-role" ] || return 0
  local pid sid
  pid="$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "${P}/current-role")"
  sid="$(cat "${P}/current-session" 2>/dev/null || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null && ps -p "${pid}" -o command= | grep -q 'opencode'; then
    log "  ! найдена роль-сирота прошлого запуска (pid ${pid}) — останавливаю"
    kill_tree "${pid}"
  fi
  if [ -n "${sid}" ]; then session_cleanup "${sid}" "${P}/sessions/orphan-${sid}.session.json" 1; fi
  rm -f "${P}/current-role" "${P}/current-session"
}

main(){
  state_exists || die "нет пайплайна (${P}): сначала dt --new <задача>"
  if lock_alive; then die "оркестратор уже работает (pid $(lock_pid))"; fi
  ensure_dirs
  lock_take
  trap cleanup EXIT
  trap 'STOP=1' INT TERM
  rm -f "${P}/stop.request"
  reap_orphan
  ensure_git_exclude
  state_load || die "не прочитать состояние"
  [ -n "${IN_HANDOFF}" ] || IN_HANDOFF="$(ls -t "${P}"/handoffs/*.md 2>/dev/null | head -1)"
  log "══ старт оркестратора (pid $$): stage=${STAGE} cycle=${CYCLE} step=${STEP} next=${NEXT_ROLE:-—}"

  if has_pending "${P}/amendments/pending"; then log "✎ есть правки — перепланирование"; do_replan; fi
  if [ "${STAGE}" = done ]; then
    if do_cycle; then log "беклог → цикл ${CYCLE}"; else log "всё сделано, беклог пуст"; return 0; fi
  fi
  if [ "${STAGE}" = blocked ]; then log "pipeline blocked: ${BLOCK_REASON}"; return 1; fi
  state_save

  while :; do
    case "${STAGE}" in
      planning|coding|testing) ;;
      done)    log "══ DONE (цикл ${CYCLE}). Итог: ${DT_FINALIZED:-${P}/archive}"; return 0 ;;
      blocked) log "══ BLOCKED: ${BLOCK_REASON}. Поправь задачу (/dt-add) и /dt"; return 1 ;;
      *)       die "неизвестная стадия ${STAGE}" ;;
    esac
    step_once; [ $? = 2 ] && return 0
    if [ "${ADD_INTERRUPT}" = step ] && has_pending "${P}/amendments/pending"; then
      log "✎ правка — перепланирование"; do_replan
    fi
  done
}

main "$@"
