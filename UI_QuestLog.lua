-- Queb: dots left of each quest title in the quest list.
--   Modern preset: QuestMapFrame side panel (QuestScrollFrame)
--   Classic preset: QuestLogFrame (QuestLogTitleN buttons)
-- Names are from Mainline/Classic UI source and still need in-game checks.
local _, ns = ...
local UI = ns.UI
local T = ns.Tracker -- reuse its hook bookkeeping for /queb probe

local L = { installed = {} }
ns.QuestLogUI = L

local function Refresh() UI:Refresh() end

local function HookGlobal(fname)
  if L.installed[fname] then return end
  if type(_G[fname]) == "function" then
    hooksecurefunc(fname, Refresh)
    L.installed[fname] = true
    T.hooks[#T.hooks + 1] = fname .. "()"
  end
end

local function HookShow(frameName)
  local key = frameName .. ":OnShow"
  if L.installed[key] then return end
  local f = _G[frameName]
  if f and f.HookScript then
    f:HookScript("OnShow", Refresh)
    L.installed[key] = true
    T.hooks[#T.hooks + 1] = key
  end
end

function L:Install()
  HookGlobal("QuestLogQuests_Update") -- Modern list rebuild
  HookShow("QuestMapFrame")
  HookShow("QuestScrollFrame")
  HookGlobal("QuestLog_Update")       -- Classic list rebuild
  HookShow("QuestLogFrame")
end

---------------------------------------------------------------------------
-- Modern
---------------------------------------------------------------------------
local function TitleText(button)
  return button.Text or button.ButtonText or (button.GetFontString and button:GetFontString())
end

-- Dots go in the free space after the title text (left of the checkmark);
-- the left side of each row holds Blizzard's quest-status icons.
local function PlaceOnButton(seen, button, qid)
  seen[button] = true
  local text = TitleText(button)
  if text then
    UI:SetDotsAfterText("questlog", button, button, qid, text)
  else
    UI:Release("questlog", button)
  end
end

local function VisitModern(seen, button)
  local qid = button.questID
  if type(qid) == "number" and qid > 0 and button:IsVisible() then
    PlaceOnButton(seen, button, qid)
  end
end

local function ScanChildren(seen, frame, depth)
  for _, child in ipairs({ frame:GetChildren() }) do
    if type(child.questID) == "number" and TitleText(child) then
      VisitModern(seen, child)
    elseif depth < 2 then
      ScanChildren(seen, child, depth + 1)
    end
  end
end

local function DecorateModern(seen)
  local sf = QuestScrollFrame
  if not (sf and sf:IsVisible()) then return end
  local pool = sf.titleFramePool
  if pool and pool.EnumerateActive then
    for button in pool:EnumerateActive() do VisitModern(seen, button) end
  elseif sf.Contents then
    ScanChildren(seen, sf.Contents, 0)
  end
end

---------------------------------------------------------------------------
-- Classic
---------------------------------------------------------------------------
local function DecorateClassic(seen)
  if not (QuestLogFrame and QuestLogFrame:IsVisible()) then return end
  for i = 1, (QUESTS_DISPLAYED or 30) do
    local button = _G["QuestLogTitle" .. i]
    if not button then break end
    if button:IsVisible() then
      local index = button:GetID()
      local info = index and index > 0 and C_QuestLog.GetInfo(index)
      if info and not info.isHeader and type(info.questID) == "number" and info.questID > 0 then
        PlaceOnButton(seen, button, info.questID)
      end
    end
  end
end

UI:RegisterDecorator("questlog", function()
  local seen = {}
  if ns.db.showInQuestLog then
    DecorateModern(seen)
    DecorateClassic(seen)
  end
  UI:ReleaseUnseen("questlog", seen)
end)

ns.Listen("LOGIN", function() L:Install() end)
ns.On("ADDON_LOADED", function()
  if ns.loggedIn then L:Install() end
end)
