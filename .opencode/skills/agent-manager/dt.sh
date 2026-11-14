#!/usr/bin/env bash
#
# dream-team: разбор входа /dt (детерминированно, без LLM).
#
#   printf '%s' "<сообщение>" | bash dt.sh
#
# Сообщение — как от слэш-команды (`<dt mode="add">текст</dt>`) или голый текст
# (`/dt-add текст`, `/dt --add текст`, `--add текст`, `resume`, `задача`…).
# Текст можно взять из файла: `--new-file путь`, или `@путь` вместо текста (для огромных промптов).
#
# Печатает директиву:
#   ACTION=stop   + MSG=…   — сказать пользователю и ничего не запускать
#   ACTION=run    [+ MSG=…] — запустить/продолжить оркестратор (dt-run.sh)
# Для new/issue/add всю подготовку (архив, task-context, intake) делает сам.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=dt-lib.sh
. "${HERE}/dt-lib.sh"

raw="$(cat)"

mode=auto
text="${raw}"
if [[ "${raw}" =~ ^[[:space:]]*\<dt[[:space:]]+mode=\"([a-z]+)\"\>(.*)\</dt\>(.*)$ ]]; then
  mode="${BASH_REMATCH[1]}"
  text="${BASH_REMATCH[2]}"
fi

trim(){ local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "${s}"; }
drop_first(){ # $1 текст, $2 первый токен -> остаток
  if [ "$2" = "$1" ]; then printf ''; else trim "${1#"$2"}"; fi
}
text="$(trim "${text}")"

# текстом можно прислать саму слэш-команду: «/dt --add …», «/dt-add …», «dt --add …»
first="${text%%[[:space:]]*}"
case "${first}" in
  /dt|dt|/dt-*)
    case "${first}" in
      /dt-new|/dt-resume|/dt-issue|/dt-add) [ "${mode}" = auto ] && mode="${first#/dt-}" ;;
    esac
    text="$(drop_first "${text}" "${first}")"
    ;;
esac
first="${text%%[[:space:]]*}"
case "${first}" in
  --resume|resume|--new|--issue|--add)
    [ "${mode}" = auto ] && mode="${first#--}"
    text="$(drop_first "${text}" "${first}")"
    ;;
  --new-file)
    mode=new; text="@$(drop_first "${text}" "${first}")"
    ;;
esac
force=0
if [ "${mode}" = new ]; then
  first="${text%%[[:space:]]*}"
  if [ "${first}" = --force ]; then force=1; text="$(drop_first "${text}" "${first}")"; fi
  first="${text%%[[:space:]]*}"
  if [ "${first}" = --new-file ]; then text="@$(drop_first "${text}" "${first}")"; fi
fi

