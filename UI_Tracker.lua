-- Queb: dots in the objective tracker (Modern + Classic presets).
--
-- Frame and method names below come from Mainline UI source and are NOT yet
-- verified on Forever. Everything is feature-detected; `/queb probe` reports
-- what was found so we can fix names after testing in game.
local _, ns = ...
local UI = ns.UI

local T = { modules = {}, hooks = {}, installed = {} }
ns.Tracker = T

-- Quest-carrying tracker modules (11.x+ names, then 10.x names).
local MODULE_GLOBALS = {
  "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
  "QUEST_TRACKER_MODULE", "CAMPAIGN_QUEST_TRACKER_MODULE",
}
local MODULE_METHODS = { "Update", "LayoutContents", "EndLayout" }

local function Refresh() UI:Refresh() end

local function HookMethod(obj, objName, method)
  local id = objName .. ":" .. method
  if T.installed[id] then return end
  if type(obj) == "table" and type(obj[method]) == "function" then
    hooksecurefunc(obj, method, Refresh)
    T.installed[id] = true
    T.hooks[#T.hooks + 1] = id
  end
end

local function HookGlobal(fname)
  if T.installed[fname] then return end
  if type(_G[fname]) == "function" then
    hooksecurefunc(fname, Refresh)
    T.installed[fname] = true
    T.hooks[#T.hooks + 1] = fname .. "()"
  end
end

function T:Install()
  -- Modern preset
  for _, gname in ipairs(MODULE_GLOBALS) do
    local m = _G[gname]
    if type(m) == "table" and not T.installed["module:" .. gname] then
      T.installed["module:" .. gname] = true
      self.modules[#self.modules + 1] = { name = gname, obj = m }
      for _, method in ipairs(MODULE_METHODS) do HookMethod(m, gname, method) end
    end
  end
  if ObjectiveTrackerFrame then
    HookMethod(ObjectiveTrackerFrame, "ObjectiveTrackerFrame", "Update")
    if not T.installed["OTF:OnShow"] then
      ObjectiveTrackerFrame:HookScript("OnShow", Refresh)
      T.installed["OTF:OnShow"] = true
    end
  end
  -- Classic preset
  HookGlobal("QuestWatch_Update")
end

---------------------------------------------------------------------------
-- Modern: walk each module's active blocks (read-only).
---------------------------------------------------------------------------
local function BlockQuestID(block)
  local id = block.questID
  if type(id) ~= "number" then id = block.id end
  if type(id) == "number" and id > 0 then return id end
end

local function IsFrame(v)
  return type(v) == "table" and type(v.GetObjectType) == "function"
end

local function ForEachBlock(module, fn)
  local used = module.usedBlocks
  if type(used) ~= "table" then return end
  for k, v in pairs(used) do
    if IsFrame(v) then
      fn(v)
    elseif type(v) == "table" then -- keyed by template, then by id
      for _, block in pairs(v) do
        if IsFrame(block) then fn(block) end
      end
    end
  end
end

local function DecorateModern(seen)
  if not (ObjectiveTrackerFrame and ObjectiveTrackerFrame:IsVisible()) then return end
  -- Replacement trackers (e.g. EllesmereUI's custom tracker) mute Blizzard's
  -- frame with alpha 0 but leave it shown; our mouse-enabled dots must not sit
  -- there invisibly.
  if ObjectiveTrackerFrame:GetEffectiveAlpha() < 0.05 then return end
  if ns.Ellesmere and ns.Ellesmere:CustomTrackerActive() then return end
  for _, m in ipairs(T.modules) do
    ForEachBlock(m.obj, function(block)
      if block:IsVisible() then
        local qid = BlockQuestID(block)
        if qid then
          local header = block.HeaderText
          seen[block] = true
          -- After the title text, in free space only (the POI/map-marker
          -- button sits left of the title).
          if header then
            UI:SetDotsAfterText("tracker", block, block, qid, header)
          else
            UI:Release("tracker", block)
          end
        end
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Classic: QuestWatchLineN font strings; map title lines to questIDs by text.
---------------------------------------------------------------------------
local function StripLevel(text)
  return (string.gsub(text, "^%[[^%]]*%]%s*", ""))
end

local function DecorateClassic(seen)
  if not (QuestWatchFrame and QuestWatchFrame:IsVisible()) then return end
  local byTitle = {}
  for qid, q in pairs(ns.QuestState.quests) do
    if q.title then byTitle[q.title] = qid end
  end
  for i = 1, (MAX_QUESTWATCH_LINES or 50) do
    local line = _G["QuestWatchLine" .. i]
    if not line then break end
    if line:IsShown() then
      local text = line:GetText()
      if text and not ns.IsSecret(text) then
        local qid = byTitle[text] or byTitle[StripLevel(text)]
        if qid then
          seen[line] = true
          UI:SetDotsAfterText("tracker", line, QuestWatchFrame, qid, line)
        end
      end
    end
  end
end

UI:RegisterDecorator("tracker", function()
  local seen = {}
  if ns.db.showInTracker then
    DecorateModern(seen)
    DecorateClassic(seen)
  end
  UI:ReleaseUnseen("tracker", seen)
end)

ns.Listen("LOGIN", function() T:Install() end)
ns.On("ADDON_LOADED", function()
  if ns.loggedIn then T:Install() end -- load-on-demand Blizzard UI
end)
