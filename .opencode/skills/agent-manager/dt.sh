#!/usr/bin/env bash
#
# dream-team: /dt input parsing (deterministic, no LLM).
#
#   printf '%s' "<message>" | bash dt.sh
#
# The message — as from a slash command (`<dt mode="add">text</dt>`) or plain text
# (`/dt-add text`, `/dt --add text`, `--add text`, `resume`, `task`…).
# Text can come from a file: `--new-file path`, or `@path` instead of text (for huge prompts).
#
# Prints a directive:
#   ACTION=stop   + MSG=…   — tell the user and start nothing
#   ACTION=run    [+ MSG=…] — start/resume the orchestrator (dt-run.sh)
# For new/issue/add it does all the preparation itself (archive, task-context, intake).
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
drop_first(){ # $1 text, $2 first token -> remainder
  if [ "$2" = "$1" ]; then printf ''; else trim "${1#"$2"}"; fi
}
text="$(trim "${text}")"

# the slash command itself may be sent as text: "/dt --add …", "/dt-add …", "dt --add …"
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

# @path → file content (path without trailing spaces; relative — from cwd)
if [ "${text#@}" != "${text}" ]; then
  src="$(trim "${text#@}")"
  src="${src/#\~/${HOME}}"
  [ -f "${src}" ] || { say stop "file not found: ${src}"; exit 0; }
  text="$(cat "${src}")"
  [ -n "$(trim "${text}")" ] || { say stop "file is empty: ${src}"; exit 0; }
fi

# --- probe ---
state=no; stage=none
if state_exists; then state=yes; state_load || true; stage="${STAGE}"; fi
live=0; lock_alive && live=1

intake(){ # $1 kind(add|issue) $2 dir(amendments|backlog) -> path
  local ts d f n=1
  ts="$(date +%Y%m%d-%H%M%S)"; d="${P}/$2/pending"; mkdir -p "${d}"
  f="${d}/$1-${ts}.md"
  while [ -e "${f}" ]; do f="${d}/$1-${ts}-${n}.md"; n=$((n+1)); done
  { printf '# %s\nsource: /dt-%s\nstage_at_receive: %s\n\n## User text (verbatim)\n' "$1" "$1" "${stage}"
    printf '%s\n' "${text}"; } > "${f}"
  printf '%s' "${f}"
}

if [ "${mode}" = auto ]; then
  if [ -z "${text}" ]; then
    if [ "${state}" = yes ]; then mode=resume
    else say stop "no pipeline and no task: /dt-new <task> (or /dt-new @file)"; exit 0; fi
  elif [ "${state}" = no ]; then mode=new
  else
    say stop "a pipeline already exists (stage=${stage}). Is this an amendment (/dt-add), a backlog addition (/dt-issue) or a new task (/dt-new --force)? Doing nothing."
    exit 0
  fi
fi
if [ "${mode}" = resume ] && [ "${state}" = no ]; then
  [ -n "${text}" ] || { say stop "no pipeline: /dt-new <task>"; exit 0; }
  mode=new
fi

case "${mode}" in
  issue)
    [ -n "${text}" ] || { say stop "empty addition: /dt-issue <text>"; exit 0; }
    f="$(intake issue backlog)"
    if [ "${state}" = no ]; then say stop "added to the backlog (${f}); no pipeline yet — /dt-new <task>"
    elif [ "${live}" = 1 ]; then say stop "added to the backlog (${f}); it will be taken as the next cycle after the current one"
    elif [ "${stage}" = done ]; then say stop "added to the backlog (${f}); /dt will start a new cycle"
    else say stop "added to the backlog (${f}); it will be taken as the next cycle. Resume the run: /dt"; fi
    ;;
  add)
    [ -n "${text}" ] || { say stop "empty amendment: /dt-add <text>"; exit 0; }
    [ "${state}" = yes ] || { say stop "nothing to amend — no pipeline: /dt-new <task>"; exit 0; }
    f="$(intake add amendments)"
    if [ "${live}" = 1 ]; then
      say stop "amendment recorded (${f}); the orchestrator will interrupt the current role and replan within a few seconds"
    else
      say run "amendment recorded (${f}); no run in progress — starting with a replan"
    fi
    ;;
  resume)
    if [ "${live}" = 1 ]; then say stop "the orchestrator is already running (pid $(lock_pid)). Status: /dt-status"; exit 0; fi
    if [ "${stage}" = done ] && ! has_pending "${P}/backlog/pending" && ! has_pending "${P}/amendments/pending"; then
      say stop "everything is done (stage=done), the backlog is empty"; exit 0
    fi
    if [ "${stage}" = blocked ] && ! has_pending "${P}/amendments/pending"; then
      say stop "the pipeline is blocked: ${BLOCK_REASON:-see history}. Amend the task: /dt-add <amendment>"; exit 0
    fi
    say run
    ;;
  new)
    [ -n "${text}" ] || { say stop "no task text: /dt-new <task> (or /dt-new @file)"; exit 0; }
    if [ "${live}" = 1 ]; then say stop "the orchestrator is running (pid $(lock_pid)). /dt-stop first"; exit 0; fi
    if [ "${state}" = yes ] && [ "${stage}" != done ] && [ "${force}" = 0 ]; then
      say stop "unfinished pipeline (stage=${stage}): /dt-resume or /dt-new --force <task>"
      exit 0
    fi
    tf="$(mktemp "${TMPDIR:-/tmp}/dt-task.XXXXXX")"; printf '%s\n' "${text}" > "${tf}"
    DT_ARCHIVED=""
    do_new "${tf}"
    if [ -n "${DT_ARCHIVED}" ]; then say run "old pipeline → ${DT_ARCHIVED}; new task accepted"
    else say run "new task accepted"; fi
    ;;
  *)
    say stop "unknown mode: ${mode} (expected new|resume|issue|add)"
    ;;
esac
