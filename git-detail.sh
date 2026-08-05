#!/bin/sh
# herdr-git-detail — rich git status for the herdr sidebar.
#
# Reports a $git_detail workspace token with:
#   !<n>   modified (unstaged) files
#   ?<n>   untracked files
#   +<n>   staged files
#   ⇡<n>   commits ahead of upstream
#   ⇣<n>   commits behind upstream
#   *<n>   stash entries
#   (clean) when nothing to show
#
# Also keeps the built-in `branch` token fresh (herdr updates it natively,
# but we re-set it to match the dirty repo's HEAD when present).
#
# Usage:
#   git-detail.sh watch          # background loop (startup hook)
#   git-detail.sh once           # single pass over all workspaces
#   git-detail.sh status <dir>   # print computed status string for a repo
#
# Configure via ~/sfroment/herdr-git-detail/config.sh (optional):
#   GIT_DETAIL_INTERVAL=5        # seconds between passes (default 5)
#   GIT_DETAIL_CLEAN="clean"     # text when nothing to show (default "clean")

set -eu

# --- config -----------------------------------------------------------------
PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:-$PLUGIN_ROOT}"
CONFIG_FILE="${CONFIG_DIR:-$PLUGIN_ROOT}/config.sh"

GIT_DETAIL_INTERVAL=5
GIT_DETAIL_CLEAN="clean"
GIT_DETAIL_SOURCE="git-detail"

if [ -n "${CONFIG_DIR:-}" ] && [ -f "${CONFIG_DIR}/config.sh" ]; then
  . "${CONFIG_DIR}/config.sh"
fi
if [ -z "${CONFIG_DIR:-}" ] && [ -f "${CONFIG_FILE}" ]; then
  . "${CONFIG_FILE}"
fi

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

# --- git status computation --------------------------------------------------
# Prints a compact status string for the repo at $1, or empty string if not a
# git repo. Uses porcelain=v2 + rev-list for ahead/behind; one git invocation
# for the counts, then cheap calls for stash and upstream.
compute_status() {
  dir="$1"
  [ -d "$dir" ] || return 0
  cd "$dir" 2>/dev/null || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0

  # Branch name (empty if detached, fallback to short commit)
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    branch="$(git rev-parse --short HEAD 2>/dev/null || true)"
    [ -n "$branch" ] && branch="($branch)"
  fi

  # Porcelain v2: count by category. Lines look like:
  #   1 <XY> ...          staged+unstaged changes
  #   2 <XY> ...          renamed
  #   u <XY> ...           unmerged (conflict)
  #   ? <path>             untracked
  set -- $(git status --porcelain=v2 --branch 2>/dev/null | awk '
    /^# branch.upstream/ { next }
    /^branch\.ab /        { ahead=$3; behind=$4; next }
    /^branch\.ahead /     { ahead=$3; next }
    /^branch\.behind /    { behind=$3; next }
    /^1 / { staged++; if (substr($2,2,1) != ".") modified++; next }
    /^2 / { staged++; if (substr($2,2,1) != ".") modified++; next }
    /^\? / { untracked++; next }
    /^u / { conflict++; next }
    END {
      printf "%d %d %d %d", staged, modified, untracked, conflict
    }
  ')
  staged="${1:-0}"; modified="${2:-0}"; untracked="${3:-0}"; conflict="${4:-0}"

  # Ahead/behind upstream (porcelain v2 prints branch.ab but some setups
  # don't; fall back to rev-list).
  ahead="${ahead:-0}"
  behind="${behind:-0}"
  if [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    if [ -n "$upstream" ]; then
      counts="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null || echo "0	0")"
      behind="$(printf '%s' "$counts" | cut -f1)"
      ahead="$(printf '%s' "$counts" | cut -f2)"
    fi
  fi

  # Stash count.
  stash="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  [ -n "$stash" ] || stash=0

  # Build the detail string.
  detail=""
  [ "$modified"  != "0" ] && detail="${detail}!${modified} "
  [ "$untracked" != "0" ] && detail="${detail}?${untracked} "
  [ "$staged"    != "0" ] && detail="${detail}+${staged} "
  [ "$conflict"  != "0" ] && detail="${detail}✗${conflict} "
  [ "$ahead"     != "0" ] && detail="${detail}⇡${ahead} "
  [ "$behind"    != "0" ] && detail="${detail}⇣${behind} "
  [ "$stash"     != "0" ] && detail="${detail}*${stash} "

  # Trim trailing space; default to "clean" when nothing changed.
  detail="$(printf '%s' "$detail" | sed 's/ *$//')"
  [ -n "$detail" ] || detail="$GIT_DETAIL_CLEAN"

  printf '%s  %s' "$branch" "$detail"
}

# --- report a single workspace ---------------------------------------------
report_workspace() {
  ws_id="$1"; ws_cwd="$2"
  [ -n "$ws_id" ] || return 0
  status="$(compute_status "$ws_cwd")"
  # Always report (even when clean / not a repo) so stale tokens clear.
  "$HERDR_BIN" workspace report-metadata "$ws_id" \
    --source "$GIT_DETAIL_SOURCE" \
    --token "git_detail=$status" >/dev/null 2>&1 || true
}

# --- single pass over all workspaces ---------------------------------------
pass_once() {
  # List workspaces, extract id + cwd. cwd lives on panes; the workspace's
  # own cwd is the first pane's cwd (the root pane).
  "$HERDR_BIN" workspace list 2>/dev/null \
    | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for ws in d.get("result", {}).get("workspaces", []):
    print(ws.get("workspace_id", "") + "\t")
' 2>/dev/null | while IFS="$(printf '\t')" read -r ws_id _; do
    [ -n "$ws_id" ] || continue
    # Resolve the workspace cwd from its first pane.
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
    # One immediate pass, then loop. herdr supervises via the startup hook;
    # if herdr restarts us we just resume.
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
    compute_status "$1"
    ;;
  *)
    echo "usage: git-detail.sh [watch|once|status <dir>]" >&2
    exit 2
    ;;
esac
