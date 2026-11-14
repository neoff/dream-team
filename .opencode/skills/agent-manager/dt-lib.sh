#!/usr/bin/env bash
#
# dream-team: общая детерминированная часть (подключается из dt.sh и dt-run.sh).
# cwd = корень проекта. Совместимо с bash 3.2 (macOS): без ассоциативных массивов.
#
# Состояние:
#   .planning/agent-pipeline/state.env           — канон (KEY=value, читает/пишет только скрипт)
#   .planning/agent-pipeline/pipeline-state.json — генерируется из state.env (для людей/ролей)
#   .planning/agent-pipeline/history.jsonl       — журнал переходов (строка = событие)
#   .planning/agent-pipeline/run.lock            — pid живого оркестратора
#

P=.planning/agent-pipeline

# --- state -------------------------------------------------------------------
STATE_KEYS="TASK_ID CREATED STAGE STEP CYCLE PAIR ITER WAVE TOTAL_WAVES WAVE_ID BUGFIX TEST_ROUND NEXT_ROLE NEXT_MODE IN_HANDOFF LAST_HANDOFF LAST_STATUS BLOCK_REASON"

state_defaults(){
  TASK_ID="$(date +%Y%m%d-%H%M%S)"; CREATED="$(now_iso)"; STAGE=planning; STEP=0; CYCLE=1
  PAIR=plan; ITER=1; WAVE=0; TOTAL_WAVES=0; WAVE_ID=""; BUGFIX=0; TEST_ROUND=0
  NEXT_ROLE=planner; NEXT_MODE=work; IN_HANDOFF=""; LAST_HANDOFF=""; LAST_STATUS=""; BLOCK_REASON=""
}

now_iso(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

# timeout есть не везде (чистый macOS) — тогда просто выполнить
tmo(){ local s="$1"; shift; if command -v timeout >/dev/null 2>&1; then timeout "${s}" "$@"; else "$@"; fi; }

json_str(){ # экранирование строки для JSON
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"
  printf '"%s"' "${s}"
}

state_exists(){ [ -f "${P}/state.env" ] || [ -f "${P}/pipeline-state.json" ]; }

# Прочитать state.env; для старых прогонов (только JSON) — восстановить что можно.
state_load(){
  state_defaults
  if [ -f "${P}/state.env" ]; then
    # shellcheck disable=SC1091
    . "${P}/state.env"
    return 0
  fi
  [ -f "${P}/pipeline-state.json" ] || return 1
  local j="${P}/pipeline-state.json" v
  v="$(grep -oE '"task_id": *"[^"]*"' "${j}" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"; [ -n "${v}" ] && TASK_ID="${v}"
  v="$(grep -oE '"stage": *"[a-z]*"' "${j}" | head -1 | sed 's/.*"\([a-z]*\)"$/\1/')"; [ -n "${v}" ] && STAGE="${v}"
  v="$(grep -oE '"step": *[0-9]+' "${j}" | head -1 | grep -oE '[0-9]+$')"; [ -n "${v}" ] && STEP="${v}"
  v="$(grep -oE '"cycle": *[0-9]+' "${j}" | head -1 | grep -oE '[0-9]+$')"; [ -n "${v}" ] && CYCLE="${v}"
  v="$(grep -oE '"last_handoff": *"[^"]*"' "${j}" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"; [ -n "${v}" ] && { IN_HANDOFF="${v}"; LAST_HANDOFF="${v}"; }
  case "${STAGE}" in
    planning|plan) STAGE=planning; PAIR=plan; NEXT_ROLE=planner ;;
    coding|code)   STAGE=coding;   PAIR=code; NEXT_ROLE=coder; WAVE=1 ;;
    testing|test)  STAGE=testing;  PAIR=test; NEXT_ROLE=tester ;;
  esac
  return 0
}

state_save(){
  local k v tmp="${P}/state.env.tmp"
  mkdir -p "${P}"
  : > "${tmp}"
  for k in ${STATE_KEYS}; do
    eval "v=\${${k}-}"
    printf '%s=%q\n' "${k}" "${v}" >> "${tmp}"
  done
  mv "${tmp}" "${P}/state.env"
  state_json
}

history_add(){ # $1 action, $2 доп. поля JSON без фигурных скобок (опц.)
  local extra="${2:-}"
  [ -n "${extra}" ] && extra=", ${extra}"
  printf '{"timestamp": "%s", "step": %s, "cycle": %s, "stage": "%s", "action": "%s"%s}\n' \
    "$(now_iso)" "${STEP:-0}" "${CYCLE:-1}" "${STAGE:-}" "$1" "${extra}" >> "${P}/history.jsonl"
}

