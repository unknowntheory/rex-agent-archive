#!/bin/sh
# Check what Archived Agent Sessions needs: commands, the agent hooks, and the
# require line in the Rex config.
# Usage: check.sh [--no-wait]   (--no-wait for running outside a popup)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
data="${XDG_DATA_HOME:-$HOME/.local/share}/rex-archive"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/rex"
problems=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  MISS  %s\n' "$1"; problems=$((problems + 1)); }
note() { printf '  note  %s\n' "$1"; }

echo "Archived Agent Sessions"
printf '\nCommands\n'
for c in rex fzf jq; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"
  elif [ "$c" = rex ]; then bad "rex (comes with the Rex app; run this from a Rex terminal)"
  else bad "$c  (brew install $c)"; fi
done

printf '\nAgent hooks\n'
for pair in "Claude Code:$HOME/.claude/settings.json" "Codex:$HOME/.codex/hooks.json"; do
  name=${pair%%:*}; file=${pair#*:}
  if [ ! -f "$file" ]; then note "$name: not set up, skipped"
  elif grep -q 'archive/agent-hook.sh' "$file"; then ok "$name: hook registered"
  else bad "$name: hook not registered (run install.sh)"; fi
done
grep -q 'archive/agent-hook.sh' "$HOME/.codex/hooks.json" 2>/dev/null &&
  note "Codex: approve the hook with /hooks inside Codex if you haven't"
[ -f "$data/hook-problem" ] && bad "$(cat "$data/hook-problem")"

printf '\nAgents (agents.json, agents.local.json)\n'
here=$(cd "$(dirname "$0")" && pwd)
cat "$here/agents.json" "$here/agents.local.json" 2>/dev/null | jq -rs 'reduce .[] as $x ({}; . * $x) | to_entries[] | "\(.key)\t\(.value.resume // "")"' |
while IFS="$(printf '\t')" read -r name resume; do
  cmd=${resume%% *}
  if [ -z "$resume" ]; then note "$name: no resume command"
  elif command -v "$cmd" >/dev/null 2>&1; then ok "$name: $cmd"
  else note "$name: $cmd not installed"; fi
done

printf '\nRex config\n'
if grep -qsE 'require[ (,]*"archive"' "$conf/init.lua"; then ok 'init.lua has require("archive")'
else bad "add require(\"archive\") to $conf/init.lua, then run rex config reload"; fi

echo
if [ "$problems" -eq 0 ]; then echo "Everything is in place."; else echo "$problems problem(s) found."; fi
[ "${1:-}" = "--no-wait" ] || { printf '\nPress Enter to close. '; read -r _; }
[ "$problems" -eq 0 ]
