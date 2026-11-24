-- Archived Agent Sessions for Rex. Load it from your init.lua with
--   require("archive")
-- An agent conversation is archived once its pane closes. The hook in each
-- agent's settings (agent-hook.sh, hook.lua) records conversations in
-- ~/.local/share/rex-archive/agents.
local dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/archive"

local data = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/rex-archive/agents"

local function decode(text)
  local ok, value = pcall(rex.json.decode, text)
  if ok then return value end
end

local function read_json(path)
  local f = io.open(path)
  if not f then return nil end
  local value = decode(f:read("*a"))
  f:close()
  return value
end

-- Per-agent settings: agents.json, with agents.local.json (if any) on top.
local function load_agents()
  local agents = read_json(dir .. "/agents.json") or {}
  for name, settings in pairs(read_json(dir .. "/agents.local.json") or {}) do
    agents[name] = settings
  end
  return agents
end

-- Modified times, as { [path] = seconds }. Lua can't stat files, so this is
-- one `stat` call for all of them.
local function mtimes(paths)
  local times = {}
  if #paths == 0 then return times end
  local argv = { "stat", "-f", "%m %N" }
  for _, p in ipairs(paths) do argv[#argv + 1] = p end
  local r = rex.exec(argv)
  for t, p in ((r and r.stdout) or ""):gmatch("(%d+) ([^\n]+)") do times[p] = tonumber(t) end
  return times
end

-- Record files in the agents folder.
local function record_paths()
  local r = rex.exec({ "find", data, "-maxdepth", "1", "-name", "*.json" })
  local paths = {}
  for p in ((r and r.stdout) or ""):gmatch("[^\n]+") do paths[#paths + 1] = p end
  return paths
end

-- Every pane (block) that still exists in any session, as a set. Reading
-- another session's blocks needs this connection attached to it.
local function live_blocks()
  local live = {}
  local all, err = rex.call("session.attach_all", { event_scope = "session" })
  if not all then rex.log("warn", "archive: can't list sessions: " .. tostring(err)) end
  for _, s in ipairs((all or {}).sessions or {}) do
    local r, e = rex.call("session.list_blocks", { session_id = s.session_id })
    if not r then rex.log("warn", "archive: can't list blocks of " .. s.session_id .. ": " .. tostring(e)) end
    for _, b in ipairs((r or {}).blocks or {}) do live[b.block_id] = true end
  end
  return live
end

-- A message's text from either transcript format (Claude Code or Codex), or
-- nil. Skips injected context, which starts with "<" or is marked as meta.
local function message(entry, want_role)
  local role, text
  if entry.type == "user" or entry.type == "assistant" then
    if entry.isMeta then return nil end
    role = entry.type
    local content = entry.message and entry.message.content
    if type(content) == "string" then
      text = content
    elseif type(content) == "table" then
      local parts = {}
      for _, c in ipairs(content) do
        if c.type == "text" and c.text then parts[#parts + 1] = c.text end
      end
      text = table.concat(parts, "\n\n")
    end
  elseif entry.type == "response_item" and entry.payload and entry.payload.type == "message" then
    role = entry.payload.role
    local parts = {}
    for _, c in ipairs(entry.payload.content or {}) do
      if c.text then parts[#parts + 1] = c.text end
    end
    text = table.concat(parts, "\n\n")
  end
  if role ~= want_role or not text or text == "" then return nil end
  if text:match("^%s*<") or text:match("^%s*# AGENTS%.md") then return nil end
  return text
end

-- Title and branch from a transcript, in one pass. The title is the agent's
-- own (Claude's ai-title), otherwise the first user message. Lines are only
-- decoded when a plain search says they might matter; transcripts get big.
local function summarize(path)
  local f = io.open(path)
  if not f then return nil end
  local title, prompt, branch
  for line in f:lines() do
    if line:find('"ai-title"', 1, true) then
      local e = decode(line)
      if e and e.type == "ai-title" and e.aiTitle then title = e.aiTitle end
    end
    if not prompt and line:find('"user"', 1, true) then
      local e = decode(line)
      if e then prompt = message(e, "user") end
    end
    local b = line:match('"gitBranch":"([^"]*)"') or (line:find('"git"', 1, true) and line:match('"branch":"([^"]*)"'))
    if b and b ~= "" then branch = b end
  end
  f:close()
  if not title and prompt then title = prompt:gsub("%s+", " "):sub(1, 70) end
  return title, branch
end

-- Archived conversations as rex.ui.pick items, newest first: ones whose pane
-- has closed, or that a newer conversation replaced in the same pane.
local function archived_items()
  local agents = load_agents()
  local live = live_blocks()
  local records, paths = {}, record_paths()
  for _, p in ipairs(paths) do
    local rec = read_json(p)
    if rec and rec.session_id then rec.path = p; records[#records + 1] = rec end
  end

  -- The newest conversation in each live pane is still open.
  local newest = {}
  for _, rec in ipairs(records) do
    local n = newest[rec.block]
    if not n or (rec.at or "") > (n.at or "") then newest[rec.block] = rec end
  end

  local stat_paths = {}
  for _, p in ipairs(paths) do stat_paths[#stat_paths + 1] = p end
  for _, rec in ipairs(records) do
    if rec.transcript_path then stat_paths[#stat_paths + 1] = rec.transcript_path end
  end
  local times = mtimes(stat_paths)

  local rows = {}
  for _, rec in ipairs(records) do
    local open = live[rec.block] and newest[rec.block] == rec
    local t = rec.transcript_path
    -- A transcript path with no file: the conversation never had a message.
    local missing = t and not times[t]
    if not open and not missing then
      local title, branch
      if t then title, branch = summarize(t) end
      if not branch and rec.cwd then
        local r = rex.exec({ "git", "-C", rec.cwd, "rev-parse", "--abbrev-ref", "HEAD" })
        if r and r.ok then branch = r.stdout:gsub("%s+$", "") end
      end
      local when = (t and times[t]) or times[rec.path] or 0
      local agent = agents[rec.agent] or {}
      local project = (rec.cwd or ""):match("([^/]+)/*$") or "?"
      rows[#rows + 1] = { when = when, item = {
        id       = rec.path,
        title    = title or "untitled",
        subtitle = ("%s · %s · %s"):format(agent.name or rec.agent or "?", project, branch or "-"),
        icon     = "terminal",
        detail   = (os.date("%b %d %H:%M", when):gsub(" 0", " ", 1)),
      } }
    end
  end
  table.sort(rows, function(a, b) return a.when > b.when end)
  local items = {}
  for i, row in ipairs(rows) do items[i] = row.item end
  return items
end

-- Open an archived conversation in a new tab of the current session, in the
-- directory it ran in. The resume command comes from agents.json
-- (agents.local.json overrides it), with {id} replaced by the conversation ID.
local function resume(record_path)
  local rec = read_json(record_path)
  if not rec then error("can't read " .. record_path) end
  local agent = load_agents()[rec.agent] or {}
  local input
  if agent.resume then
    input = agent.resume:gsub("{id}", rec.session_id) .. "\n"
  else
    input = ("echo 'No resume command for %s. Add one to %s/agents.local.json.'\n"):format(rec.agent, dir)
  end
  local r, err = rex.session.new_window{
    window_label = agent.name or rec.agent,
    focus        = true,
    layout       = rex.layout.block{
      flavor  = "com.superlogical.terminal.shell",
      options = { cwd = rec.cwd, initial_input = input },
    },
  }
  if not r then error(err) end
end

-- Pick from the archive; returns the answer, or nil if there was none.
local function ask(opts)
  if not (rex.ui and rex.ui.pick) then
    error("Archived Agent Sessions needs a newer Rex server (control API revision 17). "
      .. "Update Rex and restart its server.", 0)
  end
  local items = archived_items()
  if #items == 0 then
    rex.log("info", "archive: no archived agent sessions")
    return nil
  end
  opts.items = items
  local answer, why, detail = rex.ui.pick(opts)
  if answer == nil and why ~= "cancelled" then
    rex.log("warn", "archive: " .. tostring(why) .. " " .. (detail or ""))
  end
  return answer
end

rex.action{
  name  = "archived_sessions",
  title = "Archived Agent Sessions",
  description = "Browse agent conversations whose tabs were closed, and resume one in a new tab.",
  run   = function(ctx, args)
    local record = ask{
      title       = "Archived Agent Sessions",
      placeholder = "Filter by title, agent, project or branch",
    }
    if record then resume(record) end
  end,
}

rex.action{
  name  = "remove_archived_sessions",
  title = "Remove Archived Agent Sessions…",
  description = "Remove agent conversations from the archive list. Transcripts are kept.",
  run   = function(ctx, args)
    local records = ask{
      title       = "Remove from archive",
      placeholder = "Filter archived sessions",
      multiple    = true,
      confirm     = "Remove",
    }
    for _, path in ipairs(records or {}) do os.remove(path) end
  end,
}

rex.action{
  name  = "check_archive_setup",
  title = "Check Agent Archive Setup",
  description = "Check the Rex server, agent hooks and config that Archived Agent Sessions needs.",
  run   = function(ctx, args)
    local check = dofile(dir .. "/check.lua")
    local results = check.run()
    local n = check.problems(results)
    if not (rex.ui and rex.ui.pick) then
      local lines = {}
      for _, r in ipairs(results) do
        if r.status == "missing" then lines[#lines + 1] = r.text end
      end
      error(table.concat(lines, " "), 0)
    end
    local items = {}
    for i, r in ipairs(results) do
      items[i] = { id = tostring(i), title = r.text, detail = r.status }
    end
    rex.ui.pick{
      title       = n == 0 and "Everything is in place" or ("%d problem(s) found"):format(n),
      placeholder = "Agent archive setup",
      confirm     = "Close",
      items       = items,
    }
  end,
}
