#!/usr/bin/env bash
#
# dream-team — установщик агентского пайплайна (install == update, одна команда).
#
#   curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
#
# Интерактивно спросит: харнес (opencode / claude / оба) и область (global / local).
# Неинтерактивно (пайп без tty) берёт переменные окружения / значения по умолчанию:
#   DREAM_TEAM_HARNESS=opencode|claude|both   (default: opencode)
#   DREAM_TEAM_SCOPE=global|local             (default: local)
#   DREAM_TEAM_BRANCH=main
#
set -euo pipefail

REPO="neoff/dream-team"
BRANCH="${DREAM_TEAM_BRANCH:-main}"

# Что именно ставим (только наши файлы — чужие агенты/скилы в целевой папке не трогаем).
AGENTS=(agent-manager agent-planner agent-critic agent-coder agent-reviewer agent-tester agent-debugger)
SKILLS=(agent-pipeline agent-pipeline-run agent-manager agent-planner agent-critic agent-coder agent-reviewer agent-tester agent-debugger)

GI_BEGIN="# >>> dream-team >>>"
GI_END="# <<< dream-team <<<"

c_info='\033[1;36m'; c_ok='\033[1;32m'; c_warn='\033[1;33m'; c_err='\033[1;31m'; c_dim='\033[2m'; c_off='\033[0m'
info(){ printf "${c_info}›${c_off} %s\n" "$*"; }
ok(){   printf "${c_ok}✓${c_off} %s\n" "$*"; }
warn(){ printf "${c_warn}!${c_off} %s\n" "$*"; }
die(){  printf "${c_err}✗${c_off} %s\n" "$*" >&2; exit 1; }

have_tty(){ [ -r /dev/tty ] && [ -w /dev/tty ]; }

# Меню: $1 = текст, далее пары "value|label"; эхо выбранного value.
menu(){
  local prompt="$1"; shift
  local vals=() labels=() i
  for pair in "$@"; do vals+=("${pair%%|*}"); labels+=("${pair#*|}"); done
  {
    printf "\n%b%s%b\n" "$c_info" "$prompt" "$c_off"
    for i in "${!labels[@]}"; do printf "  %d) %s\n" $((i+1)) "${labels[$i]}"; done
    printf "%b#? %b" "$c_dim" "$c_off"
  } >/dev/tty
  local choice
  read -r choice </dev/tty || choice=1
  case "$choice" in ''|*[!0-9]*) choice=1;; esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#vals[@]}" ] || choice=1
  printf '%s' "${vals[$((choice-1))]}"
}

# ---- 1. выбор харнеса и области -------------------------------------------
HARNESS="${DREAM_TEAM_HARNESS:-}"
SCOPE="${DREAM_TEAM_SCOPE:-}"

if [ -z "$HARNESS" ]; then
  if have_tty; then
    HARNESS="$(menu "Для какого харнеса ставить?" "opencode|opencode" "claude|claude (не тестировалось)" "both|оба")"
  else
    HARNESS="opencode"
  fi
fi
if [ -z "$SCOPE" ]; then
  if have_tty; then
    SCOPE="$(menu "Куда ставить?" "local|local — в текущий проект ($(pwd))" "global|global — для всех проектов")"
  else
    SCOPE="local"
  fi
fi

case "$HARNESS" in opencode|claude|both) ;; *) die "неизвестный харнес: $HARNESS";; esac
case "$SCOPE" in local|global) ;; *) die "неизвестная область: $SCOPE";; esac

targets_for(){ # $1 harness -> эхо базовой папки по $SCOPE
  case "$1" in
    opencode) [ "$SCOPE" = global ] && printf '%s' "$HOME/.config/opencode" || printf '%s' "$PWD/.opencode" ;;
    claude)   [ "$SCOPE" = global ] && printf '%s' "$HOME/.claude"         || printf '%s' "$PWD/.claude" ;;
  esac
}

HLIST=(); case "$HARNESS" in opencode) HLIST=(opencode);; claude) HLIST=(claude);; both) HLIST=(opencode claude);; esac

