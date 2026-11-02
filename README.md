# Archived Agent Sessions for Rex

Close a coding agent's tab in [Rex](https://www.superlogical.com/rex) and the
conversation is archived. Claude Code and Codex work out of the box; other
agents can be added (see below)[^1]. Browse archived conversations from the
command palette and resume one in a new tab, in the folder it ran in.

https://github.com/user-attachments/assets/42ebecd8-d8ed-4ef0-a34f-4c6804cc6ee9

## Install

```sh
git clone https://github.com/unknowntheory/rex-agent-archive.git /tmp/rex-agent-archive
sh /tmp/rex-agent-archive/install.sh
```

Requires Rex, `fzf` and `jq` (`brew install fzf jq`).

`install.sh` copies this folder to `~/.config/rex/archive`, adds
`require("archive")` to `~/.config/rex/init.lua`, registers a SessionStart hook
for Claude Code and Codex (backing up their settings first), and reloads Rex.
In Codex, you will have to approve the new hook with `/hooks`.

`sh install.sh --link` symlinks `~/.config/rex/archive` to the clone instead
of copying it, so edits in the clone are live. Use it if you're changing the
code. Your own `agents.local.json` is ignored by git.

## Use

Command palette → **Archived Agent Sessions**

- Each row: last active time, agent, project, branch, title (Claude's own
  title, otherwise your first message).
- The preview shows your first prompt and the agent's last replies.
- `Enter` resumes it in a new tab of the current session, using the agent's
  `resume` command from `agents.json`. `Ctrl-D` removes it from the list; the transcript is kept.


**Check Agent Archive Setup** in the palette (or `sh check.sh`) reports any
missing command, hook or config line.

## Adding an agent

Two steps, for any agent that can run a command when a conversation starts and
pass it JSON with a `session_id`:

1. **Hook.** Have the agent run this at session start, with its hook payload on
   stdin (use the agent's name in place of `myagent`):

   ```sh
   /bin/sh -c '"$HOME/.config/rex/archive/agent-hook.sh" myagent 2>/dev/null || true'
   ```

   `cwd` and `transcript_path` in the payload are used when present. Without a
   `cwd` the pane's directory is recorded.

2. **Settings.** Add the agent to `agents.local.json` next to `agents.json`
   (it overrides `agents.json` and survives reinstalls):

   ```json
   {
     "myagent": {
       "name": "My Agent",
       "mark": "◆",
       "color": "120;180;250",
       "resume": "myagent --resume {id}"
     }
   }
   ```

   `{id}` is replaced with the conversation ID. `color` is optional
   (`R;G;B`). Without a `resume` command the tab opens in the right folder and
   says so.

Previews read Claude Code's and Codex's transcript formats. Other agents are
still listed and resumable, without a title or preview unless their transcript
uses one of those formats.

## How it works

The hook records, at the start of each agent conversation, which Rex pane it is
running in (`~/.local/share/rex-archive/agents/<id>.json`). A conversation is
archived when that pane no longer exists (tab closed, session killed, Rex
restarted) or a newer conversation started in the same pane. Nothing runs in
the background. Titles and previews come from the agent's own transcript.

Only conversations started after installing are recorded.

## Files

| File | Does |
| --- | --- |
| `init.lua` | The palette actions |
| `agents.json` | Name, mark, color and resume command per agent |
| `agent-hook.sh` | SessionStart hook; records conversation → pane |
| `browse.sh` | The fzf browser |
| `restore.lua` | Opens the resume tab (`rex do`) |
| `check.sh` | Setup check |
| `deps.sh` | Missing-command message for the popups |
| `install.sh` | Installer |

This was only tested with claude code and codex[^1]
