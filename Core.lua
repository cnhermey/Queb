-- Queb: event dispatch, internal message bus, saved settings.
local addonName, ns = ...

---------------------------------------------------------------------------
-- One event frame, many handlers.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    list[i](event, ...)
  end
end)

---------------------------------------------------------------------------
-- Internal message bus (not WoW events).
---------------------------------------------------------------------------
local listeners = {}

function ns.Listen(msg, fn)
  listeners[msg] = listeners[msg] or {}
  table.insert(listeners[msg], fn)
end

function ns.Fire(msg, ...)
  local list = listeners[msg]
  if not list then return end
  for i = 1, #list do
    list[i](...)
  end
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
ns.DEFAULTS = {
  shareGuild = true,         -- guildmates who run the addon
  shareParty = true,         -- party/raid members who run the addon, guild or not (on by default since 0.10.0)
  showNonAddonParty = true,  -- group members without the addon (C_QuestLog.IsUnitOnQuest; no progress numbers)
  showInQuestLog = true,     -- class-colored dots left of quest titles in the quest list
  showInTracker = true,      -- same dots in the objective tracker
  showInTooltips = true,     -- circles + progress in quest tooltips (world map areas/markers, quest log, tracker)
  showInGuild = true,        -- "N shared quests" when hovering guildmates in Guild & Communities
  showOnMap = true,          -- shared quests on OpenMap's player markers (dots, zone badges, group dots)
  showOnPlayers = true,      -- shared quests when hovering a player (unit frames, world, nameplates)
  showOnQuestUnits = true,   -- who else is on the quest when hovering a quest mob/NPC
  maxDots = 5,              -- more sharers than this collapse into "+N"
  loginSummary = true,       -- after login, list guildmates you share the most quests with
  announceTurnIns = true,    -- "Queb: Quest completed: [link]" in party chat on turn-in (only without Questie)
  shareQuests = true,        -- "can share": send which quests you can share; show what guildmates can share with you
  showNearby = true,         -- also suggest online guildmates near your level (no shared quests needed)
  nearbyLevelRange = 3,      -- "near your level" = within this many levels
  peerTimeoutMinutes = 15,   -- forget peers we have not heard from
  debug = false,
}

ns.On("ADDON_LOADED", function(_, name)
  if name ~= addonName then return end
  QuebDB = QuebDB or {}
  local db = QuebDB
  for k, v in pairs(ns.DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  -- Migrations
  if (db.schema or 1) < 2 then
    db.showNonAddonParty = true -- now on by default (works without the addon on their side)
  end
  if (db.schema or 1) < 3 then
    db.shareParty = true -- party sync now on by default: works with anyone in your group, guild or not
  end
  db.schema = 3
  ns.db = db
  ns.Fire("INIT")
end)

ns.On("PLAYER_LOGIN", function()
  ns.BuildPlayerNames()
  ns.loggedIn = true
  ns.Fire("LOGIN")
end)
