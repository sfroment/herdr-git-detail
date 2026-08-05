#!/bin/sh
# herdr-git-detail — rich git status for the herdr sidebar.
#
# Reports per-category workspace tokens so herdr can color each independently
# via inline style tables in [ui.sidebar.spaces]. One token per status kind;
# empty tokens are cleared so stale values never linger.
#
#   $git_modified   !<n>   modified (unstaged) files
#   $git_untracked  ?<n>   untracked files
#   $git_staged     +<n>   staged files
#   $git_conflict   ✗<n>   unmerged (conflict) files
#   $git_ahead      ⇡<n>   commits ahead of upstream
#   $git_behind     ⇣<n>   commits behind upstream
#   $git_stash      *<n>   stash entries
#
# The branch is intentionally NOT reported — herdr's native `branch` token
# already shows it, so we avoid duplication.
#
# Usage:
#   git-detail.sh watch          # background loop (startup hook)
#   git-detail.sh once           # single pass over all workspaces
#   git-detail.sh status <dir>   # print computed status for a repo (debug)
#
# Configure via config.sh (optional):
#   GIT_DETAIL_INTERVAL=5        # seconds between passes (default 5)

set -eu

# --- config -----------------------------------------------------------------
PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$PLUGIN_ROOT}"
CONFIG_FILE="${CONFIG_DIR:-$PLUGIN_ROOT}/config.sh"

GIT_DETAIL_INTERVAL=5
GIT_DETAIL_SOURCE="git-detail"

if [ -n "${CONFIG_DIR:-}" ] && [ -f "${CONFIG_DIR}/config.sh" ]; then
  . "${CONFIG_DIR}/config.sh"
elif [ -z "${CONFIG_DIR:-}" ] && [ -f "${CONFIG_FILE}" ]; then
  . "${CONFIG_FILE}"
fi

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

# --- git status computation --------------------------------------------------
# Prints space-separated counts: staged modified untracked conflict ahead behind stash
# for the repo at $1, or empty line if not a git repo.
compute_counts() {
  dir="$1"
  [ -d "$dir" ] || return 0
  cd "$dir" 2>/dev/null || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  # Porcelain v2: count by category.
  set -- $(git status --porcelain=v2 --branch 2>/dev/null | awk '
    /^# branch.upstream/ { next }
    /^branch\.ab /       { ahead=$3; behind=$4; next }
    /^branch\.ahead /    { ahead=$3; next }
    /^branch\.behind /   { behind=$3; next }
    /^1 / { staged++; if (substr($2,2,1) != ".") modified++; next }
    /^2 / { staged++; if (substr($2,2,1) != ".") modified++; next }
    /^\? / { untracked++; next }
    /^u / { conflict++; next }
    END { printf "%d %d %d %d %d %d", staged, modified, untracked, conflict, ahead, behind }
  ')
  staged="${1:-0}"; modified="${2:-0}"; untracked="${3:-0}"; conflict="${4:-0}"
  ahead="${5:-0}"; behind="${6:-0}"

  # Ahead/behind fallback (porcelain v2 may omit branch.ab).
  if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [ -n "$upstream" ]; then
      counts="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || echo "0	0")"
      behind="$(printf '%s' "$counts" | cut -f1)"
      ahead="$(printf '%s' "$counts" | cut -f2)"
    fi
  fi

  stash="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  [ -n "$stash" ] || stash=0

  printf '%s %s %s %s %s %s %s' "$staged" "$modified" "$untracked" "$conflict" "$ahead" "$behind" "$stash"
}

# Format a count as "symbol+count" or empty (to clear the token).
fmt() { [ "$1" != "0" ] && printf '%s%s' "$2" "$1" || printf ''; }

# --- report a single workspace ---------------------------------------------
report_workspace() {
  ws_id="$1"; ws_cwd="$2"
  [ -n "$ws_id" ] || return 0

  counts="$(compute_counts "$ws_cwd")"
  # If not a git repo, counts is empty — clear all tokens.
  set -- $counts
  staged="${1:-0}"; modified="${2:-0}"; untracked="${3:-0}"; conflict="${4:-0}"
  ahead="${5:-0}"; behind="${6:-0}"; stash="${7:-0}"

  m="$(fmt "$modified" "!")";   u="$(fmt "$untracked" "?")"
  s="$(fmt "$staged" "+")";     c="$(fmt "$conflict" "✗")"
  a="$(fmt "$ahead" "⇡")";      b="$(fmt "$behind" "⇣")"
  st="$(fmt "$stash" "*")"

  "$HERDR_BIN" workspace report-metadata "$ws_id" --source "$GIT_DETAIL_SOURCE" \
    --token "git_modified=$m" --token "git_untracked=$u" \
    --token "git_staged=$s" --token "git_conflict=$c" \
    --token "git_ahead=$a" --token "git_behind=$b" \
    --token "git_stash=$st" >/dev/null 2>&1 || true
}

# --- single pass over all workspaces ---------------------------------------
pass_once() {
  "$HERDR_BIN" workspace list 2>/dev/null \
    | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for ws in d.get("result", {}).get("workspaces", []):
    print(ws.get("workspace_id", ""))
' 2>/dev/null | while IFS= read -r ws_id; do
    [ -n "$ws_id" ] || continue
    ws_cwd="$("$HERDR_BIN" pane list --workspace "$ws_id" 2>/dev/null \
      | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
panes = d.get(\"result\", {}).get(\"panes\", [])
if panes:
    print(panes[0].get(\"cwd\", \"\"))
" 2>/dev/null || true)"
    report_workspace "$ws_id" "$ws_cwd"
  done
}

# --- main -------------------------------------------------------------------
case "${1:-watch}" in
  watch)
    pass_once
    while true; do
      sleep "$GIT_DETAIL_INTERVAL"
      pass_once
    done
    ;;
  once)
    pass_once
    ;;
  status)
    shift
    counts="$(compute_counts "$1")"
    set -- $counts
    staged="${1:-0}"; modified="${2:-0}"; untracked="${3:-0}"; conflict="${4:-0}"
    ahead="${5:-0}"; behind="${6:-0}"; stash="${7:-0}"
    out=""
    [ "$modified"  != "0" ] && out="$out !${modified}"
    [ "$untracked" != "0" ] && out="$out ?${untracked}"
    [ "$staged"    != "0" ] && out="$out +${staged}"
    [ "$conflict"  != "0" ] && out="$out ✗${conflict}"
    [ "$ahead"     != "0" ] && out="$out ⇡${ahead}"
    [ "$behind"    != "0" ] && out="$out ⇣${behind}"
    [ "$stash"     != "0" ] && out="$out *${stash}"
    [ -n "$out" ] && echo "${out# }" || echo "clean"
    ;;
  *)
    echo "usage: git-detail.sh [watch|once|status <dir>]" >&2
    exit 2
    ;;
esac
