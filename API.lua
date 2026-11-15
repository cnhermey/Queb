-- Queb: small public API so replacement quest trackers can show
-- our data too.
--
--   local sharers = Queb.GetSharers(questID)
--     -> array of { name, class, source ("guild"|"group"|...), hasAddon,
--                   complete, objectives = { {fulfilled, required}, ... } }
--     (complete/objectives are nil when unknown — don't guess)
--
--   Queb.RegisterCallback(owner, function() ... end)
--     -> called (coalesced) whenever shared-quest data changes
--   Queb.UnregisterCallback(owner)
local _, ns = ...

local API = {}
Queb = API

local callbacks = {}

local function CopyObjectives(obj)
  if not obj then return nil end
  local out = {}
  for i, o in ipairs(obj) do out[i] = { o[1], o[2] } end
  return out
end

function API.GetVersion()
  return ns.VERSION
end

function API.GetSharers(questID)
  local out = {}
  if type(questID) ~= "number" or not ns.db then return out end
  for i, s in ipairs(ns.Peers:GetSharers(questID)) do
    out[i] = {
      name = s.name, class = s.class, source = s.source, hasAddon = s.hasAddon,
      complete = s.complete, objectives = CopyObjectives(s.objectives),
    }
  end
  return out
end

function API.RegisterCallback(owner, fn)
  if owner ~= nil and type(fn) == "function" then callbacks[owner] = fn end
end

function API.UnregisterCallback(owner)
  if owner ~= nil then callbacks[owner] = nil end
end

ns.Listen("PEERS_CHANGED", function()
  for _, fn in pairs(callbacks) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
end)