list_json(){ # $1 каталог -> JSON-массив путей файлов
  local out="" f
  for f in "$1"/*.md; do [ -e "${f}" ] || continue; out="${out}${out:+, }$(json_str "${f}")"; done
  printf '[%s]' "${out}"
}

state_json(){
  local hist
  hist="$( [ -f "${P}/history.jsonl" ] && sed 's/^/    /; $!s/$/,/' "${P}/history.jsonl" )"
  cat > "${P}/pipeline-state.json.tmp" <<EOF
{
  "version": "3.0",
  "generated_by": "dt-lib.sh (канон — state.env; руками не править)",
  "task_id": $(json_str "${TASK_ID}"),
  "created_at": $(json_str "${CREATED}"),
  "updated_at": $(json_str "$(now_iso)"),
  "stage": $(json_str "${STAGE}"),
  "step": ${STEP:-0},
  "cycle": ${CYCLE:-1},
  "current_pair": $(json_str "${PAIR}"),
  "pair_iteration": ${ITER:-1},
  "current_wave": ${WAVE:-0},
  "total_waves": ${TOTAL_WAVES:-0},
  "wave_id": $(json_str "${WAVE_ID}"),
  "bugfix": ${BUGFIX:-0},
  "test_round": ${TEST_ROUND:-0},
  "next_role": $(json_str "${NEXT_ROLE}"),
  "next_mode": $(json_str "${NEXT_MODE}"),
  "in_handoff": $(json_str "${IN_HANDOFF}"),
  "last_handoff": $(json_str "${LAST_HANDOFF}"),
  "last_status": $(json_str "${LAST_STATUS}"),
  "block_reason": $(json_str "${BLOCK_REASON}"),
  "amendments_applied": $(list_json "${P}/amendments/applied"),
  "backlog_taken": $(list_json "${P}/backlog/taken"),
  "history": [
${hist}
  ]
}
EOF
  mv "${P}/pipeline-state.json.tmp" "${P}/pipeline-state.json"
}

# --- lock (pid оркестратора) --------------------------------------------------
lock_pid(){ [ -f "${P}/run.lock" ] && sed -n 's/^pid=//p' "${P}/run.lock" | head -1; }
lock_alive(){ # 0 = жив оркестратор, держащий lock
  local pid; pid="$(lock_pid)"
  [ -n "${pid}" ] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  ps -p "${pid}" -o command= 2>/dev/null | grep -q 'dt-run.sh'
}
lock_take(){ printf 'pid=%s\nstarted=%s\n' "$$" "$(now_iso)" > "${P}/run.lock"; }
lock_release(){ [ "$(lock_pid)" = "$$" ] && rm -f "${P}/run.lock"; return 0; }

# --- файлы ----------------------------------------------------------------------
mtime(){ stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

pending_files(){ # $1 каталог -> файлы *.md в порядке поступления
  [ -d "$1" ] && find "$1" -maxdepth 1 -type f -name '*.md' | sed 's/\.md$//' | LC_ALL=C sort | sed 's/$/.md/' || true
}
has_pending(){ [ -n "$(pending_files "$1")" ]; }

user_text(){ awk 'f{print} /^## Текст пользователя/{f=1}' "$1"; }

ensure_dirs(){
  mkdir -p "${P}/handoffs" "${P}/bug-reports" "${P}/archive" "${P}/amendments/pending" \
           "${P}/amendments/applied" "${P}/backlog/pending" "${P}/backlog/taken" "${P}/sessions"
}

PASS_ARTIFACTS="plan-draft.md plan.md critique.md approval-planner.md approval-critic.md approval-reviewer.md review-report.md test-report.md debug-report.md clean-report.md"

move_artifacts(){ # $1 каталог архива: артефакты прохода (планы, подписи, отчёты, баги)
  local dst="$1" f
  mkdir -p "${dst}"
  for f in ${PASS_ARTIFACTS}; do
    if [ -f "${P}/${f}" ]; then mv "${P}/${f}" "${dst}/${f}"; fi
  done
  if [ -d "${P}/bug-reports" ] && [ -n "$(ls -A "${P}/bug-reports" 2>/dev/null)" ]; then
    mkdir -p "${dst}/bug-reports"; mv "${P}/bug-reports/"* "${dst}/bug-reports/"
  fi
  return 0
}

archive_cycle(){ # $1 каталог: всё по циклу; task-context.md — копией (нужен дальше)
  local arch="$1" f
  move_artifacts "${arch}"
  for f in code-summary.md; do
    if [ -f "${P}/${f}" ]; then mv "${P}/${f}" "${arch}/${f}"; fi
  done
  cp "${P}/task-context.md" "${arch}/task-context.md" 2>/dev/null || true
  if [ -n "$(ls -A "${P}/handoffs" 2>/dev/null)" ]; then
    mkdir -p "${arch}/handoffs"; mv "${P}/handoffs/"* "${arch}/handoffs/"
  fi
  return 0
}

latest_archive(){
  local f; f="$(ls -t "${P}"/archive/*/task-context.md 2>/dev/null | head -1)"
  if [ -n "${f}" ]; then dirname "${f}"; fi
}

