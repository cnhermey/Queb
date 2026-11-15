-- Queb: support for EllesmereUI Quest Tracker.
--
-- On WoW Forever, EllesmereUIQuestTracker's default style replaces Blizzard's
-- tracker with its own frame (EUI_CustomQuestTracker) and mutes Blizzard's.
-- (Its "Blizzard"/"Classic" styles only reskin Blizzard's tracker, which
-- UI_Tracker.lua already handles.)
--
-- We use Ellesmere's public row API, EllesmereUI.RegisterQuestTrackerRow
-- (see its PLUGINS_API.md): it gives every quest title row a slot frame of a
-- reserved width, RIGHT of the title, and calls us on each render. The left
-- side of its rows is taken by its focus buttons and clipped by its scroll
-- frame, so the circles sit right of the title on this tracker.
local _, ns = ...
local UI = ns.UI

local E = { registered = false }
ns.Ellesmere = E

local HOOK_ID = "Queb"
local SLOT_WIDTH = 52 -- Ellesmere allows 0-64; 3 dots + "+N" fit
local MAX_DOTS = 3

function E:CustomTrackerActive()
  local f = _G.EUI_CustomQuestTracker
  return f ~= nil and f:IsShown()
end

function E:Available()
  return type(EllesmereUI) == "table" and type(EllesmereUI.RegisterQuestTrackerRow) == "function"
end

-- Called by Ellesmere for each quest title row: (slot, questID, titleFontString)
local function OnRow(slot, questID)
  if not ns.db or not ns.db.showInTracker or type(questID) ~= "number" or ns.IsSecret(questID) then
    UI:Release("ellesmere", slot)
    return
  end
  UI:SetDots("ellesmere", slot, slot, questID, "TOPLEFT", slot, "TOPLEFT", 3, -1, MAX_DOTS, SLOT_WIDTH - 4)
end

function E:Register()
  if self.registered or not self:Available() then return end
  local ok, res = pcall(EllesmereUI.RegisterQuestTrackerRow, HOOK_ID, OnRow, SLOT_WIDTH)
  self.registered = ok and res ~= false
  ns.Debug("EllesmereUI tracker row hook:", self.registered and "registered" or ("failed " .. tostring(res)))
end

-- Only when OUR data or settings changed, ask Ellesmere to re-render its rows
-- (it coalesces). Quest log changes it already re-renders for by itself.
local dirty = false
local function MarkDirty() dirty = true end
ns.Listen("PEERS_CHANGED", MarkDirty)
ns.Listen("SETTINGS_CHANGED", MarkDirty)

UI:RegisterDecorator("ellesmere", function()
  if not dirty then return end
  dirty = false
  if E.registered and type(EllesmereUI.RefreshQuestTrackerRows) == "function" then
    EllesmereUI.RefreshQuestTrackerRows()
  end
end)

ns.Listen("LOGIN", function() E:Register() end)
