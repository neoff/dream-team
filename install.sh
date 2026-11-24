#!/usr/bin/env bash
#
# dream-team — agent pipeline installer (install == update, one command).
#
#   curl -fsSL https://raw.githubusercontent.com/neoff/dream-team/main/install.sh | bash
#
# Interactively asks: harness (mahcode / opencode / claude / both) and scope (global / local).
# Non-interactively (pipe without a tty) takes environment variables / defaults:
#   DREAM_TEAM_HARNESS=mahcode|opencode|claude|both   (default: mahcode)
#   DREAM_TEAM_SCOPE=global|local             (default: local)
#   DREAM_TEAM_BRANCH=main
#
set -euo pipefail

REPO="neoff/dream-team"
BRANCH="${DREAM_TEAM_BRANCH:-main}"

# What exactly we install (only our files — other agents/skills in the target folder are left alone).
AGENTS=(agent-manager agent-planner agent-critic agent-coder agent-reviewer agent-tester agent-debugger)
SKILLS=(agent-pipeline agent-pipeline-run agent-manager agent-planner agent-critic agent-coder agent-reviewer agent-tester agent-debugger)
COMMANDS=(dt dt-resume dt-new dt-issue dt-add dt-status dt-stop dt-log)

GI_BEGIN="# >>> dream-team >>>"
GI_END="# <<< dream-team <<<"

c_info='\033[1;36m'; c_ok='\033[1;32m'; c_warn='\033[1;33m'; c_err='\033[1;31m'; c_dim='\033[2m'; c_off='\033[0m'
info(){ printf "${c_info}›${c_off} %s\n" "$*"; }
ok(){   printf "${c_ok}✓${c_off} %s\n" "$*"; }
warn(){ printf "${c_warn}!${c_off} %s\n" "$*"; }
die(){  printf "${c_err}✗${c_off} %s\n" "$*" >&2; exit 1; }

have_tty(){ [ -r /dev/tty ] && [ -w /dev/tty ]; }

# Menu: $1 = text, then "value|label" pairs; echoes the chosen value.
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

# ---- 1. choose harness and scope -------------------------------------------
HARNESS="${DREAM_TEAM_HARNESS:-}"
SCOPE="${DREAM_TEAM_SCOPE:-}"

if [ -z "$HARNESS" ]; then
  if have_tty; then
    HARNESS="$(menu "Which harness to install for?" "mahcode|mahcode (MCP version: manager + pair leads)" "opencode|opencode (bash orchestrator)" "claude|claude (untested)" "both|opencode + claude")"
  else
    HARNESS="mahcode"
  fi
fi
if [ -z "$SCOPE" ]; then
  if have_tty; then
    SCOPE="$(menu "Where to install?" "local|local — into the current project ($(pwd))" "global|global — for all projects")"
  else
    SCOPE="local"
  fi
fi

case "$HARNESS" in mahcode|opencode|claude|both) ;; *) die "unknown harness: $HARNESS";; esac
case "$SCOPE" in local|global) ;; *) die "unknown scope: $SCOPE";; esac

targets_for(){ # $1 harness -> echo the base folder for $SCOPE
  case "$1" in
    opencode) [ "$SCOPE" = global ] && printf '%s' "$HOME/.config/opencode" || printf '%s' "$PWD/.opencode" ;;
    claude)   [ "$SCOPE" = global ] && printf '%s' "$HOME/.claude"         || printf '%s' "$PWD/.claude" ;;
  esac
}

HLIST=(); case "$HARNESS" in mahcode) HLIST=(mahcode);; opencode) HLIST=(opencode);; claude) HLIST=(claude);; both) HLIST=(opencode claude);; esac

# ---- 2. fetch the repo into a temp folder ----------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
info "Fetching $REPO@$BRANCH …"
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 -b "$BRANCH" "https://github.com/$REPO.git" "$TMP/src" -q || die "git clone failed"
  SRC="$TMP/src"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" | tar xz -C "$TMP" || die "tarball download failed"
  SRC="$TMP/dream-team-$BRANCH"
else
  die "git or curl is required"
fi
[ -d "$SRC/.opencode/agents" ] || die ".opencode/agents not found in the repo (broken download?)"

# ---- 3. install (overwrite = update) -----------------------------------
install_into(){ # $1 = base target folder
  local base="$1" a s
  mkdir -p "$base/agents" "$base/skills" "$base/commands"
  for a in "${AGENTS[@]}"; do
    cp -f "$SRC/.opencode/agents/$a.md" "$base/agents/$a.md"
  done
  for s in "${SKILLS[@]}"; do
    rm -rf "$base/skills/$s"
    cp -R "$SRC/.opencode/skills/$s" "$base/skills/$s"
  done
  for c in "${COMMANDS[@]}"; do
    cp -f "$SRC/.opencode/commands/$c.md" "$base/commands/$c.md"
  done
}

