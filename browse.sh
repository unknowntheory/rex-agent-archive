#!/bin/sh
# Archived agent conversations: ones whose Rex pane has closed, or that a newer
# conversation replaced in the same pane. Enter resumes one in a new tab of the
# current session; Ctrl-D removes it from the list (the transcript is kept).
. "$(dirname "$0")/deps.sh"
need fzf jq rex
agents="${XDG_DATA_HOME:-$HOME/.local/share}/rex-archive/agents"
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

# Each message as a JSON line {role, text}, from either transcript format.
# Skips injected context, which starts with "<" or is marked as meta.
messages() {
  jq -c '
    if .type == "user" or .type == "assistant" then
      select(.isMeta != true) | {role: .type, text: (.message.content
        | if type == "string" then . else (map(select(.type == "text").text) | join("\n\n")) end)}
    elif .type == "response_item" and .payload.type == "message" then
      {role: .payload.role, text: (.payload.content | map(.text // empty) | join("\n\n"))}
    else empty end
    | select(.role == "user" or .role == "assistant")
    | select(.text != "" and (.text | test("^\\s*(<|# AGENTS.md)") | not))' "$1" 2>/dev/null
}

# First user message or last assistant message, as plain text.
first_prompt() { messages "$1" | jq -rs 'map(select(.role == "user")) | first.text // ""'; }
last_reply()   { messages "$1" | jq -rs 'map(select(.role == "assistant")) | last.text // ""'; }

# Per-agent settings: agents.json, with agents.local.json (if any) on top.
here=$(dirname "$self")
agent_table=$(cat "$here/agents.json" "$here/agents.local.json" 2>/dev/null | jq -s 'reduce .[] as $x ({}; . * $x)')

# "<mark> <Name>" for an agent, colored if agents.json gives a color.
mark() {
  printf '%s' "$agent_table" | jq -r --arg a "$1" '
    .[$a] as $c
    | ($c.mark // "•") as $m
    | (if $c.color then "\u001b[38;2;\($c.color)m\($m)\u001b[0m" else "\u001b[1m\($m)\u001b[0m" end)
      + " " + ($c.name // $a)'
}

# Fixed-width columns so the header lines up. jq counts characters, not bytes.
COLUMNS_JQ='def fit($w): if length > $w then .[0:$w - 1] + "…" elif length < $w then . + (" " * ($w - length)) else . end;'

row() { # when, agent, project, branch, title
  printf '%s' "$agent_table" | jq -r --arg when "$1" --arg a "$2" --arg project "$3" --arg branch "$4" --arg title "$5" "$COLUMNS_JQ"'
    .[$a] as $c
    | ($c.mark // "•" | fit(2)) as $m
    | (if $c.color then "\u001b[38;2;\($c.color)m\($m)\u001b[0m" else "\u001b[1m\($m)\u001b[0m" end) as $mark
    | [($when | fit(12)), $mark + " " + ($c.name // $a | fit(8)), ($project | fit(18)), ($branch | fit(14)), $title]
    | join("  ")'
}

header_row() {
  jq -rn "$COLUMNS_JQ"'[("WHEN" | fit(12)), ("AGENT" | fit(11)), ("PROJECT" | fit(18)), ("BRANCH" | fit(14)), "TITLE"] | join("  ")'
}

list() {
  live=$(for s in $(rex ls -q --short=false 2>/dev/null); do
    rex api call --session "$s" session.view 2>/dev/null | jq -r '.windows[].layers[].blocks[].block_id'
  done)
  # The newest conversation in each live pane is still open.
  open=$(cat "$agents"/*.json 2>/dev/null | jq -rs 'group_by(.block)[] | max_by(.at) | .session_id')
  for r in $(ls -1 "$agents"/*.json 2>/dev/null); do
    block=$(jq -r .block "$r"); id=$(jq -r .session_id "$r")
    if printf '%s\n' "$live" | grep -qx "$block" && printf '%s\n' "$open" | grep -qx "$id"; then continue; fi
    t=$(jq -r '.transcript_path // empty' "$r")
    # A transcript path with no file: the conversation never had a message.
    [ -n "$t" ] && [ ! -f "$t" ] && continue
    title=; branch=
    if [ -f "$t" ]; then
      title=$(jq -r 'select(.type == "ai-title") | .aiTitle' "$t" 2>/dev/null | tail -1)
      [ -n "$title" ] || title=$(first_prompt "$t" | tr -s '[:space:]' ' ' | cut -c1-70)
      branch=$(jq -r '.gitBranch // .payload.git.branch // empty' "$t" 2>/dev/null | tail -1)
      when=$(stat -f %m "$t")
    else
      when=$(jq -r '.at | fromdate' "$r" 2>/dev/null || stat -f %m "$r")
    fi
    [ -n "$branch" ] || branch=$(git -C "$(jq -r .cwd "$r")" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf '%s\t%s\t%s\n' "$when" "$r" "$(row "$(date -r "$when" '+%b %e %H:%M')" \
      "$(jq -r .agent "$r")" "$(basename "$(jq -r .cwd "$r")")" "${branch:--}" "${title:-untitled}")"
  done | sort -rn | cut -f2- > "${TMPDIR:-/tmp}/rex-archive-rows.$$"
  # The first line is the column header (fzf --header-lines 1).
  printf '\t%s\n' "$(header_row)"
  cat "${TMPDIR:-/tmp}/rex-archive-rows.$$"; rm -f "${TMPDIR:-/tmp}/rex-archive-rows.$$"
}

preview() {
  r=$1; t=$(jq -r '.transcript_path // empty' "$r")
  bold=$(printf '\033[1m'); dim=$(printf '\033[2m'); off=$(printf '\033[0m')
  printf '%s  %s\n' "$(mark "$(jq -r .agent "$r")")" "$(jq -r '.cwd | sub("^" + env.HOME; "~")' "$r")"
  if [ ! -f "$t" ]; then
    started=$(jq -r '.at | fromdate' "$r" 2>/dev/null)
    printf '%sStarted %s · %s%s\n\n' "$dim" "$(date -r "${started:-0}" '+%a %b %e, %H:%M')" "$(jq -r .session_id "$r")" "$off"
    echo "This agent doesn't provide a transcript to preview."
    return
  fi
  printf '%sLast active %s · %s%s\n\n' "$dim" "$(date -r "$(stat -f %m "$t")" '+%a %b %e, %H:%M')" "$(jq -r .session_id "$r")" "$off"
  printf '%sFirst prompt:%s\n' "$bold" "$off"
  first_prompt "$t"
  printf '\n%sLast reply:%s\n' "$bold" "$off"
  last_reply "$t"
}

case "${1:-}" in
  --list) list; exit ;;
  --preview) preview "$2"; exit ;;
esac

header='Enter: resume in a new tab   Ctrl-D: remove from list'
problem="$(dirname "$agents")/hook-problem"
[ -f "$problem" ] && header="$header
Warning: $(cat "$problem")"

out=$(list | fzf --ansi --delimiter '\t' --with-nth 2.. --prompt 'archive> ' \
  --layout reverse --header "$header" --header-lines 1 \
  --preview "sh '$self' --preview {1}" --preview-window 'down,60%,wrap' \
  --bind "ctrl-d:execute-silent(rm -f {1})+reload(sh '$self' --list)") || exit 0
r=$(printf '%s' "$out" | cut -f1)
[ -n "$r" ] && rex do "$here/restore.lua" record="$r" >/dev/null
exit 0
