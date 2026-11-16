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
  { "Questie_BaseFrame", "tracker" },      -- Questie's tracker (its rows' party-progress tooltip)
  { "CommunitiesFrame", "guild" },         -- Guild & Communities (Modern)
  { "GuildFrame", "guild" },               -- Guild list (Classic)
  { "ForeverDungeonJournalFrame", "dungeonjournal" }, -- DungeonJournal quest rows (v0.14.0)
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
      or ((owner.mode == "quest" or owner.mode == "objective") and type(owner.Quest) == "table"
          and ValidID(owner.Quest.Id)) -- Questie tracker line
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

---------------------------------------------------------------------------
-- Map tooltips settle hidden (v0.14.2). Blizzard builds a quest area/marker
-- tooltip over a few frames (title first, objectives a frame later), so our
-- lines showed under the title for a moment, then jumped to the bottom.
-- Now a map tooltip Queb adds to stays invisible (alpha 0) until its
-- content has been the same for SETTLE_FRAMES frames (at most SETTLE_MAX
-- seconds), then appears finished. Alpha is always restored on hide.
---------------------------------------------------------------------------
local SETTLE_FRAMES, SETTLE_MAX = 2, 0.3
local settle = setmetatable({}, { __mode = "k" }) -- tooltip -> state

local function Signature(tooltip, owner, key)
  local h = tooltip:GetHeight() or 0
  return tostring(owner) .. ":" .. tostring(key) .. ":" .. (tooltip:NumLines() or 0) .. ":" .. math.floor(h + 0.5)
end

local function Reveal(tooltip)
  local st = settle[tooltip]
  if st and st.hidden then tooltip:SetAlpha(st.alpha or 1) end
  if st then st.hidden, st.done = false, true end
end

local function EndSettle(tooltip)
  local st = settle[tooltip]
  if not st then return end
  if st.hidden then tooltip:SetAlpha(st.alpha or 1) end
  settle[tooltip] = nil
end

-- Called after we added lines to a map tooltip (owner + what it is about).
local function Settle(tooltip, owner, key)
  local st = settle[tooltip]
  if not st or st.owner ~= owner or st.key ~= key then
    if st then EndSettle(tooltip) end
    st = { owner = owner, key = key, start = GetTime(), stable = 0, alpha = 1 }
    settle[tooltip] = st
  end
  if st.done then return end
  -- OnUpdate compares content frame to frame; a rebuild with the same
  -- content (map blobs rebuild every frame) still counts as settled
  if not st.hidden then
    local a = tooltip:GetAlpha()
    st.alpha = (type(a) == "number" and not ns.IsSecret(a) and a > 0.05) and a or 1
    st.hidden = true
  end
  tooltip:SetAlpha(0)
end

local function OnUpdate(tooltip)
  local st = settle[tooltip]
  if not st or st.done then return end
  if tooltip:GetOwner() ~= st.owner then return EndSettle(tooltip) end
  local sig = Signature(tooltip, st.owner, st.key)
  if sig == st.sig then st.stable = st.stable + 1 else st.sig, st.stable = sig, 0 end
  if st.stable >= SETTLE_FRAMES or GetTime() - st.start > SETTLE_MAX then
    Reveal(tooltip)
  elseif st.hidden then
    tooltip:SetAlpha(0) -- Blizzard may reset alpha while rebuilding
  end
end

local loggedOwners = {}
local function OnShow(tooltip)
  if TT.busy then return end
  local st = settle[tooltip]
  if st and tooltip:GetOwner() ~= st.owner then EndSettle(tooltip); st = nil end
  if TT.appended[tooltip] then
    -- same build shown again: keep it hidden until it settles
    if st and st.hidden and not st.done then tooltip:SetAlpha(0) end
    return
  end
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
        Settle(tooltip, owner, kind)
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

  local questID
  if area == "dungeonjournal" then
    -- only rows we decorated; its other tooltips (items, bosses) are left alone
    questID = ns.DungeonJournalUI and ns.DungeonJournalUI:QuestOf(owner)
  else
    questID = QuestIDFromOwner(owner) or QuestIDFromTitle(tooltip)
  end
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
    if area == "map" then Settle(tooltip, owner, questID) end
  end
end

local function Reset(tooltip) TT.appended[tooltip] = nil end
local function OnHide(tooltip)
  TT.appended[tooltip] = nil
  EndSettle(tooltip)
end

local function HookTooltip(tooltip)
  if not tooltip or TT.hooked[tooltip] then return end
  TT.hooked[tooltip] = true
  hooksecurefunc(tooltip, "Show", OnShow)
  -- a fresh tooltip (new owner / cleared lines) may need our lines again
  hooksecurefunc(tooltip, "SetOwner", Reset)
  hooksecurefunc(tooltip, "ClearLines", Reset)
  tooltip:HookScript("OnHide", OnHide)
  tooltip:HookScript("OnUpdate", OnUpdate)
end

-- Other GameTooltips (e.g. Questie's tracker tooltip, made on first use).
function TT:Hook(tooltip) HookTooltip(tooltip) end

ns.Listen("LOGIN", function()
  HookTooltip(GameTooltip)
  if WorldMapTooltip and WorldMapTooltip ~= GameTooltip then HookTooltip(WorldMapTooltip) end
end)