# ---- 2. выкачать репо во временную папку ----------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
info "Качаю $REPO@$BRANCH …"
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$TMP/src" -q || die "git clone не удался"
  SRC="$TMP/src"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" | tar xz -C "$TMP" || die "скачивание tarball не удалось"
  SRC="$TMP/dream-team-$BRANCH"
else
  die "нужен git или curl"
fi
[ -d "$SRC/.opencode/agents" ] || die "в репо не найден .opencode/agents (битая выкачка?)"

# ---- 3. установка (перезапись = апдейт) -----------------------------------
install_into(){ # $1 = базовая целевая папка
  local base="$1" a s
  mkdir -p "$base/agents" "$base/skills"
  for a in "${AGENTS[@]}"; do
    cp -f "$SRC/.opencode/agents/$a.md" "$base/agents/$a.md"
  done
  for s in "${SKILLS[@]}"; do
    rm -rf "$base/skills/$s"
    cp -R "$SRC/.opencode/skills/$s" "$base/skills/$s"
  done
}

# .gitignore для локальной установки: если есть .gitignore ИЛИ проект под git —
# занести установленные пути (идемпотентный блок с маркерами).
ensure_gitignore(){ # $1 = имя целевой папки, напр. .opencode / .claude
  local dir="$1" gi="$PWD/.gitignore"
  local is_git=0; git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=1
  { [ -f "$gi" ] || [ "$is_git" = 1 ]; } || return 0
  local block
  block="$GI_BEGIN"$'\n'
  block+="$dir/agents/agent-manager.md"$'\n'
  block+="$dir/agents/agent-planner.md"$'\n'
  block+="$dir/agents/agent-critic.md"$'\n'
  block+="$dir/agents/agent-coder.md"$'\n'
  block+="$dir/agents/agent-reviewer.md"$'\n'
  block+="$dir/agents/agent-tester.md"$'\n'
  block+="$dir/agents/agent-debugger.md"$'\n'
  local s2
  for s2 in "${SKILLS[@]}"; do block+="$dir/skills/$s2/"$'\n'; done
  block+="$dir/.planning/"$'\n'
  block+="$GI_END"
  touch "$gi"
  # вырезать старый блок (если был) и дописать свежий
  if grep -qF "$GI_BEGIN" "$gi"; then
    local tmp; tmp="$(mktemp)"
    awk -v b="$GI_BEGIN" -v e="$GI_END" '
      $0==b{skip=1} !skip{print} $0==e{skip=0}' "$gi" > "$tmp"
    mv "$tmp" "$gi"
  fi
  printf '%s\n' "$block" >> "$gi"
  ok "В .gitignore занесён блок dream-team ($dir)"
}

for h in "${HLIST[@]}"; do
  base="$(targets_for "$h")"
  info "Ставлю [$h / $SCOPE] → $base"
  install_into "$base"
  [ "$h" = claude ] && warn "claude: формат агентов opencode-специфичен (mode/permissions/subagent) — на Claude Code не тестировалось."
  ok "Установлено: ${#AGENTS[@]} агентов + ${#SKILLS[@]} скилов в $base"
  if [ "$SCOPE" = local ]; then
    case "$h" in opencode) ensure_gitignore ".opencode";; claude) ensure_gitignore ".claude";; esac
  fi
done

# ---- 4. итог ---------------------------------------------------------------
printf "\n${c_ok}Готово.${c_off} Запуск:\n"
if printf '%s\n' "${HLIST[@]}" | grep -qx opencode; then
  printf "  ${c_dim}# opencode${c_off}\n"
  printf "  opencode run --agent agent-manager \"Твоя задача\"\n"
  printf "  opencode run --standalone --agent agent-manager \"resume\"   ${c_dim}# продолжить${c_off}\n"
fi
printf "\nОбновление — та же команда:\n"
printf "  curl -fsSL https://raw.githubusercontent.com/%s/%s/install.sh | bash\n" "$REPO" "$BRANCH"
