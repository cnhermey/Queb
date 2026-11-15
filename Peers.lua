-- Queb: other addon users we have heard from, and "who shares quest X".
local _, ns = ...

local P = {
  list = {},        -- [name] = peer
  roster = {},      -- [name] = unit, for current group members (excluding the player)
  guildOnline = {}, -- [name] = classFile, online guildmates from the guild roster
  guildKnown = false,
}
ns.Peers = P

local MAX_PEERS = 200

-- peer = { name, ver, hash, lastSeen, sources = { GROUP=true, GUILD=true },
--          hasState, entries = {[qid]=string}, quests = {[qid]=quest}, demo,
--          push = {[qid] = { lvl?, title? }}   quests they can share
--          wants = {[qid]=true} }              quests they could take from a guildmate
function P:Touch(name, source)
  local peer = self.list[name]
  if not peer then
    local count = 0
    for _ in pairs(self.list) do count = count + 1 end
    if count >= MAX_PEERS then return nil end
    peer = { name = name, sources = {}, entries = {}, quests = {}, hasState = false }
    self.list[name] = peer
    ns.Debug("new peer", name, "via", source)
  end
  peer.lastSeen = GetTime()
  if source then peer.sources[source] = true end
  return peer
end

function P:Changed()
  ns.Coalesce("peers_changed", 0.2, function()
    ns.Fire("PEERS_CHANGED")
    ns.UI:Refresh()
  end)
end

function P:UpdateRoster()
  wipe(self.roster)
  for _, unit in ipairs(ns.GroupUnits()) do
    local name = ns.UnitKey(unit)
    if name and not ns.IsMe(name) then
      self.roster[name] = unit
    end
  end
end

function P:FindRosterUnit(name)
  local unit = self.roster[name]
  if unit then return unit end
  for _, v in ipairs(ns.NameVariants(name)) do
    if self.roster[v] then return self.roster[v] end
  end
  -- roster key may be the longer spelling
  for rosterName, u in pairs(self.roster) do
    for _, v in ipairs(ns.NameVariants(rosterName)) do
      if v == name then return u end
    end
  end
end

local function LookupLoose(map, name)
  if map[name] ~= nil then return map[name] end
  for _, v in ipairs(ns.NameVariants(name)) do
    if map[v] ~= nil then return map[v] end
  end
  for key, val in pairs(map) do
    for _, v in ipairs(ns.NameVariants(key)) do
      if v == name then return val end
    end
  end
end

-- Peer by any spelling of their name (guild UI names may differ in format).
function P:FindPeer(name)
  return LookupLoose(self.list, name)
end

-- Can we trust C_QuestLog.IsUnitOnQuest for this group unit? The game only
-- knows a party member's quests while they're connected and nearby; when they
-- are far away (e.g. another zone) it answers false for every quest, which
-- would wrongly read as "no shared quests".
local function Bool(v)
  if v == nil or ns.IsSecret(v) then return nil end
  return v and true or false
end

function P:GroupUnitCheckable(unit)
  if Bool(UnitIsConnected(unit)) == false then return false, "offline" end
  if Bool(UnitIsVisible(unit)) ~= true then return false, "far" end
  return true
end

-- Is `name` online, according to the guild roster? nil = can't tell.
function P:IsGuildmateOnline(name)
  if not self.guildKnown then return nil end
  return LookupLoose(self.guildOnline, name) ~= nil
end

