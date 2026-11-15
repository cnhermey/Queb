-- Queb: unit tooltips, wherever the game shows one (unit frames, party and
-- raid frames, nameplates, players and NPCs in the world).
--
--   * Player you're grouped with, or anyone Queb has heard from (guild or
--     party sync): the same "Queb: N shared quests" lines as the guild
--     tooltip (GuildUI:WriteLines), or the short reason when unknown.
--     Players Queb knows nothing about get no lines (no noise in cities).
--   * Quest mob / NPC: Blizzard lists your quest under its name. If anyone
--     else (guildmate or group member) is on that quest, one line names them
--     with their class circles.
--
-- Hook: TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit)
-- (Mainline); fallback HookScript("OnTooltipSetUnit") for older clients.
-- Post-call only; every game value is checked for secrets first.
local _, ns = ...
local UI = ns.UI

local U = { hook = "none" }
ns.UnitUI = U

local MAX_QUESTS = 3
local MAX_NAMES = 4

local function Str(v)
  if type(v) == "string" and v ~= "" and not ns.IsSecret(v) then return v end
end

local function Bool(v)
  if v == nil or ns.IsSecret(v) then return nil end
  return v and true or false
end

local function SafeCall(fn, ...)
  if not fn then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
end

local function UnitOf(tooltip, data)
  local _, unit = SafeCall(tooltip.GetUnit, tooltip)
  unit = Str(unit)
  if unit then return unit end
  local guid = data and Str(data.guid)
  if guid and UnitTokenFromGUID then return Str(SafeCall(UnitTokenFromGUID, guid)) end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
local function AddPlayerLines(tooltip, unit)
  if not ns.db.showOnPlayers then return false end
  if Bool(SafeCall(UnitIsUnit, unit, "player")) then return false end
  local name = ns.UnitKey(unit)
  if not name or ns.IsMe(name) then return false end
  -- only people we can say something useful about
  local P = ns.Peers
  if not (P:FindRosterUnit(name) or P:FindPeer(name)) then return false end
  local _, classFile = SafeCall(UnitClass, unit)
  classFile = Str(classFile)
  local online = Bool(SafeCall(UnitIsConnected, unit))
  return ns.GuildUI:WriteLines(tooltip, name, classFile, online)
end

---------------------------------------------------------------------------
-- Quest mobs / NPCs: which of your quests does this tooltip mention?
---------------------------------------------------------------------------
local function TitleIndex()
  local t = {}
  for qid, q in pairs(ns.QuestState.quests) do
    if q.title then t[q.title] = qid end
  end
  return t
end

local function Clean(text)
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  return (string.match(text, "^%s*(.-)%s*$"))
end

local function QuestsInTooltip(tooltip, data)
  local titles = TitleIndex()
  if not next(titles) then return {} end
  local found, seen = {}, {}
  local function add(qid)
    if qid and not seen[qid] and ns.QuestState.quests[qid] then
      seen[qid] = true
      found[#found + 1] = qid
    end
  end
  local QT = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
  if data and type(data.lines) == "table" then
    for _, line in ipairs(data.lines) do
      if type(line) == "table" then
        local id = line.id
        if QT and line.type == QT and type(id) == "number" and not ns.IsSecret(id) then add(id) end
        local text = Str(line.leftText)
        if text then add(titles[Clean(text)]) end
      end
    end
  else
    local tname = tooltip.GetName and tooltip:GetName()
    for i = 2, (tooltip.NumLines and tooltip:NumLines() or 0) do
      local fs = tname and _G[tname .. "TextLeft" .. i]
      local text = fs and Str(fs:GetText())
      if text then add(titles[Clean(text)]) end
    end
  end
  return found
end

local function NamesText(sharers)
  local parts = {}
  for i = 1, math.min(#sharers, MAX_NAMES) do
    local s = sharers[i]
    parts[i] = UI:CircleIcon(s.class, 10) .. " " .. UI.ColorName(s.name, s.class)
  end
  local text = table.concat(parts, "  ")
  if #sharers > MAX_NAMES then text = text .. UI.Wrap(UI.GRAY, string.format(" +%d", #sharers - MAX_NAMES)) end
  return text
end

local function AddQuestUnitLines(tooltip, data)
  if not ns.db.showOnQuestUnits then return false end
  local rows = {}
  for _, qid in ipairs(QuestsInTooltip(tooltip, data)) do
    local sharers = ns.Peers:GetSharers(qid)
    if #sharers > 0 then rows[#rows + 1] = { qid = qid, sharers = sharers } end
    if #rows >= MAX_QUESTS then break end
  end
  if #rows == 0 then return false end
  local head = UI.Wrap(UI.GOLD, "Queb:")
  if #rows == 1 then
    tooltip:AddLine(head .. " " .. NamesText(rows[1].sharers), 1, 1, 1, true)
  else
    tooltip:AddLine(head, 1, 1, 1)
    for _, r in ipairs(rows) do
      local title = ns.QuestState:GetTitle(r.qid) or ("Quest " .. r.qid)
      tooltip:AddLine("   " .. UI.Wrap(UI.GRAY, title .. ":") .. " " .. NamesText(r.sharers), 1, 1, 1, true)
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Hook
---------------------------------------------------------------------------
local function OnUnitTooltip(tooltip, data)
  if not ns.db or not tooltip or tooltip.IsForbidden and tooltip:IsForbidden() then return end
  if ns.Tooltip and ns.Tooltip.appended[tooltip] then return end
  local unit = UnitOf(tooltip, data)
  if not unit then return end
  local added
  local isPlayer = Bool(SafeCall(UnitIsPlayer, unit))
  if isPlayer then
    added = AddPlayerLines(tooltip, unit)
  elseif isPlayer == false then
    added = AddQuestUnitLines(tooltip, data)
  end
  if added and ns.Tooltip then ns.Tooltip.appended[tooltip] = true end
end

ns.Listen("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
     and Enum.TooltipDataType.Unit then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
      pcall(OnUnitTooltip, tooltip, data)
    end)
    U.hook = "TooltipDataProcessor"
  elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) pcall(OnUnitTooltip, tooltip, nil) end)
    U.hook = "OnTooltipSetUnit"
  end
end)
