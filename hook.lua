-- Writes the record for one agent conversation: which Rex pane it runs in,
-- its folder and its transcript. agent-hook.sh runs it with the agent's hook
-- payload:
--   rex do hook.lua agent= block= session= pwd= dir= payload=
local a = rex.args
-- rex do turns a JSON value into a table; take a string too, just in case.
local payload = a.payload
if type(payload) == "string" then payload = rex.json.decode(payload) end
if type(payload) ~= "table" then return end

local id = payload.session_id
if type(id) ~= "string" or id == "" or id:find("/", 1, true) then return end

local record = rex.json.encode{
  agent           = a.agent,
  block           = a.block,
  rex_session     = a.session,
  session_id      = id,
  cwd             = payload.cwd or a.pwd,
  transcript_path = payload.transcript_path,
  at              = os.date("!%Y-%m-%dT%H:%M:%SZ"),
}
local f = assert(io.open(a.dir .. "/" .. id .. ".json", "w"))
f:write(record, "\n")
f:close()
