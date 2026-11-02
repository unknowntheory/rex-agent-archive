#!/bin/sh
# Install Archived Agent Sessions for Rex:
#  1. copy this folder to ~/.config/rex/archive (--link: symlink it instead,
#     so edits in this repo are live; for working on it)
#  2. add require("archive") to ~/.config/rex/init.lua
#  3. register the SessionStart hook for Claude Code and Codex (backups first)
#  4. reload the Rex config and check the setup
set -e
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
here=$(cd "$(dirname "$0")" && pwd)
conf="${XDG_CONFIG_HOME:-$HOME/.config}/rex"
dest="$conf/archive"
stamp=$(date +%Y%m%d%H%M%S)
mode=copy
[ "${1:-}" = "--link" ] && mode=link

command -v jq >/dev/null 2>&1 || { echo "jq is required: brew install jq"; exit 1; }

# 1. Files
if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$here" ]; then
  echo "$dest already links here"
elif [ "$here" != "$dest" ]; then
  if [ -e "$dest" ] || [ -L "$dest" ]; then mv "$dest" "$dest.bak-$stamp"; echo "moved old $dest to $dest.bak-$stamp"; fi
  mkdir -p "$conf"
  if [ "$mode" = link ]; then
    ln -s "$here" "$dest"
    echo "linked $dest -> $here"
  else
    cp -R "$here" "$dest"
    rm -rf "$dest/.git"
    echo "installed $dest"
  fi
  # Keep the user's own agent settings across reinstalls.
  if [ -f "$dest.bak-$stamp/agents.local.json" ] && [ ! -f "$dest/agents.local.json" ]; then
    cp "$dest.bak-$stamp/agents.local.json" "$dest/"
  fi
fi

# 2. Rex config
touch "$conf/init.lua"
if grep -qsE 'require[ (,]*"archive"' "$conf/init.lua"; then
  echo "init.lua already loads it"
else
  printf '\n-- Archived Agent Sessions (%s)\nrequire("archive")\n' "$dest" >> "$conf/init.lua"
  echo "added require(\"archive\") to $conf/init.lua"
fi

# 3. Agent hooks, appended after any existing SessionStart hooks
register() { # settings file, agent name
  file=$1; agent=$2
  hook="$dest/agent-hook.sh"
  [ "$dest" = "$HOME/.config/rex/archive" ] && hook='$HOME/.config/rex/archive/agent-hook.sh'
  cmd="/bin/sh -c '\"$hook\" $agent 2>/dev/null || true'"
  [ -s "$file" ] || echo '{}' > "$file"
  if jq -e --arg cmd "$cmd" '[.hooks.SessionStart[]?.hooks[]?.command] | index($cmd)' "$file" >/dev/null; then
    echo "$agent: hook already registered"
    return
  fi
  cp "$file" "$file.bak-$stamp"
  jq --arg cmd "$cmd" '.hooks.SessionStart += [{hooks: [{type: "command", command: $cmd, timeout: 5}]}]' \
    "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  echo "$agent: hook registered in $file (backup: $file.bak-$stamp)"
}
[ -d "$HOME/.claude" ] && register "$HOME/.claude/settings.json" claude
[ -d "$HOME/.codex" ] && register "$HOME/.codex/hooks.json" codex

# 4. Reload and check
if command -v rex >/dev/null 2>&1; then
  rex config reload >/dev/null 2>&1 && echo "reloaded Rex config" || echo "run: rex config reload"
fi
echo
sh "$dest/check.sh" --no-wait || true
cat <<'NOTE'

Next:
  - Codex: approve the new hook with /hooks inside Codex.
  - Start new agent sessions inside Rex; conversations started before the
    hook was installed aren't recorded.
  - Open it from the command palette: "Archived Agent Sessions".
NOTE