nn(){ printf '%02d' "$1"; }

# Handoff от «менеджера» (оркестратора) следующей роли.
# $1 путь, $2 кому, $3 DONE (строка), $4 ARTIFACTS (строки «- `путь` — что»), $5 FOR NEXT AGENT
write_handoff(){
  cat > "$1" <<EOF
# Handoff: manager → $2 (pair: ${PAIR}, iter ${ITER})

## STATUS

done

## DONE

- $3

## ARTIFACTS (читать ТОЛЬКО это, больше ничего не нужно)

$4

## FOR NEXT AGENT

$5

## OPEN / RISKS

- Нет.

## CONTEXT RESET

Этот handoff + перечисленные ARTIFACTS = ВСЁ, что нужно. Предыдущий диалог не требуется
и недоступен. Поднимайся с чистого контекста.
EOF
}

# --- переходы, общие для dt.sh и dt-run.sh -----------------------------------------

# new: старое → архив, каркас, task-context (задача дословно из файла $1), state, handoff.
do_new(){ # $1 файл с текстом задачи
  local src="$1" ts dst f ho
  ts="$(date +%Y%m%d-%H%M%S)"
  if state_exists; then
    state_load || true
    dst="${P}/archive/task-$(printf '%s' "${TASK_ID:-old}" | tr -c 'A-Za-z0-9._-' '_')-${ts}"
    mkdir -p "${dst}"
    for f in "${P}"/* "${P}"/.[!.]*; do
      [ -e "${f}" ] || continue
      case "$(basename "${f}")" in archive) continue ;; esac
      [ "${f}" = "${src}" ] && continue
      mv "${f}" "${dst}/"
    done
    DT_ARCHIVED="${dst}"
  fi
  ensure_dirs
  { printf '# Task Context\n\n## Задача (дословно)\n'; cat "${src}"; printf '\n'; } > "${P}/task-context.md"
  rm -f "${src}"
  : > "${P}/history.jsonl"
  state_defaults
  TASK_ID="${ts}"
  ho="${P}/handoffs/step-00-manager.md"
  write_handoff "${ho}" planner "Новая задача принята (/dt-new)." \
    "- \`${P}/task-context.md\` — задача дословно" \
    "- Построй plan-draft.md по задаче из task-context.md (фазы → волны → атомарные задачи,
  у каждой RED-тест, файлы, критерии приёмки). Волны размечай заголовками \`### Wave X.Y: …\`."
  IN_HANDOFF="${ho}"; LAST_HANDOFF="${ho}"
  history_add created
  state_save
}

# replan: правки из amendments/pending → task-context, архив прохода, planning. 0 = было что применять.
do_replan(){
  local files arch ho prev_plan summary f
  files="$(pending_files "${P}/amendments/pending")"
  [ -n "${files}" ] || return 1
  STEP=$((STEP + 1))
  arch="${P}/archive/replan-step-$(nn "${STEP}")"
  move_artifacts "${arch}"
  mkdir -p "${P}/amendments/applied" "${P}/handoffs"
  { printf '\n## Правки (/dt-add) — шаг %s\n' "$(nn "${STEP}")"
    while IFS= read -r f; do printf '\n### %s\n' "$(basename "${f}")"; user_text "${f}"; done <<<"${files}"
  } >> "${P}/task-context.md"
  while IFS= read -r f; do mv "${f}" "${P}/amendments/applied/"; done <<<"${files}"
  STAGE=planning; PAIR=plan; ITER=1; WAVE=0; TOTAL_WAVES=0; WAVE_ID=""; BUGFIX=0; TEST_ROUND=0
  ho="${P}/handoffs/step-$(nn "${STEP}")-manager.md"
  prev_plan=""; [ -f "${arch}/plan.md" ] && prev_plan="- \`${arch}/plan.md\` — прежний план (до правок), для сравнения"
  summary=""; [ -f "${P}/code-summary.md" ] && summary="- \`${P}/code-summary.md\` — что уже реализовано (плюс \`git log\`)"
  write_handoff "${ho}" planner "Пришли правки пользователя (/dt-add); текущая стадия прервана, артефакты прохода → \`${arch}/\`." \
    "- \`${P}/task-context.md\` — задача + раздел «Правки (/dt-add) — шаг $(nn "${STEP}")» (дословно)
${prev_plan}
${summary}" \
    "- ПЕРЕПЛАН. Задача изменилась: см. раздел «Правки» в task-context.md. Часть уже может быть
  реализована (code-summary.md, \`git log\`). Построй plan-draft.md, который доводит
  СУЩЕСТВУЮЩИЙ код до задачи с правками: что оставить, что переделать, что добавить. Не
  переписывай готовое без причины. Правки важнее исходного текста там, где противоречат."
  NEXT_ROLE=planner; NEXT_MODE=work; IN_HANDOFF="${ho}"; LAST_HANDOFF="${ho}"; BLOCK_REASON=""
  history_add replan '"reason": "amendment"'
  state_save
  return 0
}

# cycle: беклог → новый цикл. 0 = цикл начат, 1 = беклог пуст.
do_cycle(){
  local files arch ho f arts
  files="$(pending_files "${P}/backlog/pending")"
  [ -n "${files}" ] || return 1
  if [ -f "${P}/plan.md" ] || [ -f "${P}/code-summary.md" ] || [ -f "${P}/clean-report.md" ]; then
    arch="${P}/archive/cycle-${CYCLE}"; [ -e "${arch}" ] && arch="${arch}-$(date +%Y%m%d-%H%M%S)"
    archive_cycle "${arch}"
  else
    arch="$(latest_archive)"
  fi
  if [ ! -f "${P}/task-context.md" ] && [ -n "${arch}" ] && [ -f "${arch}/task-context.md" ]; then
    cp "${arch}/task-context.md" "${P}/task-context.md"
  fi
  arts=""
  for f in plan.md code-summary.md clean-report.md; do
    if [ -n "${arch}" ] && [ -f "${arch}/${f}" ]; then arts="${arts}- \`${arch}/${f}\` — ${f} цикла ${CYCLE}"$'\n'; fi
  done
  [ -n "${arts}" ] || arts="- (артефактов цикла ${CYCLE} не найдено — смотри код и \`git log\`)"
  CYCLE=$((CYCLE + 1)); STEP=$((STEP + 1))
  mkdir -p "${P}/backlog/taken" "${P}/handoffs"
  { printf '\n## Цикл %s — дополнения (/dt-issue)\n' "${CYCLE}"
    while IFS= read -r f; do printf '\n### %s\n' "$(basename "${f}")"; user_text "${f}"; done <<<"${files}"
  } >> "${P}/task-context.md"
  while IFS= read -r f; do printf '\ncycle: %s\n' "${CYCLE}" >> "${f}"; mv "${f}" "${P}/backlog/taken/"; done <<<"${files}"
  STAGE=planning; PAIR=plan; ITER=1; WAVE=0; TOTAL_WAVES=0; WAVE_ID=""; BUGFIX=0; TEST_ROUND=0
  ho="${P}/handoffs/step-$(nn "${STEP}")-manager.md"
  write_handoff "${ho}" planner "Цикл $((CYCLE - 1)) завершён (clean). В беклоге были дополнения → начат цикл ${CYCLE}." \
    "- \`${P}/task-context.md\` — задача + раздел «Цикл ${CYCLE} — дополнения (/dt-issue)» (дословно)
${arts}" \
    "- ИНКРЕМЕНТ. Цикл $((CYCLE - 1)) сделан и проверен (clean). Спланируй ТОЛЬКО дополнения цикла
  ${CYCLE} поверх готового кода; регрессии прошлого цикла должны остаться зелёными."
  NEXT_ROLE=planner; NEXT_MODE=work; IN_HANDOFF="${ho}"; LAST_HANDOFF="${ho}"; BLOCK_REASON=""
  history_add new-cycle
  state_save
  return 0
}

do_finalize(){
  local arch="${P}/archive/cycle-${CYCLE}"
  [ -e "${arch}" ] && arch="${arch}-$(date +%Y%m%d-%H%M%S)"
  archive_cycle "${arch}"
  STAGE=done; PAIR=""; NEXT_ROLE=""; NEXT_MODE=""; IN_HANDOFF=""
  history_add finalized "\"archive\": $(json_str "${arch}")"
  state_save
  DT_FINALIZED="${arch}"
}