-- Quests you share with `name`, for the guild member tooltip.
-- Always returns { status, shared = { {questID, complete?, objectives?}, ... } }.
--   status:
--     "addon"    they run the addon; `shared` is exact (with progress)
--     "syncing"  they run the addon but their quest list hasn't arrived yet
--     "group"    no addon, grouped and nearby; `shared` from the game (no progress)
--     "far"      no addon, grouped but too far away for the game to tell
--     "offline"  not online
--     "noaddon"  no addon and not grouped: their quests can't be seen
-- `online` (optional) overrides the roster-based online check.
function P:SharedWith(name, online)
  local mine = ns.QuestState.quests
  local result = { shared = {} }
  local peer = self:FindPeer(name)
  if peer and peer.hasState then
    result.status = "addon"
    for qid, q in pairs(peer.quests) do
      if mine[qid] then
        result.shared[#result.shared + 1] = { questID = qid, complete = q.c, objectives = q.obj }
      end
    end
  else
    local unit = self:FindRosterUnit(name)
    if online == nil then
      -- group members may not be guildmates: ask the game, not the guild roster
      if unit then online = Bool(UnitIsConnected(unit)) else online = self:IsGuildmateOnline(name) end
    end
    if online == false then
      result.status = "offline"
    elseif peer then
      result.status = "syncing"
    elseif unit and C_QuestLog.IsUnitOnQuest then
      local ok, why = self:GroupUnitCheckable(unit)
      if not ok then
        result.status = why
      else
        result.status = "group"
        for qid in pairs(mine) do
          local ok2, on = pcall(C_QuestLog.IsUnitOnQuest, unit, qid)
          if ok2 and not ns.IsSecret(on) and on then
            result.shared[#result.shared + 1] = { questID = qid }
          end
        end
      end
    else
      result.status = "noaddon"
    end
  end
  table.sort(result.shared, function(a, b) return a.questID < b.questID end)
  return result
end

---------------------------------------------------------------------------
-- "Can share": quests a guildmate can share with you, and the reverse.
---------------------------------------------------------------------------
local function MyLevel()
  local l = UnitLevel("player")
  if ns.IsSecret(l) then return nil end
  return tonumber(l)
end

-- Levels below yours where a quest turns gray (no XP).
local function TrivialRange()
  for _, fn in ipairs({ UnitQuestTrivialLevelRange, GetQuestGreenRange }) do
    if fn then
      local ok, r = pcall(fn, "player")
      if ok and type(r) == "number" and not ns.IsSecret(r) then return r end
    end
  end
  return 8
end

local TOO_HIGH = 4 -- quests more than this many levels above you are left out

-- Could you take this quest from a guildmate? Never guesses "yes" on data it
-- has: in your log, already done, gray or far above you = no. (Prerequisite
-- quests and class/race limits aren't knowable without a quest database.)
function P:CanTake(questID, level)
  if ns.QuestState.quests[questID] then return false end
  if C_QuestLog.IsQuestFlaggedCompleted then
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if ok and not ns.IsSecret(done) and done then return false end
  end
  local me = MyLevel()
  if me and level then
    if level > me + TOO_HIGH then return false end
    if me - level > TrivialRange() then return false end
  end
  return true
end

-- Quests `peer` can share with you: { {questID, level, title}, ... } by level.
function P:ShareableFrom(peer)
  local out = {}
  if not (ns.db and ns.db.shareQuests) or not peer or not peer.push then return out end
  for qid, sh in pairs(peer.push) do
    if self:CanTake(qid, sh.lvl) then
      out[#out + 1] = { questID = qid, level = sh.lvl, title = sh.title }
    end
  end
  table.sort(out, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.questID < b.questID
  end)
  return out
end

-- Guildmates who could take your quest `questID` from you (they told us via
-- WT, so they did the eligibility check on their side).
function P:ShareTargets(questID)
  local out = {}
  if not (ns.db and ns.db.shareQuests) then return out end
  local mine = ns.QuestState.quests[questID]
  if not mine then return out end
  for name, peer in pairs(self.list) do
    if peer.wants and peer.wants[questID] and not peer.quests[questID] and (mine.push or peer.demo) then
      out[#out + 1] = { name = name, class = self:GetClass(peer) }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Every quest you could take from some guildmate (sent as WT). Sorted.
function P:ComputeWants()
  local set, out = {}, {}
  for _, peer in pairs(self.list) do
    if not peer.demo and peer.hasState then
      for _, s in ipairs(self:ShareableFrom(peer)) do set[s.questID] = true end
    end
  end
  for qid in pairs(set) do out[#out + 1] = qid end
  table.sort(out)
  return out
end

-- Online guildmates and their classes (class fallback + logout detection).
function P:UpdateGuildRoster()
  wipe(self.guildOnline)
  self.guildInfo = self.guildInfo or {}
  wipe(self.guildInfo)
  self.guildKnown = false
  if not IsInGuild() or not GetGuildRosterInfo then return end
  local total = GetNumGuildMembers() or 0
  for i = 1, total do
    local name, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
    name = ns.NormalizeName(name)
    if name and online and not ns.IsSecret(online) then
      self.guildOnline[name] = (type(classFile) == "string" and not ns.IsSecret(classFile)) and classFile or false
      self.guildInfo[name] = {
        level = (not ns.IsSecret(level)) and tonumber(level) or nil,
        zone = (type(zone) == "string" and not ns.IsSecret(zone)) and zone or nil,
      }
    end
  end
  self.guildKnown = total > 0
  -- Only trust the roster for logout detection once we've seen that addon
  -- sender names and roster names actually match on this client.
  if not self.guildNamesMatch then
    for name, peer in pairs(self.list) do
      if not peer.demo and LookupLoose(self.guildOnline, name) ~= nil then
        self.guildNamesMatch = true
        ns.Debug("guild roster names match addon sender names")
        break
      end
    end
  end
end

-- Level/zone for a peer: from group unit if grouped, else the guild roster.
function P:GetInfo(peer)
  if peer.demo then return { level = peer.level, zone = peer.zone } end
  local unit = self:FindRosterUnit(peer.name)
  if unit then
    local level = UnitLevel(unit)
    if ns.IsSecret(level) then level = nil end
    local g = self.guildInfo and LookupLoose(self.guildInfo, peer.name)
    return { level = level, zone = g and g.zone }
  end
  return (self.guildInfo and LookupLoose(self.guildInfo, peer.name)) or {}
end

-- Guildmates (and other peers) ranked by how many quests they share with
-- you. Ties go to whoever is closest to your level.
function P:GetBuddies()
  local myLevel = UnitLevel("player")
  if ns.IsSecret(myLevel) then myLevel = nil end
  local out = {}
  for name, peer in pairs(self.list) do
    if peer.hasState then
      local shared = {}
      for qid in pairs(peer.quests) do
        if ns.QuestState.quests[qid] then shared[#shared + 1] = qid end
      end
      local canShare = self:ShareableFrom(peer)
      if #shared > 0 or #canShare > 0 then
        table.sort(shared)
        local info = self:GetInfo(peer)
        out[#out + 1] = {
          name = name, class = self:GetClass(peer), shared = shared, canShare = canShare,
          level = info.level, zone = info.zone, hasAddon = true,
          unit = self:FindRosterUnit(name), peer = peer,
        }
      end
    end
  end
  -- Group members without the addon: the game tells us which of our quests
  -- they're on while they're nearby (same rule as everywhere else in Queb).
  for name, unit in pairs(self.roster) do
    local peer = self:FindPeer(name)
    if not (peer and peer.hasState) then
      local info = self:SharedWith(name, true)
      if info.status == "group" and #info.shared > 0 then
        local shared = {}
        for i, s in ipairs(info.shared) do shared[i] = s.questID end
        local _, classFile = UnitClass(unit)
        if ns.IsSecret(classFile) then classFile = nil end
        local level = UnitLevel(unit)
        if ns.IsSecret(level) then level = nil end
        local g = self.guildInfo and LookupLoose(self.guildInfo, name)
        out[#out + 1] = {
          name = name, class = classFile, shared = shared, canShare = {},
          level = level, zone = g and g.zone, hasAddon = false,
          unit = unit, peer = nil,
        }
      end
    end
  end
  -- shared quests first, then quests they can share with you
  table.sort(out, function(a, b)
    if #a.shared ~= #b.shared then return #a.shared > #b.shared end
    if #a.canShare ~= #b.canShare then return #a.canShare > #b.canShare end
    if myLevel then
      local da = a.level and math.abs(a.level - myLevel) or 99
      local db = b.level and math.abs(b.level - myLevel) or 99
      if da ~= db then return da < db end
    end
    return a.name < b.name
  end)
  return out
end

-- Guildmates on a similar path but with no shared quests: online, within
-- `nearbyLevelRange` levels of you; same zone first. Includes guildmates
-- without the addon (level/zone come from the guild roster).
-- `exclude` = { [name] = true } for people already listed as buddies.
function P:GetNearby(exclude)
  local out = {}
  local myLevel = UnitLevel("player")
  if ns.IsSecret(myLevel) or not myLevel then return out end
  local myZone = GetRealZoneText and GetRealZoneText() or nil
  if ns.IsSecret(myZone) then myZone = nil end
  local range = ns.db.nearbyLevelRange or 3
  local seen = {}

  local function consider(name, class, level, zone, hasAddon, peer)
    if seen[name] or (exclude and exclude[name]) or ns.IsMe(name) then return end
    seen[name] = true
    if not level or math.abs(level - myLevel) > range then return end
    out[#out + 1] = {
      name = name, class = class, level = level, zone = zone, hasAddon = hasAddon,
      sameZone = (myZone ~= nil and zone == myZone), unit = self:FindRosterUnit(name), peer = peer,
    }
  end

  for name, peer in pairs(self.list) do
    if peer.sources.GUILD then
      local info = self:GetInfo(peer)
      consider(name, self:GetClass(peer), info.level, info.zone, true, peer)
    end
  end
  for name, info in pairs(self.guildInfo or {}) do
    -- skip roster entries that are just another spelling of a known peer
    local known = false
    for _, v in ipairs(ns.NameVariants(name)) do
      if seen[v] or self.list[v] then known = true end
    end
    if not known then
      local class = self.guildOnline[name]
      consider(name, class or nil, info.level, info.zone, false, nil)
    end
  end

  table.sort(out, function(a, b)
    if a.sameZone ~= b.sameZone then return a.sameZone end
    local da, db = math.abs(a.level - myLevel), math.abs(b.level - myLevel)
    if da ~= db then return da < db end
    if a.hasAddon ~= b.hasAddon then return a.hasAddon end
    return a.name < b.name
  end)
  return out
end

function P:GetClass(peer)
  if peer.class then return peer.class end
  local unit = self:FindRosterUnit(peer.name)
  if unit then
    local _, classFile = UnitClass(unit)
    if classFile and not ns.IsSecret(classFile) then return classFile end
  end
  local c = LookupLoose(self.guildOnline, peer.name)
  if c then return c end
end

function P:Prune()
  local now = GetTime()
  local timeout = (ns.db.peerTimeoutMinutes or 15) * 60
  local changed = false
  for name, peer in pairs(self.list) do
    if not peer.demo then
      local inGroup = self:FindRosterUnit(name) ~= nil
      if not inGroup then peer.sources.GROUP = nil end
      if not ns.db.shareGuild then peer.sources.GUILD = nil end
      -- guildmate logged out: the roster says offline (only trust a matched name)
      if peer.sources.GUILD and self.guildKnown and self.guildNamesMatch
         and LookupLoose(self.guildOnline, name) == nil then
        local seenRecently = (now - (peer.lastSeen or 0)) < 120
        if not seenRecently then peer.sources.GUILD = nil end
      end
      local expired = (now - (peer.lastSeen or 0)) > timeout and not inGroup
      if expired or not next(peer.sources) then
        self.list[name] = nil
        changed = true
      end
    end
  end
  if changed then self:Changed() end
end

local SOURCE_ORDER = { guild = 1, group = 2, demo = 3, other = 4 }

-- Returns an array of sharers for questID:
-- { name, unit?, source = "group"|"guild"|"demo"|"other", hasAddon,
--   complete?, objectives? }   (complete/objectives nil when unknown)
function P:GetSharers(questID)
  local out = {}
  local covered = {}

  for name, peer in pairs(self.list) do
    local unit = self:FindRosterUnit(name)
    if unit then covered[unit] = true end
    local q = peer.quests[questID]
    if q then
      local source = (peer.sources.GUILD and "guild") or (unit and "group") or (peer.demo and "demo") or "other"
      out[#out + 1] = {
        name = name, unit = unit, source = source, hasAddon = true,
        class = self:GetClass(peer), complete = q.c, objectives = q.obj,
      }
    elseif unit and not peer.hasState then
      covered[unit] = nil -- we know them but have no data yet: fall back below
    end
  end

  if ns.db.showNonAddonParty and C_QuestLog.IsUnitOnQuest then
    for name, unit in pairs(self.roster) do
      if not covered[unit] then
        local ok, onQuest = pcall(C_QuestLog.IsUnitOnQuest, unit, questID)
        if ok and not ns.IsSecret(onQuest) and onQuest then
          local _, classFile = UnitClass(unit)
          if ns.IsSecret(classFile) then classFile = nil end
          out[#out + 1] = { name = name, unit = unit, source = "group", hasAddon = false, class = classFile }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    local oa, ob = SOURCE_ORDER[a.source] or 9, SOURCE_ORDER[b.source] or 9
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  return out
end

---------------------------------------------------------------------------
-- Demo peers (Settings > Demo guildmates) so the UI can be checked while solo.
---------------------------------------------------------------------------
function P:SetDemo(on)
  for name, peer in pairs(self.list) do
    if peer.demo then self.list[name] = nil end
  end
  if on then
    local ids = {}
    for qid in pairs(ns.QuestState.quests) do ids[#ids + 1] = qid end
    table.sort(ids)
    -- Two-part names on purpose, to exercise name handling.
    local fakes = {
      { "Demo Paladin", "PALADIN" }, { "Demo Mage", "MAGE" }, { "Demo Druid", "DRUID" },
      { "Demo Rogue", "ROGUE" }, { "Demo Hunter", "HUNTER" }, { "Demo Priest", "PRIEST" },
      { "Demo Warlock", "WARLOCK" },
    }
    local myLevel = UnitLevel("player")
    if ns.IsSecret(myLevel) then myLevel = 10 end
    local zone = GetRealZoneText and GetRealZoneText() or nil
    if ns.IsSecret(zone) then zone = nil end
    for k, f in ipairs(fakes) do
      local peer = { name = f[1], class = f[2], sources = { GUILD = true }, entries = {}, quests = {},
                     hasState = true, demo = true, lastSeen = GetTime(),
                     level = math.max(1, myLevel + (k % 3) - 1), zone = zone }
      -- quest i gets a different number of sharers (1..7) so every layout shows up
      for i = 1, math.min(7, #ids) do
        if k <= i then
          local mine = ns.QuestState.quests[ids[i]]
          local q = { c = (k == 1 and i == 2), obj = {} }
          for j, o in ipairs(mine.obj) do q.obj[j] = { math.floor(o[2] * k / 7), o[2] } end
          peer.quests[ids[i]] = q
        end
      end
      self.list[peer.name] = peer
    end
    -- roles (some with two, one with none) so the role icons show up
    local demoRoles = {
      ["Demo Paladin"] = { tank = true, healer = true }, ["Demo Mage"] = { damage = true },
      ["Demo Druid"] = { healer = true }, ["Demo Rogue"] = { damage = true },
      ["Demo Priest"] = { healer = true, damage = true }, ["Demo Warlock"] = {},
    }
    for name, roles in pairs(demoRoles) do
      if self.list[name] then self.list[name].roles = roles end
    end
    -- guildmates with no shared quests, to show the "near your level" section
    local nearby = { { "Demo Shaman", "SHAMAN", 0, zone }, { "Demo Warrior", "WARRIOR", 2, "Somewhere Else" } }
    for _, f in ipairs(nearby) do
      self.list[f[1]] = { name = f[1], class = f[2], sources = { GUILD = true }, entries = {}, quests = {},
                          hasState = true, demo = true, lastSeen = GetTime(),
                          level = math.max(1, myLevel + f[3]), zone = f[4] }
    end
    self.list["Demo Shaman"].roles = { healer = true }
    self.list["Demo Warrior"].roles = { tank = true, damage = true }
    -- "Can share": made-up quests (IDs no real quest uses) they can share with
    -- you, and your own quests they'd like from you.
    local demoQuests = {
      { "Demo Shaman", 9900001, "Demo: Lost Supplies" }, { "Demo Shaman", 9900002, "Demo: Wolf Pelts" },
      { "Demo Paladin", 9900003, "Demo: Old Letter" },
    }
    for _, d in ipairs(demoQuests) do
      local peer = self.list[d[1]]
      peer.push = peer.push or {}
      peer.push[d[2]] = { lvl = myLevel, title = d[3] }
      peer.quests[d[2]] = { c = false, obj = { { 0, 5 } } }
    end
    if ids[1] then self.list["Demo Warrior"].wants = { [ids[1]] = true } end
    if ids[2] then self.list["Demo Shaman"].wants = { [ids[2]] = true } end
    if #ids == 0 then
      ns.Print("Demo on: pick up a quest first")
    else
      ns.Print("Demo on: fake guildmates on " .. math.min(7, #ids) .. " quests")
    end
  else
    ns.Print("Demo off")
  end
  self:Changed()
end

ns.On("GROUP_ROSTER_UPDATE", function()
  P:UpdateRoster()
  ns.Debounce("peers_prune", 2, function() P:Prune() end)
  ns.UI:Refresh()
end)

ns.On("GUILD_ROSTER_UPDATE", function()
  P:UpdateGuildRoster()
  ns.Debounce("peers_prune", 2, function() P:Prune() end)
  P:Changed()
end)

local function RequestGuildRoster()
  if not IsInGuild() then return end
  if C_GuildInfo and C_GuildInfo.GuildRoster then
    C_GuildInfo.GuildRoster()
  elseif GuildRoster then
    GuildRoster()
  end
end

ns.Listen("LOGIN", function()
  P:UpdateRoster()
  RequestGuildRoster()
  C_Timer.NewTicker(60, function()
    RequestGuildRoster()
    P:Prune()
  end)
end)
