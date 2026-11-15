-- Queb: shared helpers.
-- Every file receives the same private namespace table `ns` from the TOC loader.
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.PREFIX = "Queb"   -- addon message prefix (<= 16 chars)
ns.PROTOCOL = 1          -- bump when the wire format changes incompatibly

do
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  ns.VERSION = (getMeta and getMeta(addonName, "Version")) or "dev"
end

---------------------------------------------------------------------------
-- Secret values (Midnight). Never compare, branch on, or format a secret.
---------------------------------------------------------------------------
function ns.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
-- Native look: Queb messages look like Blizzard system messages (system
-- chat color, short "Queb:" prefix). Sub-lines use the same color.
local TAG = "Queb: "

local function ToText(v)
  if ns.IsSecret(v) then return "<secret>" end
  return tostring(v)
end

local function SystemColor()
  local info = ChatTypeInfo and ChatTypeInfo.SYSTEM
  if info and info.r then return info.r, info.g, info.b end
  return 1, 1, 0
end

function ns.PrintLine(text)
  DEFAULT_CHAT_FRAME:AddMessage(text, SystemColor())
end

function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = ToText((select(i, ...)))
  end
  ns.PrintLine(TAG .. table.concat(parts, " "))
end

function ns.Debug(...)
  if ns.db and ns.db.debug then
    ns.Print("[debug]", ...)
  end
end

---------------------------------------------------------------------------
-- Timers: Coalesce runs fn once, `delay` seconds after the FIRST request in
-- a burst (never starves under constant events). Debounce restarts the timer
-- on every request (runs after things go quiet).
---------------------------------------------------------------------------
local pending = {}
function ns.Coalesce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    fn()
  end)
end

local timers = {}
function ns.Debounce(key, delay, fn)
  if timers[key] then timers[key]:Cancel() end
  timers[key] = C_Timer.NewTimer(delay, function()
    timers[key] = nil
    fn()
  end)
end

