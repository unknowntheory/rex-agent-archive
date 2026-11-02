-- Resume an archived agent conversation in a new tab of the current session,
-- in the directory it ran in. The resume command comes from agents.json
-- (agents.local.json overrides it), with {id} replaced by the conversation ID.
-- Usage: rex do restore.lua record=/path/to/agents/<id>.json
local function read_json(path)
  local f = io.open(path)
  if not f then return nil end
  local value = rex.json.decode(f:read("*a"))
  f:close()
  return value
end

local record_path = assert(rex.args.record, "pass record=")
local rec = assert(read_json(record_path), "can't read " .. record_path)

local dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/archive"
local agents = read_json(dir .. "/agents.json") or {}
for name, settings in pairs(read_json(dir .. "/agents.local.json") or {}) do
  agents[name] = settings
end

local agent = agents[rec.agent] or {}
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
return r
