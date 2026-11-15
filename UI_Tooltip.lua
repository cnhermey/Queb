-- Queb: add class-colored circles + guildmate progress to Blizzard
-- quest tooltips:
--   * World map: hovering a quest area (blob) or a quest marker (POI pin)
--   * Map & Quest Log side panel: hovering a quest title
--   * Objective tracker (Modern and Classic): hovering a quest
--
-- Approach: post-hook GameTooltip:Show and, only when the tooltip's owner
-- sits inside one of those Blizzard frames, work out which quest it is about
-- and append our lines. We never replace Blizzard code or write to its frames.
-- Owner/field names are from Mainline UI source; verify with Settings > Debug messages.
local _, ns = ...
local UI = ns.UI

local TT = { appended = setmetatable({}, { __mode = "k" }), hooked = {}, busy = false }
ns.Tooltip = TT

-- Roots whose descendants we care about, and what kind of area each is.
local ROOTS = {
  { "WorldMapFrame", "map" },
  { "QuestMapFrame", "questlog" },
  { "QuestLogFrame", "questlog" },
  { "ObjectiveTrackerFrame", "tracker" },
  { "QuestWatchFrame", "tracker" },
  { "EUI_CustomQuestTracker", "tracker" }, -- EllesmereUI Quest Tracker (Forever custom tracker)
  { "CommunitiesFrame", "guild" },         -- Guild & Communities (Modern)
  { "GuildFrame", "guild" },               -- Guild list (Classic)
}

local function AreaOf(owner)
  if not owner or type(owner) ~= "table" or not owner.GetParent then return nil end
  local f, depth = owner, 0
  while f and depth < 12 do
    for _, r in ipairs(ROOTS) do
      if f == _G[r[1]] then return r[2] end
    end
    f = f.GetParent and f:GetParent() or nil
    depth = depth + 1
  end
end

local function ValidID(v)
  if type(v) == "number" and v > 0 and not ns.IsSecret(v) then return v end
end

-- Fields Blizzard quest pins / title buttons / tracker blocks carry.
local function QuestIDFromOwner(owner)
  return ValidID(owner.questID)
      or ValidID(owner.highlightedQuestID)   -- quest blob pin (area) when hovering
      or ValidID(owner.focusedQuestID)
      or (owner.parentModule and ValidID(owner.id)) -- tracker block
      or (owner.kind == "quest" and ValidID(owner.id)) -- EllesmereUI custom tracker title row
end

-- Fallback: first tooltip line is usually the quest title.
local function QuestIDFromTitle(tooltip)
  local name = tooltip.GetName and tooltip:GetName()
  local fs = name and _G[name .. "TextLeft1"]
  local text = fs and fs:GetText()
  if not text or ns.IsSecret(text) then return nil end
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "^%[[^%]]*%]%s*", "") -- "[12] Title"
  for qid, q in pairs(ns.QuestState.quests) do
    if q.title == text then return qid end
  end
end

local loggedOwners = {}
local function OnShow(tooltip)
  if TT.busy or TT.appended[tooltip] then return end
  if not ns.db or not ns.db.showInTooltips then return end
  local owner = tooltip:GetOwner()
  if not owner or UI.ours[owner] then return end
  local area = AreaOf(owner)
  if not area then return end

  -- OpenMap's player markers (guild/friend dots, zone badges, group dots)
  if area == "map" and ns.OpenMapUI then
    local kind = ns.OpenMapUI:KindOf(owner)
    if kind then
      if ns.OpenMapUI:AddLines(tooltip, owner, kind) then
        TT.appended[tooltip] = true
        TT.busy = true
        tooltip:Show()
        TT.busy = false
      end
      return
    end
  end

  if area == "guild" then
    local name, classFile, online = ns.GuildUI:MemberOf(owner)
    if name and ns.GuildUI:AddLines(tooltip, name, classFile, online) then
      TT.appended[tooltip] = true
      TT.busy = true
      tooltip:Show()
      TT.busy = false
    end
    return
  end

  local questID = QuestIDFromOwner(owner) or QuestIDFromTitle(tooltip)
  if ns.db.debug and not loggedOwners[owner] then
    loggedOwners[owner] = true
    ns.Debug("tooltip in", area, "owner", owner.GetDebugName and owner:GetDebugName() or "?", "quest", questID or "none")
  end
  if not questID then return end

  if UI:AddSharersToTooltip(tooltip, questID) then
    TT.appended[tooltip] = true
    TT.busy = true
    tooltip:Show() -- resize to fit our lines (re-entry guarded by TT.busy)
    TT.busy = false
  end
end

local function Reset(tooltip) TT.appended[tooltip] = nil end

local function HookTooltip(tooltip)
  if not tooltip or TT.hooked[tooltip] then return end
  TT.hooked[tooltip] = true
  hooksecurefunc(tooltip, "Show", OnShow)
  -- a fresh tooltip (new owner / cleared lines) may need our lines again
  hooksecurefunc(tooltip, "SetOwner", Reset)
  hooksecurefunc(tooltip, "ClearLines", Reset)
  tooltip:HookScript("OnHide", Reset)
end

ns.Listen("LOGIN", function()
  HookTooltip(GameTooltip)
  if WorldMapTooltip and WorldMapTooltip ~= GameTooltip then HookTooltip(WorldMapTooltip) end
end)