say(){ printf 'ACTION=%s\n' "$1"; shift; [ $# -gt 0 ] && printf 'MSG=%s\n' "$*"; return 0; }

# @путь → содержимое файла (путь без пробелов-хвостов; относительный — от cwd)
if [ "${text#@}" != "${text}" ]; then
  src="$(trim "${text#@}")"
  src="${src/#\~/${HOME}}"
  [ -f "${src}" ] || { say stop "файл не найден: ${src}"; exit 0; }
  text="$(cat "${src}")"
  [ -n "$(trim "${text}")" ] || { say stop "файл пуст: ${src}"; exit 0; }
fi

# --- probe ---
state=no; stage=none
if state_exists; then state=yes; state_load || true; stage="${STAGE}"; fi
live=0; lock_alive && live=1

intake(){ # $1 kind(add|issue) $2 dir(amendments|backlog) -> путь
  local ts d f n=1
  ts="$(date +%Y%m%d-%H%M%S)"; d="${P}/$2/pending"; mkdir -p "${d}"
  f="${d}/$1-${ts}.md"
  while [ -e "${f}" ]; do f="${d}/$1-${ts}-${n}.md"; n=$((n+1)); done
  { printf '# %s\nsource: /dt-%s\nstage_at_receive: %s\n\n## Текст пользователя (дословно)\n' "$1" "$1" "${stage}"
    printf '%s\n' "${text}"; } > "${f}"
  printf '%s' "${f}"
}

if [ "${mode}" = auto ]; then
  if [ -z "${text}" ]; then
    if [ "${state}" = yes ]; then mode=resume
    else say stop "нет пайплайна и нет задачи: /dt-new <задача> (или /dt-new @файл)"; exit 0; fi
  elif [ "${state}" = no ]; then mode=new
  else
    say stop "пайплайн уже есть (stage=${stage}). Это правка (/dt-add), дополнение в беклог (/dt-issue) или новая задача (/dt-new --force)? Ничего не делаю."
    exit 0
  fi
fi
if [ "${mode}" = resume ] && [ "${state}" = no ]; then
  [ -n "${text}" ] || { say stop "нет пайплайна: /dt-new <задача>"; exit 0; }
  mode=new
fi

case "${mode}" in
  issue)
    [ -n "${text}" ] || { say stop "пустое дополнение: /dt-issue <текст>"; exit 0; }
    f="$(intake issue backlog)"
    if [ "${state}" = no ]; then say stop "записано в беклог (${f}); пайплайна ещё нет — /dt-new <задача>"
    elif [ "${live}" = 1 ]; then say stop "записано в беклог (${f}); возьмётся следующим циклом после текущего"
    elif [ "${stage}" = done ]; then say stop "записано в беклог (${f}); /dt запустит новый цикл"
    else say stop "записано в беклог (${f}); возьмётся следующим циклом. Продолжить прогон: /dt"; fi
    ;;
  add)
    [ -n "${text}" ] || { say stop "пустая правка: /dt-add <текст>"; exit 0; }
    [ "${state}" = yes ] || { say stop "нечего править — пайплайна нет: /dt-new <задача>"; exit 0; }
    f="$(intake add amendments)"
    if [ "${live}" = 1 ]; then
      say stop "правка записана (${f}); оркестратор прервёт текущую роль и уйдёт в перепланирование в течение нескольких секунд"
    else
      say run "правка записана (${f}); прогон не идёт — запускаю с перепланированием"
    fi
    ;;
  resume)
    if [ "${live}" = 1 ]; then say stop "оркестратор уже работает (pid $(lock_pid)). Статус: /dt-status"; exit 0; fi
    if [ "${stage}" = done ] && ! has_pending "${P}/backlog/pending" && ! has_pending "${P}/amendments/pending"; then
      say stop "всё сделано (stage=done), беклог пуст"; exit 0
    fi
    if [ "${stage}" = blocked ] && ! has_pending "${P}/amendments/pending"; then
      say stop "пайплайн в blocked: ${BLOCK_REASON:-см. history}. Поправь задачу: /dt-add <правка>"; exit 0
    fi
    say run
    ;;
  new)
    [ -n "${text}" ] || { say stop "нет текста задачи: /dt-new <задача> (или /dt-new @файл)"; exit 0; }
    if [ "${live}" = 1 ]; then say stop "оркестратор работает (pid $(lock_pid)). Сначала /dt-stop"; exit 0; fi
    if [ "${state}" = yes ] && [ "${stage}" != done ] && [ "${force}" = 0 ]; then
      say stop "незаконченный пайплайн (stage=${stage}): /dt-resume или /dt-new --force <задача>"
      exit 0
    fi
    tf="$(mktemp "${TMPDIR:-/tmp}/dt-task.XXXXXX")"; printf '%s\n' "${text}" > "${tf}"
    DT_ARCHIVED=""
    do_new "${tf}"
    if [ -n "${DT_ARCHIVED}" ]; then say run "старый пайплайн → ${DT_ARCHIVED}; новая задача принята"
    else say run "новая задача принята"; fi
    ;;
  *)
    say stop "неизвестный режим: ${mode} (ожидал new|resume|issue|add)"
    ;;
esac
