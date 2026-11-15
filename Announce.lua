-- Queb: "Quest completed" in party chat when you turn in a quest.
--
-- Same message Questie sends ("Quest Completed: [quest link]", its
-- QuestieAnnounce:CompletedQuest on QUEST_TURNED_IN), but only when Questie
-- isn't loaded, so players running both never see it twice. Like Questie's
-- default channel setting ("party"): only in a party, not in a raid.
--
-- Never in instances: Forever (Midnight rules) blocks addon chat there.
-- Each quest is announced at most once per session.
local _, ns = ...

local A = { sent = {} }
ns.Announce = A

local PREFIX = "Queb: Quest completed: "

local function Secret(v) return ns.IsSecret(v) end

-- Is Questie loaded (installed and enabled)? Then it owns announcements.
function A:QuestieLoaded()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not isLoaded then return false end
  local ok, loaded = pcall(isLoaded, "Questie")
  return ok and not Secret(loaded) and loaded and true or false
end

-- "PARTY" when we may announce now, else nil + short reason (for probe/debug).
function A:Channel()
  local inInstance = IsInInstance()
  if not Secret(inInstance) and inInstance then return nil, "in instance" end
  if IsInRaid() then return nil, "raid" end
  if LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME) then return "PARTY" end
  if not LE_PARTY_CATEGORY_HOME and IsInGroup() then return "PARTY" end
  return nil, "not in party"
end

function A:Enabled()
  return ns.db and ns.db.announceTurnIns and not self:QuestieLoaded()
end

-- Clickable quest link. Blizzard's own when it has one, else built from the
-- title we saw in the log (the quest may already be gone after turn-in).
function A:QuestLink(questID, title, level)
  if GetQuestLink then
    local ok, link = pcall(GetQuestLink, questID)
    if ok and type(link) == "string" and link ~= "" and not Secret(link) then return link end
  end
  if type(title) ~= "string" or Secret(title) then return nil end
  title = title:gsub("[|%c%[%]]", ""):match("^%s*(.-)%s*$") -- no escape codes or brackets in a link
  if title == "" then return nil end
  return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", questID, tonumber(level) or -1, title)
end

local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

function A:OnTurnedIn(questID)
  questID = tonumber(questID)
  if not questID or self.sent[questID] or not self:Enabled() then return end
  local channel, why = self:Channel()
  if not channel then
    ns.Debug("announce skipped:", why)
    return
  end
  -- QuestState rescans after a short delay, so the quest is still known here
  local q = ns.QuestState.quests[questID]
  local title = q and q.title
  if not title and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if ok then title = t end
  end
  local link = self:QuestLink(questID, title, q and q.lvl)
  if not link then
    ns.Debug("announce skipped: no title for", questID)
    return -- never announce a quest we can't name
  end
  self.sent[questID] = true
  local ok, err = pcall(send, PREFIX .. link, channel)
  if not ok then ns.Debug("announce failed:", tostring(err)) end
end

ns.On("QUEST_TURNED_IN", function(_, questID) A:OnTurnedIn(questID) end)