# .gitignore for a local install: if there is a .gitignore OR the project is under git —
# add the installed paths (idempotent block with markers).
ensure_gitignore(){ # $1 = target folder name, e.g. .opencode / .claude
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
  local c2
  for c2 in "${COMMANDS[@]}"; do block+="$dir/commands/$c2.md"$'\n'; done
  block+=".planning/"$'\n'
  block+="$GI_END"
  touch "$gi"
  # cut out the old block (if any) and append a fresh one
  if grep -qF "$GI_BEGIN" "$gi"; then
    local tmp; tmp="$(mktemp)"
    awk -v b="$GI_BEGIN" -v e="$GI_END" '
      $0==b{skip=1} !skip{print} $0==e{skip=0}' "$gi" > "$tmp"
    mv "$tmp" "$gi"
  fi
  printf '%s\n' "$block" >> "$gi"
  ok "dream-team block added to .gitignore ($dir)"
}

# mahcode: markdown + MCP only (no bash at runtime). Always into the project (cwd).
install_mahcode(){
  local dst="$PWD/.mahcode" s
  mkdir -p "$dst/skills"
  for s in dream-team agent-planner agent-critic agent-coder agent-reviewer agent-tester agent-debugger; do
    rm -rf "$dst/skills/$s"; cp -R "$SRC/.mahcode/skills/$s" "$dst/skills/$s"
  done
  if [ -f "$dst/dream-team.yaml" ]; then ok "dream-team.yaml already exists — leaving the project's models alone"
  else cp "$SRC/.mahcode/dream-team.yaml" "$dst/dream-team.yaml"; ok "created .mahcode/dream-team.yaml (adjust the models for the project)"; fi
  # AGENTS.md: entry block (idempotent, by markers)
  local ag="$PWD/AGENTS.md" tmp
  touch "$ag"
  if grep -qF '<!-- >>> dream-team >>> -->' "$ag"; then
    tmp="$(mktemp)"; awk '/<!-- >>> dream-team >>> -->/{skip=1} !skip{print} /<!-- <<< dream-team <<< -->/{skip=0}' "$ag" > "$tmp"; mv "$tmp" "$ag"
  fi
  printf '\n' >> "$ag"; cat "$SRC/.mahcode/templates/AGENTS.dream-team.md" >> "$ag"
  ok "AGENTS.md: @dream-team entry"
  # .mcp.json: mahcode MCP for the project's native sessions
  if [ ! -f "$PWD/.mcp.json" ]; then
    printf '{ "mcpServers": { "mahcode": { "command": "mahcode", "args": ["mcp", "serve"] } } }\n' > "$PWD/.mcp.json"
  elif ! grep -q '"mahcode"' "$PWD/.mcp.json"; then
    warn ".mcp.json already exists — add the mahcode server (command: mahcode, args: [mcp, serve]) manually"
  fi
  command -v mahcode >/dev/null 2>&1 && (cd "$PWD" && mahcode mcp trust >/dev/null) && ok "mahcode mcp trust"
  warn "for the manager/leads to work on codex/claude/agy, register the mahcode MCP in their configs (see README)"
}

for h in "${HLIST[@]}"; do
  if [ "$h" = mahcode ]; then info "Installing [mahcode] → $PWD/.mahcode"; install_mahcode; continue; fi
  base="$(targets_for "$h")"
  info "Installing [$h / $SCOPE] → $base"
  install_into "$base"
  [ "$h" = claude ] && warn "claude: the agent format is opencode-specific (mode/permissions/subagent) — untested on Claude Code."
  ok "Installed: ${#AGENTS[@]} agents + ${#SKILLS[@]} skills + ${#COMMANDS[@]} commands into $base"
  if [ "$SCOPE" = local ]; then
    case "$h" in opencode) ensure_gitignore ".opencode";; claude) ensure_gitignore ".claude";; esac
  fi
done

# ---- 4. summary ---------------------------------------------------------------
printf "\n${c_ok}Done.${c_off} Launch:\n"
if printf '%s\n' "${HLIST[@]}" | grep -qx opencode; then
  printf "  ${c_dim}# opencode${c_off}\n"
  printf "  ${c_dim}# in the opencode TUI:${c_off} /dt-new <task|@file> · /dt · /dt-add · /dt-issue · /dt-status · /dt-stop\n"
  if [ "$SCOPE" = global ]; then dtcli="$HOME/.config/opencode/skills/agent-manager/dt-cli.sh"; else dtcli=".opencode/skills/agent-manager/dt-cli.sh"; fi
  printf "  ${c_dim}# from the terminal:${c_off} alias dt='bash %s'\n" "$dtcli"
  printf "  dt --new @prompt.md   ·   dt   ·   dt --status   ·   dt --log -f   ·   dt --stop\n"
fi
printf "\nUpdate — the same command:\n"
printf "  curl -fsSL https://raw.githubusercontent.com/%s/%s/install.sh | bash\n" "$REPO" "$BRANCH"