---------------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------------
-- Plain (non-pattern) split. Keeps empty fields.
function ns.Split(str, sep)
  local out = {}
  if str == nil or str == "" then return out end
  local start = 1
  while true do
    local i = string.find(str, sep, start, true)
    if not i then
      out[#out + 1] = string.sub(str, start)
      break
    end
    out[#out + 1] = string.sub(str, start, i - 1)
    start = i + #sep
  end
  return out
end

-- djb2, kept in 32 bits with arithmetic (Lua 5.1 has no bitwise operators;
-- h*33+255 < 2^53 so doubles stay exact).
function ns.Hash(str)
  local h = 5381
  for i = 1, #str do
    h = (h * 33 + string.byte(str, i)) % 4294967296
  end
  return string.format("%08x", h)
end

---------------------------------------------------------------------------
-- Names. Forever is realmless and uses two-part names that contain a space:
-- never split on spaces, never strip anything except surrounding whitespace.
---------------------------------------------------------------------------
function ns.NormalizeName(name)
  if name == nil or ns.IsSecret(name) or type(name) ~= "string" then return nil end
  name = string.match(name, "^%s*(.-)%s*$")
  if name == "" then return nil end
  return name
end

-- Every spelling of a name we might see (sender format is not yet verified
-- on Forever, so we match loosely).
function ns.NameVariants(name)
  local out = { name }
  if Ambiguate then
    local ok, a = pcall(Ambiguate, name, "none")
    if ok and a and not ns.IsSecret(a) and a ~= name then out[#out + 1] = a end
  end
  local base = string.match(name, "^(.-)%-[^%-%s]+$") -- "Name-Realm" style, if any
  if base and base ~= "" then out[#out + 1] = base end
  return out
end

function ns.UnitKey(unit)
  local name
  if GetUnitName then name = GetUnitName(unit, true) end
  if not name or ns.IsSecret(name) then name = UnitName(unit) end
  return ns.NormalizeName(name)
end

function ns.BuildPlayerNames()
  local set = {}
  local function add(n)
    n = ns.NormalizeName(n)
    if n then
      for _, v in ipairs(ns.NameVariants(n)) do set[v] = true end
    end
  end
  add(GetUnitName and GetUnitName("player", true))
  local n, r = UnitName("player")
  add(n)
  if n and r and r ~= "" and not ns.IsSecret(r) and not ns.IsSecret(n) then add(n .. "-" .. r) end
  if UnitFullName then
    local a, b = UnitFullName("player")
    add(a)
    if a and b and b ~= "" and not ns.IsSecret(a) and not ns.IsSecret(b) then add(a .. "-" .. b) end
  end
  ns.playerNames = set
end

function ns.IsMe(name)
  if not ns.playerNames then ns.BuildPlayerNames() end
  if ns.playerNames[name] then return true end
  for _, v in ipairs(ns.NameVariants(name)) do
    if ns.playerNames[v] then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Group helpers
---------------------------------------------------------------------------
function ns.GetGroupChannel()
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

function ns.GroupUnits()
  local units = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end

---------------------------------------------------------------------------
-- Quest entry wire format:  questID,complete,f/r,f/r,...
--   complete: "1" or "0";  "-" in that slot means "quest removed".
---------------------------------------------------------------------------
local MAX_OBJECTIVES = 20
local MAX_COUNT = 100000

function ns.EncodeEntry(questID, q)
  local parts = { tostring(questID), q.c and "1" or "0" }
  for _, o in ipairs(q.obj) do
    parts[#parts + 1] = o[1] .. "/" .. o[2]
  end
  return table.concat(parts, ",")
end

-- Returns questID, questTable  |  questID, false (removed)  |  nil (invalid)
function ns.DecodeEntry(entry)
  local fields = ns.Split(entry, ",")
  local qid = tonumber(fields[1])
  if not qid or qid <= 0 or qid > 10000000 or qid ~= math.floor(qid) then return nil end
  if fields[2] == "-" then return qid, false end
  if fields[2] ~= "0" and fields[2] ~= "1" then return nil end
  local q = { c = fields[2] == "1", obj = {} }
  for i = 3, math.min(#fields, 2 + MAX_OBJECTIVES) do
    local f, r = string.match(fields[i], "^(%d+)/(%d+)$")
    f, r = tonumber(f), tonumber(r)
    if not f or not r or r > MAX_COUNT then return nil end
    if f > r then f = r end
    q.obj[#q.obj + 1] = { f, r }
  end
  return qid, q
end

-- Hash over a { [questID] = entryString } map, order-independent.
function ns.HashEntries(entries)
  local ids = {}
  for qid in pairs(entries) do ids[#ids + 1] = qid end
  table.sort(ids)
  local parts = {}
  for i, qid in ipairs(ids) do parts[i] = entries[qid] end
  return ns.Hash(table.concat(parts, ";"))
end

---------------------------------------------------------------------------
-- "Can share" wire part:  !questID:level:title
--   Sent next to quest entries in ST/QU for quests the game lets the sender
--   share (C_QuestLog.IsPushableQuest). Older Queb builds skip these parts
--   (DecodeEntry rejects them), so no protocol bump is needed. Not hashed.
---------------------------------------------------------------------------
local MAX_TITLE = 60

-- Title safe for the wire: no separators or escape codes, bounded length.
function ns.CleanTitle(title)
  if type(title) ~= "string" or ns.IsSecret(title) then return "" end
  title = string.gsub(title, "[;|%c]", " ")
  title = string.match(title, "^%s*(.-)%s*$") or ""
  if #title > MAX_TITLE then
    title = string.sub(title, 1, MAX_TITLE)
    title = string.gsub(title, "[\192-\255][\128-\191]*$", "") -- no cut UTF-8 character
  end
  return title
end

function ns.EncodeShare(questID, level, title)
  return "!" .. questID .. ":" .. (tonumber(level) or 0) .. ":" .. ns.CleanTitle(title)
end

-- Returns questID, { lvl, title }  |  nil (not a share part / invalid)
function ns.DecodeShare(part)
  local qid, lvl, title = string.match(part or "", "^!(%d+):(%d+):(.*)$")
  qid, lvl = tonumber(qid), tonumber(lvl)
  if not qid or qid <= 0 or qid > 10000000 or not lvl or lvl > 200 then return nil end
  title = ns.CleanTitle(title)
  return qid, { lvl = lvl > 0 and lvl or nil, title = title ~= "" and title or nil }
end
