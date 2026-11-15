-- Queb: /queb opens the main window; /queb probe is a developer report.
-- Style rules: Blizzard system-message look (ns.Print / ns.PrintLine) and
-- short phrases.
local _, ns = ...
local P = function(text) ns.PrintLine(text) end

local function Stats()
  local s = ns.Comm.stats
  P(string.format("  Sent %d · received %d · dropped %d · throttled %d", s.sent, s.recv, s.dropped, s.throttled))
  local blocked = {}
  for ch in pairs(ns.Comm.blocked) do blocked[#blocked + 1] = ch end
  if #blocked > 0 then P("  Blocked: " .. table.concat(blocked, ", ")) end
  P("  State hash: " .. ns.QuestState.hash)
end

local function Peers()
  local n = 0
  for name, peer in pairs(ns.Peers.list) do
    n = n + 1
    local shared = 0
    for qid in pairs(peer.quests) do
      if ns.QuestState.quests[qid] then shared = shared + 1 end
    end
    local srcs = {}
    for k in pairs(peer.sources) do srcs[#srcs + 1] = k end
    local c = ns.UI.ClassColor(ns.Peers:GetClass(peer))
    P(string.format("  |cff%02x%02x%02x%s|r · %d shared · v%s · %s%s",
      c.r * 255, c.g * 255, c.b * 255, name, shared, peer.ver or "?",
      table.concat(srcs, "/"), peer.hasState and "" or " · syncing"))
  end
  if n == 0 then ns.Print("No Queb users seen yet") end
end

local function Probe()
  local build, _, _, iface = GetBuildInfo()
  ns.Print("Probe: build", build, "interface", iface)
  local names = {
    "ObjectiveTrackerFrame", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
    "QUEST_TRACKER_MODULE", "QuestWatchFrame", "QuestWatchLine1", "QuestWatch_Update",
    "QuestMapFrame", "QuestScrollFrame", "QuestLogQuests_Update",
    "QuestLogFrame", "QuestLogTitle1", "QuestLog_Update",
  }
  for _, n in ipairs(names) do
    local v = _G[n]
    P("  " .. n .. ": " .. (v ~= nil and ns.UI.Wrap(ns.UI.GREEN, type(v)) or ns.UI.Wrap(ns.UI.RED, "missing")))
  end
  if QuestScrollFrame then
    P("  QuestScrollFrame.titleFramePool: " .. tostring(QuestScrollFrame.titleFramePool ~= nil))
  end
  for _, m in ipairs(ns.Tracker.modules) do
    P("  tracker module " .. m.name .. " usedBlocks: " .. type(m.obj.usedBlocks))
  end
  P("  C_QuestLog.IsUnitOnQuest: " .. tostring(C_QuestLog.IsUnitOnQuest ~= nil)
    .. ", issecretvalue: " .. tostring(issecretvalue ~= nil)
    .. ", GetGuildRosterInfo: " .. tostring(GetGuildRosterInfo ~= nil))
  P("  Guild UI: CommunitiesFrame " .. tostring(CommunitiesFrame ~= nil) .. " (hooked " .. tostring(ns.GuildUI.boxHooked == true)
    .. "), Classic GuildFrame " .. tostring(GuildFrame ~= nil) .. " (hooked " .. tostring(ns.GuildUI.classicHooked == true) .. ")")
  local E = ns.Ellesmere
  P("  EllesmereUI tracker API: " .. tostring(E:Available()) .. ", row hook registered: " .. tostring(E.registered)
    .. ", custom tracker shown: " .. tostring(E:CustomTrackerActive()))
  local shareN, wantN = 0, 0
  for _, q in pairs(ns.QuestState.quests) do if q.push then shareN = shareN + 1 end end
  wantN = #ns.Peers:ComputeWants()
  P("  Can share: icon " .. ns.UI:ShareIcon(12) .. " (" .. tostring(ns.UI.shareSource) .. "), yours "
    .. shareN .. ", you could take " .. wantN .. ", IsPushableQuest " .. tostring(C_QuestLog.IsPushableQuest ~= nil)
    .. ", IsQuestFlaggedCompleted " .. tostring(C_QuestLog.IsQuestFlaggedCompleted ~= nil))
  P("  OpenMap API: " .. (type(OpenMapAPI) == "table" and ("v" .. tostring(OpenMapAPI.major) .. "." .. tostring(OpenMapAPI.version)) or "missing")
    .. ", menu toggle: " .. tostring(ns.OpenMapUI and ns.OpenMapUI.menuRegistered == true))
  P("  Hooks installed: " .. (#ns.Tracker.hooks > 0 and table.concat(ns.Tracker.hooks, ", ") or "none"))
  local B = ns.Buddies
  B:Create() -- builds the window (hidden) so we can report what it used
  P("  Look: circle " .. (ns.UI.CIRCLE:find("AddOns", 1, true) and "Queb fallback" or "Blizzard")
    .. ", window " .. tostring(B.template) .. ", list " .. tostring(B.list)
    .. ", class icons " .. tostring(C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("classicon-warrior") ~= nil))
  local f = B.frame
  P("  Icon in portrait: " .. tostring(f and f.qbPortraitSet or false))
  P("  Roles: yours " .. ns.Roles:EncodeMine() .. ", icons " .. tostring(ns.Roles:IconSource())
    .. ", window " .. (f and math.floor(f:GetWidth()) .. "x" .. math.floor(f:GetHeight()) or "?"))
  local me = {}
  for n in pairs(ns.playerNames or {}) do me[#me + 1] = "[" .. n .. "]" end
  P("  Your name forms: " .. table.concat(me, " "))
end

-- Interface-driven: /queb opens the Queb window (Quebmates + Settings tabs).
-- The only other command is a hidden developer report, /queb probe.
SLASH_QUEB1 = "/queb"
SlashCmdList.QUEB = function(msg)
  if not ns.db then return end
  local cmd = string.match(string.lower(msg or ""), "^%s*(%S*)")
  if cmd == "probe" then
    Probe()
    Stats()
    P("  Queb users:")
    return Peers()
  end
  if cmd == "settings" then return ns.Buddies:Toggle("settings") end
  ns.Buddies:Toggle()
end
