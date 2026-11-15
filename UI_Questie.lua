-- Queb: circles on Questie's quest tracker.
--
-- Questie's tracker (Questie_BaseFrame) replaces Blizzard's for the quests it
-- tracks. Unlike EllesmereUI it has no row API, so we read its line frames
-- (read-only) the way it lays them out (Questie 12.9.0, Forever build):
--   * lines are Buttons named linePool1..N, children of
--     TrackedQuestsScrollChildFrame (inside TrackedQuestsScrollFrame, which
--     clips its children)
--   * quest title lines have line.mode == "quest", line.Quest.Id = questID
--     and line.label = the title FontString (left of it: Questie's focus,
--     play and +/- buttons, so nothing of ours goes left)
--   * the tracker keeps a 30 px right margin (TrackerLayout.MARGIN_RIGHT),
--     so even the widest title has room for a circle or two after it
-- Circles go right after the title text, like on every other tracker, in
-- measured free space up to the scroll frame's right edge.
--
-- Refresh: post-hook QuestieTracker:UpdateFormatting (end of each Questie
-- layout) via the global QuestieLoader's module table, plus the base frame's
-- OnShow / OnSizeChanged. Same "Objective tracker" setting as Blizzard's and
-- Ellesmere's trackers. Nothing is written to Questie's frames or tables.
local _, ns = ...
local UI = ns.UI

local Q = { hooked = nil, frameHooked = false, stats = { rows = 0, placed = 0 } }
ns.QuestieUI = Q

local MAX_LINES = 500
local EDGE_PAD = 4

local function Refresh() UI:Refresh() end

-- A Questie module, read from QuestieLoader's own table (no ImportModule:
-- that would create an empty module if the name were wrong).
local function Module(name)
  local L = _G.QuestieLoader
  local mods = type(L) == "table" and rawget(L, "_modules")
  local m = type(mods) == "table" and mods[name]
  if type(m) == "table" then return m end
end

function Q:Loaded()
  return type(_G.QuestieLoader) == "table"
end

function Q:TrackerShown()
  local f = _G.Questie_BaseFrame
  return f ~= nil and f:IsVisible()
end

function Q:Hook()
  if not self.hooked then
    local qt = Module("QuestieTracker")
    if qt and type(qt.UpdateFormatting) == "function" then
      hooksecurefunc(qt, "UpdateFormatting", Refresh)
      self.hooked = "UpdateFormatting"
    end
  end
  local f = _G.Questie_BaseFrame
  if f and not self.frameHooked then
    f:HookScript("OnShow", Refresh)
    f:HookScript("OnSizeChanged", Refresh)
    self.frameHooked = true
  end
  -- Questie's own party-progress tooltip on tracker rows (made on first use)
  local tip = _G.QuestieTrackerQuestTooltip
  if tip and ns.Tooltip and ns.Tooltip.Hook then ns.Tooltip:Hook(tip) end
end

local function QuestIDOf(line)
  if line.mode ~= "quest" or line.Recipe then return nil end
  local q = line.Quest
  local id = type(q) == "table" and q.Id
  if type(id) == "number" and id > 0 and not ns.IsSecret(id) and ns.QuestState.quests[id] then return id end
end

local function Decorate(seen)
  local scroll = _G.TrackedQuestsScrollFrame
  local child = _G.TrackedQuestsScrollChildFrame
  if not (scroll and child and Q:TrackerShown()) then return end
  local right = scroll:GetRight()
  if not right or ns.IsSecret(right) then return end
  for i = 1, MAX_LINES do
    local line = _G["linePool" .. i]
    if not line then break end
    if line:GetParent() == child and line:IsVisible() then
      local qid = QuestIDOf(line)
      local label = line.label
      if qid and type(label) == "table" and label.GetObjectType and label:GetObjectType() == "FontString" then
        seen[line] = true
        Q.stats.rows = Q.stats.rows + 1
        if UI:SetDotsAfterText("questie", line, line, qid, label, nil, right - EDGE_PAD) then
          Q.stats.placed = Q.stats.placed + 1
        end
      end
    end
  end
end

UI:RegisterDecorator("questie", function()
  local seen = {}
  Q.stats.rows, Q.stats.placed = 0, 0
  if Q:Loaded() then
    Q:Hook()
    if ns.db.showInTracker then Decorate(seen) end
  end
  UI:ReleaseUnseen("questie", seen)
end)

-- Questie builds its tracker in a coroutine after login: try hooking again.
ns.Listen("LOGIN", function()
  for _, delay in ipairs({ 0, 5, 15, 30 }) do
    C_Timer.After(delay, function() if Q:Loaded() then Q:Hook(); Refresh() end end)
  end
end)
