#!/bin/sh
# Session-start hook for coding agents: `agent-hook.sh NAME`, with the agent's
# hook payload (JSON with at least session_id) on stdin. Records which
# conversation is running in which Rex pane. Once that pane is gone (tab closed, session killed)
# the conversation shows up in Archived Sessions.
# Prints nothing: Claude Code adds a SessionStart hook's output to its context.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
agent=$1
[ -n "$REX_BLOCK" ] || exit 0
data="${XDG_DATA_HOME:-$HOME/.local/share}/rex-archive"
mkdir -p "$data/agents"
# Can't record anything without jq. Leave a note for the browser and the setup
# check instead of printing, which would end up in the agent's context.
if ! command -v jq >/dev/null 2>&1; then
  cat >/dev/null
  echo "jq is missing, so agent conversations aren't being recorded (brew install jq)" > "$data/hook-problem"
  exit 0
fi
rm -f "$data/hook-problem"
input=$(cat)
id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
case "$id" in ''|*/*) exit 0 ;; esac
dir="$data/agents"
printf '%s' "$input" | jq -c \
  --arg agent "$agent" --arg block "$REX_BLOCK" --arg session "${REX_SESSION:-}" --arg pwd "$PWD" \
  '{agent: $agent, block: $block, rex_session: $session, session_id,
    cwd: (.cwd // $pwd), transcript_path, at: (now | todate)}' \
  > "$dir/$id.json" 2>/dev/null
exit 0
