-- Archived Agent Sessions for Rex. Load it from your init.lua with
--   require("archive")
-- An agent (only tested with codex and claude code) conversation is archived once its pane closes; the
-- hook in each agent's settings records conversations in
-- ~/.local/share/rex-archive/agents.
local dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/archive"

local function popup(bounds, script)
  rex.session.new_layer{
    bounds = bounds,
    focus  = true,
    layout = rex.layout.block{
      flavor  = "com.superlogical.terminal.shell",
      options = { command = { "sh", dir .. "/" .. script }, exit = { on_completion = true } },
    },
  }
end

rex.action{
  name  = "archived_sessions",
  title = "Archived Agent Sessions",
  description = "Browse agent conversations whose tabs were closed, and resume one in a new tab.",
  run   = function(ctx, args) popup({ 0.1, 0.1, 0.8, 0.8 }, "browse.sh") end,
}

rex.action{
  name  = "check_archive_setup",
  title = "Check Agent Archive Setup",
  description = "Check the commands, agent hooks and config that Archived Agent Sessions needs.",
  run   = function(ctx, args) popup({ 0.2, 0.15, 0.6, 0.7 }, "check.sh") end,
}
