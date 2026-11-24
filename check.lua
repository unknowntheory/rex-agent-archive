-- Checks what Archived Agent Sessions needs: a new enough Rex server, the
-- agent hooks, the agents' resume commands, and the require line in the Rex
-- config. init.lua shows the results in the palette; from a terminal:
--   rex do ~/.config/rex/archive/check.lua
local home = os.getenv("HOME")
local conf = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/rex"
local data = (os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/rex-archive"
local dir = conf .. "/archive"
local MIN_REVISION = 17

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function read_json(path)
  local text = read(path)
  if not text then return nil end
  local ok, value = pcall(rex.json.decode, text)
  if ok then return value end
end

-- Whether a command exists in the user's login shell, where agents run.
local function installed(cmd)
  local shell = os.getenv("SHELL") or "/bin/zsh"
  local r = rex.exec({ shell, "-lc", 'command -v "$1"', "_", cmd })
  return r and r.ok
end

-- A list of { status = "ok" | "missing" | "note", text = "..." }.
local function run()
  local results = {}
  local function add(status, text) results[#results + 1] = { status = status, text = text } end

  local status = rex.call("server.status")
  local rev = status and status.api_revision
  if not rev then
    add("missing", "Can't reach the Rex server")
  elseif rev >= MIN_REVISION then
    add("ok", "Rex server: control API revision " .. rev)
  else
    add("missing", ("Rex server: control API revision %d, needs %d. Update Rex and restart its server.")
      :format(rev, MIN_REVISION))
  end

  for _, hook in ipairs{
    { name = "Claude Code", file = home .. "/.claude/settings.json" },
    { name = "Codex", file = home .. "/.codex/hooks.json" },
  } do
    local text = read(hook.file)
    if not text then
      add("note", hook.name .. ": not set up, skipped")
    elseif text:find("archive/agent-hook.sh", 1, true) then
      add("ok", hook.name .. ": hook registered")
      if hook.name == "Codex" then add("note", "Codex: approve the hook with /hooks inside Codex if you haven't") end
    else
      add("missing", hook.name .. ": hook not registered. Run install.sh.")
    end
  end
  local problem = read(data .. "/hook-problem")
  if problem then add("missing", (problem:gsub("%s+$", ""))) end

  local agents = read_json(dir .. "/agents.json") or {}
  for name, settings in pairs(read_json(dir .. "/agents.local.json") or {}) do agents[name] = settings end
  local names = {}
  for name in pairs(agents) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local label = agents[name].name or name
    local resume = agents[name].resume
    local cmd = resume and resume:match("^%S+")
    if not cmd then
      add("note", label .. ": no resume command")
    elseif installed(cmd) then
      add("ok", label .. ": resumes with " .. cmd)
    else
      add("note", label .. ": " .. cmd .. " not installed")
    end
  end

  local init = read(conf .. "/init.lua") or ""
  if init:find('require[%s%(,]*["\']archive["\']') then
    add("ok", 'Rex config: init.lua has require("archive")')
  else
    add("missing", 'Rex config: add require("archive") to ' .. conf .. "/init.lua, then run rex config reload")
  end
  return results
end

local function problems(results)
  local n = 0
  for _, r in ipairs(results) do if r.status == "missing" then n = n + 1 end end
  return n
end

-- Run as a script: print the report, and exit 1 if anything is missing.
if rex.args then
  local results = run()
  local labels = { ok = "ok   ", missing = "MISS ", note = "note " }
  print("Archived Agent Sessions setup\n")
  for _, r in ipairs(results) do print("  " .. labels[r.status] .. r.text) end
  local n = problems(results)
  print(n == 0 and "\nEverything is in place." or ("\n%d problem(s) found."):format(n))
  if n > 0 then rex.stop(1) end
  return
end

return { run = run, problems = problems }
