#!/bin/sh
# Session-start hook for coding agents: `agent-hook.sh NAME`, with the agent's
# hook payload (JSON with at least session_id) on stdin. Records which
# conversation is running in which Rex pane; hook.lua does the work. Once that
# pane is gone (tab closed, session killed) the conversation shows up in
# Archived Agent Sessions.
# Prints nothing: Claude Code adds a SessionStart hook's output to its context.
[ -n "$REX_BLOCK" ] || exit 0
data="${XDG_DATA_HOME:-$HOME/.local/share}/rex-archive"
mkdir -p "$data/agents"
payload=$(cat)
if ! command -v rex >/dev/null 2>&1; then
  # Leave a note for the setup check instead of printing.
  echo "rex isn't on the agent's PATH, so its conversations aren't being recorded" > "$data/hook-problem"
  exit 0
fi
rm -f "$data/hook-problem"
rex do "$(dirname "$0")/hook.lua" agent="$1" block="$REX_BLOCK" session="${REX_SESSION:-}" \
  pwd="$PWD" dir="$data/agents" payload="$payload" >/dev/null 2>&1
exit 0
