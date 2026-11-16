-- Queb: circles on DungeonJournal's quest rows (v0.14.0).
--
-- DungeonJournal (folder ForeverDungeonJournal) has no public API. Its quest
-- rows are a local pool, but every quest-list refresh ends with
--   FDJ.MarkLostQuestRows(questButtons, quests)
-- a field on its global namespace ForeverDungeonJournal_NS. A post-hook
-- (hooksecurefunc) on it hands us the rows and the dungeon's quest list:
-- quests[button.questIndex].id is the row's quest.
--
-- Rows are 296 x 48 Buttons: quest icon left, name (button.name) + meta line,
-- icons top right (check, turn-in "?", faction / class icons, "Pick it up").
-- Circles go right after the name text in measured free space
-- (UI:SetDotsAfterText stops at the first visible element to the right), as
-- on every other quest list; no room = no circles (the tooltip still lists
-- people). Rows hidden by DungeonJournal's RPG Mode get none. Nothing is
-- written to DungeonJournal's frames or tables; row -> quest lives in our
-- own weak table. Same setting as the quest log circles ("Quest log").
local _, ns = ...
local UI = ns.UI

local J = { hooked = false, stats = { rows = 0, placed = 0 } }
ns.DungeonJournalUI = J

local lastButtons, lastQuests
local rowQuest = setmetatable({}, { __mode = "k" }) -- [row] = questID

local function FDJ() return ns.Dungeons.FDJ() end

local function Frame() return _G.ForeverDungeonJournalFrame end

local function OnRows(buttons, quests)
  if type(buttons) == "table" and type(quests) == "table" then
    lastButtons, lastQuests = buttons, quests
  end
  UI:Refresh()
end

function J:Hook()
  if self.hooked then return true end
  local F = FDJ()
  if F and type(F.MarkLostQuestRows) == "function" then
    hooksecurefunc(F, "MarkLostQuestRows", OnRows)
    self.hooked = true
    local f = Frame()
    if f then f:HookScript("OnHide", function() UI:Refresh() end) end
  end
  return self.hooked
end

-- questID of a DungeonJournal row we decorated (for the tooltip hook).
function J:QuestOf(row)
  return rowQuest[row]
end

local function Decorate(seen)
  local f = Frame()
  if not (f and f:IsVisible() and lastButtons and lastQuests) then return end
  for _, button in ipairs(lastButtons) do
    if type(button) == "table" and button.IsVisible and button:IsVisible() and not button.fdjRPGHidden then
      local idx = button.questIndex
      local q = type(idx) == "number" and lastQuests[idx]
      local qid = type(q) == "table" and q.id
      local text = button.name
      if type(qid) == "number" and qid > 0 and type(text) == "table" and text.GetObjectType
         and text:GetObjectType() == "FontString" then
        seen[button] = true
        rowQuest[button] = qid
        J.stats.rows = J.stats.rows + 1
        if UI:SetDotsAfterText("dungeonjournal", button, button, qid, text) then
          J.stats.placed = J.stats.placed + 1
        end
      end
    end
  end
end

UI:RegisterDecorator("dungeonjournal", function()
  local seen = {}
  J.stats.rows, J.stats.placed = 0, 0
  if J:Hook() and ns.db.showInQuestLog then
    local ok, err = pcall(Decorate, seen)
    if not ok then ns.Debug("DungeonJournal rows:", err) end
  end
  UI:ReleaseUnseen("dungeonjournal", seen)
end)

ns.Listen("LOGIN", function()
  for _, delay in ipairs({ 0, 5 }) do
    C_Timer.After(delay, function() if J:Hook() then UI:Refresh() end end)
  end
end)
