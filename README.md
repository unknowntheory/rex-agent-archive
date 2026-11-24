# Archived Agent Sessions for Rex

Close a coding agent's tab in [Rex](https://www.superlogical.com/rex) and the
conversation is archived. Browse archived conversations from the command
palette and resume one in a new tab, in the folder it ran in.

Claude Code and Codex work out of the box. Other agents can be added (see
[Adding an agent](#adding-an-agent)).

## Requirements

- **macOS.** Other platforms aren't supported.
- **Rex** with a server at control API revision 17 or newer, which is what the
  palette picker needs. Check with `rex api call server.status`. If it's
  older, update Rex and restart its server.

Nothing else: no jq, fzf or other tools to install.

## Install

Run this from a Rex terminal:

```sh
git clone https://github.com/unknowntheory/rex-agent-archive.git /tmp/rex-agent-archive
sh /tmp/rex-agent-archive/install.sh
```

`install.sh`:

1. copies this folder to `~/.config/rex/archive`
2. adds `require("archive")` to `~/.config/rex/init.lua`
3. registers a SessionStart hook for Claude Code (`~/.claude/settings.json`)
   and Codex (`~/.codex/hooks.json`), backing each file up first
4. reloads the Rex config and checks the setup

In Codex, approve the new hook with `/hooks`.

Only conversations started after installing are recorded.

`sh install.sh --link` symlinks `~/.config/rex/archive` to the clone instead
of copying it, so edits in the clone are live. Use it if you're changing the
code.

## Use

All from the command palette:

- **Archived Agent Sessions** lists archived conversations, newest first. Each
  row shows the title (Claude's own title, otherwise your first message), the
  agent, project and branch, and when it was last active. Type to filter.
  `Enter` resumes it in a new tab of the current session.
- **Remove Archived Agent Sessions…** lets you tick conversations to remove
  from the list. Their transcripts are kept.
- **Check Agent Archive Setup** reports anything missing: an old Rex server, an
  unregistered hook, a missing `require` line. From a terminal:
  `rex do ~/.config/rex/archive/check.lua`.

## Adding an agent

Any agent that can run a command when a conversation starts, and pass it JSON
with a `session_id`, can be added in two steps:

1. **Hook.** Have the agent run this at session start, with its hook payload on
   stdin (use the agent's name in place of `myagent`):

   ```sh
   /bin/sh -c '"$HOME/.config/rex/archive/agent-hook.sh" myagent 2>/dev/null || true'
   ```

   `cwd` and `transcript_path` in the payload are used when present. Without a
   `cwd`, the pane's directory is recorded.

2. **Settings.** Add the agent to `agents.local.json` next to `agents.json`. It
   overrides `agents.json`, survives reinstalls and is ignored by git:

   ```json
   {
     "myagent": {
       "name": "My Agent",
       "resume": "myagent --resume {id}"
     }
   }
   ```

   `{id}` is replaced with the conversation ID. Without a `resume` command the
   tab opens in the right folder and says so.

Titles are read from Claude Code's and Codex's transcript formats. Other agents
are listed as "untitled" unless their transcript uses one of those formats.

## How it works

The hook records, at the start of each agent conversation, which Rex pane it
is running in (`~/.local/share/rex-archive/agents/<id>.json`). A conversation
is archived when that pane no longer exists (tab closed, session killed, Rex
restarted) or a newer conversation started in the same pane. Nothing runs in
the background. Titles and branches come from the agent's own transcript.

## Files

| File | Does |
| --- | --- |
| `init.lua` | The palette actions: listing, resuming and removing |
| `check.lua` | Setup check, for the palette action and `rex do` |
| `agents.json` | Name and resume command per agent |
| `agent-hook.sh` | SessionStart hook; hands the payload to `hook.lua` |
| `hook.lua` | Records which conversation runs in which pane |
| `install.sh` | Installer |

## Uninstall

1. Remove the `require("archive")` line from `~/.config/rex/init.lua`, then run
   `rex config reload`.
2. Remove the `archive/agent-hook.sh` hook from `~/.claude/settings.json` and
   `~/.codex/hooks.json`.
3. Delete `~/.config/rex/archive` and `~/.local/share/rex-archive`.

## Limitations

- macOS only.
- Only tested with Claude Code and Codex.
- Conversations started before installing aren't recorded.
