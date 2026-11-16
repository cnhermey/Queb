-- Queb: dungeon quest check (v0.14.0).
--
-- Helps experienced players make sure a group / guildmates are on all the
-- right quests before a dungeon:
--   * which quests belong to which dungeon: DungeonJournal's curated list
--     (global namespace ForeverDungeonJournal_NS, read defensively; no public
--     API), else Questie's database (QuestieDB: global QuestDB + Questie's
--     ZoneDB dungeon table). Without either, the Dungeons section says so.
--   * each person's status per quest. "In log" comes from Queb's normal sync
--     (ST/QU). "Done", "can pick up", "needs pre-quest", "level too low" and
--     "not for them" can only be worked out on that player's own client, so
--     the helper asks (DQ) and the player's Queb answers (DA).
--
-- Wire (backward compatible, no protocol bump; older builds ignore both):
--   DQ  name,name,...;qid,qid,...      "named players: your status for these quests"
--   DA  requester;qidC,qidC,...  or  requester;-   (C = one status letter; "-" = not shared)
-- Every client that hears a DA keeps the sender's answers (they're the
-- sender's own facts), so one answer serves everyone on the channel.
--
-- Status letters:
--   L in log · R ready to turn in · D done · A can pick up · P needs pre-quest
--   V level too low · X not for them (class/faction/profession, or lost)
--   ? unknown (no quest database on their side)
-- Display-only (never on the wire): S syncing · U update Queb · N not shared
--   Q no Queb · F too far away · O offline
local _, ns = ...

local D = {
  list = nil,          -- array of dungeons (see Build*)
  byKey = {},          -- [key] = dungeon
  fdjIndex = {},       -- [questID] = DungeonJournal quest table
  source = nil,        -- "DungeonJournal" | "Questie" | nil
  building = false,
  stats = { asked = 0, answered = 0, heard = 0 },
  lastAsk = {},        -- [channel .. key] = GetTime()
}
ns.Dungeons = D

local MIN_VERSION = "0.14.0" -- first build that answers DQ
local MAX_QIDS = 60
local MAX_NAMES = 40
local ASK_EVERY = 30         -- seconds between DQ for the same dungeon + channel
local MAX_PEOPLE = 12        -- status columns per dungeon

D.MIN_VERSION = MIN_VERSION
D.MAX_PEOPLE = MAX_PEOPLE

D.TEXT = {
  L = "on quest", R = "ready to turn in", D = "done", A = "can pick up",
  P = "needs pre-quest", V = "level too low", X = "not for them", ["?"] = "unknown",
  S = "syncing", U = "update Queb", N = "not shared", Q = "no Queb", F = "too far away", O = "offline",
}
local WIRE = { L = true, R = true, D = true, A = true, P = true, V = true, X = true, ["?"] = true }

local function Num(v)
  if v == nil or ns.IsSecret(v) then return nil end
  return tonumber(v)
end

local function MyLevel() return Num(UnitLevel("player")) end

local function MyFaction()
  local ok, f = pcall(UnitFactionGroup, "player")
  if ok and type(f) == "string" and not ns.IsSecret(f) and f ~= "" then return f end
end

local function MyClass()
  local _, c = UnitClass("player")
  if type(c) == "string" and not ns.IsSecret(c) then return c end
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local function FDJ()
  local t = _G.ForeverDungeonJournal_NS
  if type(t) == "table" and type(t.DB) == "table" then return t end
end
D.FDJ = FDJ

local function QuestieModule(name)
  local L = _G.QuestieLoader
  local mods = type(L) == "table" and rawget(L, "_modules")
  local m = type(mods) == "table" and mods[name]
  if type(m) == "table" then return m end
end

-- Public QuestieDB (LibQuestieDB) quest accessors, if present.
local function QDB()
  local q = _G.QuestDB
  if type(q) == "table" and type(q.GetAllIds) == "function" and type(q.zoneOrSort) == "function" then return q end
end

local function QField(fn, qid)
  local q = QDB()
  local f = q and q[fn]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, qid)
  if ok then return v end
end

-- "13-20" -> 13, 20
local function ParseRange(s)
  if type(s) == "number" then return s, s end
  if type(s) ~= "string" then return nil end
  local a, b = string.match(s, "(%d+)%D+(%d+)")
  if a then return tonumber(a), tonumber(b) end
  a = string.match(s, "(%d+)")
  if a then return tonumber(a), tonumber(a) end
end

local function Sort(list)
  table.sort(list, function(a, b)
    if (a.minL or 99) ~= (b.minL or 99) then return (a.minL or 99) < (b.minL or 99) end
    return a.name < b.name
  end)
end

local function Finish(list, source)
  Sort(list)
  D.list, D.source = list, source
  wipe(D.byKey)
  for _, d in ipairs(list) do D.byKey[d.key] = d end
  D.building = false
  ns.Debug("dungeons:", #list, "from", source)
  ns.Fire("DUNGEONS_READY")
end

local function BuildFromFDJ(F)
  local list = {}
  wipe(D.fdjIndex)
  for name, def in pairs(F.DB) do
    if type(name) == "string" and type(def) == "table" and type(def.quests) == "table" then
      local qs = {}
      for _, q in ipairs(def.quests) do
        if type(q) == "table" and type(q.id) == "number" and q.id > 0 then
          D.fdjIndex[q.id] = q
          if not q.hideFromMainList and not q.repeatable and not q.unavailable then
            qs[#qs + 1] = {
              id = q.id,
              name = type(q.name) == "string" and q.name or nil,
              level = tonumber(q.level),
              req = tonumber(q.requires),
              faction = (q.faction == "Alliance" or q.faction == "Horde") and q.faction or nil,
              classOnly = type(q.classOnly) == "string" and string.upper(q.classOnly) or nil,
              pickup = type(q.pickup) == "string" and q.pickup or nil,
            }
          end
        end
      end
      if #qs > 0 then
        local minL, maxL = ParseRange(def.level)
        list[#list + 1] = { key = name, name = name, minL = minL, maxL = maxL, quests = qs }
      end
    end
  end
  Finish(list, "DungeonJournal")
end

-- Questie fallback: every quest whose zone is a dungeon in Questie's zone
-- table. Scanned in small batches so login doesn't hitch.
local NOT_DUNGEONS = { [2597] = true, [3277] = true, [3358] = true } -- battlegrounds
local function QuestieDungeonTable()
  local z = QuestieModule("ZoneDB")
  local p = z and rawget(z, "private")
  local t = type(p) == "table" and p.dungeons
  if type(t) == "table" then return t end
end

local function Band(a, b)
  if bit and bit.band then return bit.band(a, b) end
  return nil
end

local function FactionFromRaces(races)
  local Lq = _G.LibQuestieDB
  local masks = type(Lq) == "table" and type(Lq.Enum) == "table" and Lq.Enum.factionRaceMasks
  if type(races) ~= "number" or races == 0 or type(masks) ~= "table" then return nil end
  local a, h = Band(races, masks.Alliance or 0), Band(races, masks.Horde or 0)
  if a == nil then return nil end
  if a ~= 0 and h == 0 then return "Alliance" end
  if h ~= 0 and a == 0 then return "Horde" end
end

local function ClassFromMask(mask)
  local Lq = _G.LibQuestieDB
  local keys = type(Lq) == "table" and type(Lq.Enum) == "table" and Lq.Enum.classKeys
  if type(mask) ~= "number" or mask == 0 or type(keys) ~= "table" then return nil end
  local found
  for token, v in pairs(keys) do
    if type(v) == "number" and v > 0 and Band(mask, v) and Band(mask, v) ~= 0 then
      if found then return nil end -- several classes: don't restrict
      found = token
    end
  end
  return type(found) == "string" and string.upper(found) or nil
end

local function BuildFromQuestie(dungeons)
  local q = QDB()
  local okIds, ids = pcall(q.GetAllIds)
  if not okIds or type(ids) ~= "table" then return Finish({}, nil) end
  local areaToKey, byKey = {}, {}
  for area, e in pairs(dungeons) do
    if type(area) == "number" and type(e) == "table" and type(e[1]) == "string" and not NOT_DUNGEONS[area] then
      areaToKey[area] = area
      if type(e[2]) == "table" then
        for _, alt in ipairs(e[2]) do if type(alt) == "number" then areaToKey[alt] = area end end
      end
    end
  end
  D.building = true
  local i, n = 1, #ids
  local function Step()
    local stop = math.min(n, i + 400)
    for k = i, stop do
      local qid = ids[k]
      local okZ, z = pcall(q.zoneOrSort, qid)
      local area = okZ and type(z) == "number" and areaToKey[z]
      if area then
        local d = byKey[area]
        if not d then
          d = { key = "q" .. area, name = dungeons[area][1], quests = {} }
          byKey[area] = d
        end
        local lvl, req = Num(QField("questLevel", qid)), Num(QField("requiredLevel", qid))
        local name = QField("name", qid)
        d.quests[#d.quests + 1] = {
          id = qid, name = type(name) == "string" and name or nil,
          level = (lvl and lvl > 0) and lvl or nil, req = (req and req > 0) and req or nil,
          faction = FactionFromRaces(QField("requiredRaces", qid)),
          classOnly = ClassFromMask(QField("requiredClasses", qid)),
        }
        if lvl and lvl > 0 and lvl <= 60 then
          d.minL = math.min(d.minL or lvl, lvl)
          d.maxL = math.max(d.maxL or lvl, lvl)
        end
      end
    end
    i = stop + 1
    if i <= n then
      C_Timer.After(0, Step)
    else
      local list = {}
      for _, d in pairs(byKey) do
        table.sort(d.quests, function(a, b)
          if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
          return a.id < b.id
        end)
        if d.minL then list[#list + 1] = d end
      end
      Finish(list, "Questie")
    end
  end
  Step()
end

-- Dungeon list; builds it on first use. nil while the Questie scan runs.
function D:GetList()
  if self.list then return self.list end
  if self.building then return nil end
  local F = FDJ()
  if F then
    local ok = pcall(BuildFromFDJ, F)
    if ok then return self.list end
    ns.Debug("DungeonJournal data unreadable")
  end
  local dt = QDB() and QuestieDungeonTable()
  if dt then
    self.building = true
    local ok = pcall(BuildFromQuestie, dt)
    if not ok then self.building = false; Finish({}, nil) end
    return self.list
  end
  return nil -- no source (yet): Questie may still be loading; try again later
end

function D:HasSource()
  return FDJ() ~= nil or (QDB() ~= nil and QuestieDungeonTable() ~= nil)
end

-- Questie's database may become ready after login.
ns.Listen("LOGIN", function()
  local Q = _G.Questie
  local reg = type(Q) == "table" and type(Q.API) == "table" and Q.API.RegisterOnReady
  if type(reg) == "function" then
    pcall(reg, function()
      if not D.list or (#D.list == 0 and not FDJ()) then D.list = nil end
      if ns.Buddies then ns.Buddies:Update() end
    end)
  end
end)

---------------------------------------------------------------------------
-- My own status for one quest (also what we answer in DA)
---------------------------------------------------------------------------
local function InLog(qid)
  local q = ns.QuestState.quests[qid]
  if q then return true, q.c end
  if C_QuestLog.GetLogIndexForQuestID then
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    if ok and type(idx) == "number" and idx > 0 and not ns.IsSecret(idx) then
      local okc, c = pcall(C_QuestLog.IsComplete, qid)
      return true, okc and not ns.IsSecret(c) and c and true or false
    end
  end
  return false
end

local function Done(qid)
  if not C_QuestLog.IsQuestFlaggedCompleted then return nil end
  local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
  if ok and not ns.IsSecret(done) then return done and true or false end
end

function D:LocalStatus(qid)
  local inLog, complete = InLog(qid)
  if inLog then return complete and "R" or "L" end
  if Done(qid) then return "D" end
  local me = MyLevel()
  local F = FDJ()
  if F and not self.list then self:GetList() end -- builds fdjIndex
  local def = F and self.fdjIndex[qid]
  if def then
    if type(F.IsQuestLost) == "function" then
      local ok, lost = pcall(F.IsQuestLost, def)
      if ok and lost then return "X" end
    end
    local mine = MyFaction()
    if (def.faction == "Alliance" or def.faction == "Horde") and mine and def.faction ~= mine then return "X" end
    if type(F.QuestCountsForCharacter) == "function" then
      local ok, counts = pcall(F.QuestCountsForCharacter, def)
      if ok and counts == false then return "X" end
    end
    local req = tonumber(def.requires)
    if req and me and me < req then return "V" end
    local chain
    if type(F.PrereqChainOf) == "function" then
      local ok, c = pcall(F.PrereqChainOf, qid)
      if ok then chain = c end
    end
    if type(chain) ~= "table" or #chain == 0 then return "A" end
    if type(F.QuestChainUnlocked) == "function" then
      local ok, unlocked = pcall(F.QuestChainUnlocked, def)
      if ok then return unlocked and "A" or "P" end
    end
  end
  local req = Num(QField("requiredLevel", qid))
  if req and me and me < req then return "V" end
  local met = ns.Peers:PrereqsMet(qid)
  if met == true then return "A" end
  if met == false then return "P" end
  return "?"
end

---------------------------------------------------------------------------
-- Everyone's status for one quest
---------------------------------------------------------------------------
-- Demo peers: made-up but stable statuses so every icon shows up.
local DEMO_CODES = { "L", "D", "A", "P", "R", "A", "V", "X", "S" }
local function DemoStatus(peer, qid)
  local h = tonumber(string.sub(ns.Hash(peer.name .. qid), 1, 6), 16) or 0
  return DEMO_CODES[(h % #DEMO_CODES) + 1]
end

-- person = { name, isMe?, unit?, peer?, class, level }
function D:Status(person, qid)
  if person.isMe then return self:LocalStatus(qid) end
  local peer = person.peer
  if peer and peer.hasState then
    if peer.demo then return DemoStatus(peer, qid) end
    local q = peer.quests[qid]
    if q then return q.c and "R" or "L" end
    if peer.dqOff then return "N" end
    local c = peer.dq and peer.dq[qid]
    if c and c ~= "L" and c ~= "R" then return c end -- L/R from DA are stale once gone from their log
    if not ns.Peers.VersionAtLeast(peer.ver, MIN_VERSION) then return "U" end
    return "S"
  end
  if peer and not peer.hasState then return "S" end
  local unit = person.unit
  if unit then
    if not ns.db.showNonAddonParty then return "Q" end
    local ok, why = ns.Peers:GroupUnitCheckable(unit)
    if not ok then return why == "offline" and "O" or "F" end
    if C_QuestLog.IsUnitOnQuest then
      local okq, on = pcall(C_QuestLog.IsUnitOnQuest, unit, qid)
      if okq and not ns.IsSecret(on) and on then return "L" end
    end
    return "Q"
  end
  return "?"
end

---------------------------------------------------------------------------
-- Who is checked, and which dungeons are listed
---------------------------------------------------------------------------
-- All candidates: you, group members (setting), guildmates with Queb (setting).
function D:People()
  local out, seen = {}, {}
  local me = ns.UnitKey("player")
  out[1] = { name = me or "You", isMe = true, class = MyClass(), level = MyLevel() }
  if ns.db.dungeonsGroup then
    local names = {}
    for name in pairs(ns.Peers.roster) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      local unit = ns.Peers.roster[name]
      local peer = ns.Peers:FindPeer(name)
      local _, class = UnitClass(unit)
      if ns.IsSecret(class) then class = nil end
      out[#out + 1] = { name = name, unit = unit, peer = peer, group = true,
                        class = (peer and ns.Peers:GetClass(peer)) or class, level = Num(UnitLevel(unit)) }
      seen[name] = true
      if peer then seen[peer.name] = true end
    end
  end
  if ns.db.dungeonsGuild then
    for name, peer in pairs(ns.Peers.list) do
      if not seen[name] and peer.sources.GUILD and peer.hasState then
        local info = ns.Peers:GetInfo(peer)
        out[#out + 1] = { name = name, peer = peer, class = ns.Peers:GetClass(peer), level = info.level }
      end
    end
  end
  return out
end

local function LevelFits(d, level, range)
  if not level or not d.minL then return false end
  return level >= (d.minL - range) and level <= ((d.maxL or d.minL) + range)
end

local function OnAnyQuest(d, person)
  for _, q in ipairs(d.quests) do
    if person.isMe then
      if ns.QuestState.quests[q.id] then return true end
    elseif person.peer and person.peer.quests[q.id] then
      return true
    end
  end
  return false
end

-- Quests of `d` worth showing: your faction; class quests only if someone
-- shown is that class.
local function VisibleQuests(d, people)
  local faction = MyFaction()
  local classes = {}
  for _, p in ipairs(people) do if p.class then classes[p.class] = true end end
  local out = {}
  for _, q in ipairs(d.quests) do
    if not (q.faction and faction and q.faction ~= faction) and not (q.classOnly and not classes[q.classOnly]) then
      out[#out + 1] = q
    end
  end
  return out
end

-- The dungeons to list, each with its people (columns) and quests (rows):
-- { dungeon, people = {...}, quests = {...} }. Listed: dungeons near your
-- level or a group member's level (± Level range), plus any dungeon someone
-- shown is on a quest for.
function D:Blocks()
  local list = self:GetList()
  if not list then return nil end
  local all = self:People()
  local range = ns.db.nearbyLevelRange or 3
  local out = {}
  for _, d in ipairs(list) do
    local people = {}
    local listed = false
    for _, p in ipairs(all) do
      local fits, on = LevelFits(d, p.level, range), OnAnyQuest(d, p)
      if (p.isMe or p.group) and fits then listed = true end
      if on then listed = true end
      if p.group or fits or on then people[#people + 1] = p end
    end
    if listed and #people > 0 then
      -- you, group, then guildmates closest to the dungeon's level
      local mid = ((d.minL or 0) + (d.maxL or d.minL or 0)) / 2
      table.sort(people, function(a, b)
        if (a.isMe and true or false) ~= (b.isMe and true or false) then return a.isMe and true or false end
        if (a.group and true or false) ~= (b.group and true or false) then return a.group and true or false end
        local da, db = a.level and math.abs(a.level - mid) or 99, b.level and math.abs(b.level - mid) or 99
        if da ~= db then return da < db end
        return a.name < b.name
      end)
      for k = #people, MAX_PEOPLE + 1, -1 do people[k] = nil end
      local quests = VisibleQuests(d, people)
      if #quests > 0 then out[#out + 1] = { dungeon = d, people = people, quests = quests } end
    end
  end
  return out
end

-- The dungeon you're in, if it's one we know (opens its block by default).
function D:CurrentKey()
  if not IsInInstance then return nil end
  local ok, inInstance = pcall(IsInInstance)
  if not ok or not inInstance or ns.IsSecret(inInstance) then return nil end
  local name = GetInstanceInfo and GetInstanceInfo()
  if type(name) ~= "string" or ns.IsSecret(name) then return nil end
  local F = FDJ()
  if F and type(F.DungeonFromInstanceName) == "function" then
    local okk, key = pcall(F.DungeonFromInstanceName, name)
    if okk and key and self.byKey[key] then return key end
  end
  for key, d in pairs(self.byKey) do
    if d.name == name then return key end
  end
end

function D:IsOpen(key)
  local o = ns.db.dungeonOpen
  if type(o) == "table" and o[key] ~= nil then return o[key] end
  return key == self:CurrentKey()
end

function D:SetOpen(key, open)
  ns.db.dungeonOpen = type(ns.db.dungeonOpen) == "table" and ns.db.dungeonOpen or {}
  ns.db.dungeonOpen[key] = open and true or false
end

---------------------------------------------------------------------------
-- Asking (DQ) and answering (DA)
---------------------------------------------------------------------------
-- Ask the people of an open block for the statuses only they can know.
function D:Ask(block)
  local byChannel = {}
  local groupCh = ns.GetGroupChannel()
  for _, p in ipairs(block.people) do
    local peer = p.peer
    if peer and peer.hasState and not peer.demo and ns.Peers.VersionAtLeast(peer.ver, MIN_VERSION) then
      local ch
      if p.group and groupCh and ns.Comm:IsActive(groupCh) then
        ch = groupCh
      elseif peer.sources.GUILD and ns.Comm:IsActive("GUILD") then
        ch = "GUILD"
      end
      if ch then
        byChannel[ch] = byChannel[ch] or {}
        local t = byChannel[ch]
        if #t < MAX_NAMES then t[#t + 1] = peer.name end
      end
    end
  end
  if not next(byChannel) then return end
  local ids = {}
  for k = 1, math.min(#block.quests, MAX_QIDS) do ids[k] = tostring(block.quests[k].id) end
  local now = GetTime()
  for ch, names in pairs(byChannel) do
    local key = ch .. "|" .. block.dungeon.key
    if not self.lastAsk[key] or now - self.lastAsk[key] >= ASK_EVERY then
      self.lastAsk[key] = now
      table.sort(names)
      ns.Comm:Send("DQ", table.concat(names, ",") .. ";" .. table.concat(ids, ","), ch)
      self.stats.asked = self.stats.asked + 1
    end
  end
end

local pendingAnswer = {} -- [channel] = { requester = name, ids = {qid=true} }
local function Answer(channel)
  local p = pendingAnswer[channel]
  pendingAnswer[channel] = nil
  if not p or not ns.Comm:IsActive(channel) then return end
  local payload
  if not ns.db.shareDungeonQuests then
    payload = p.requester .. ";-"
  else
    local ids = {}
    for qid in pairs(p.ids) do ids[#ids + 1] = qid end
    table.sort(ids)
    local parts = {}
    for k = 1, math.min(#ids, MAX_QIDS) do
      local ok, c = pcall(D.LocalStatus, D, ids[k])
      parts[#parts + 1] = ids[k] .. ((ok and WIRE[c]) and c or "?")
    end
    payload = p.requester .. ";" .. table.concat(parts, ",")
  end
  ns.Comm:Send("DA", payload, channel)
  D.stats.answered = D.stats.answered + 1
end

ns.Comm.handlers.DQ = function(self, body, channel, sender, src)
  local names, qids = string.match(body, "^([^;]*);(.*)$")
  if not names then return end
  local forMe = false
  local list = ns.Split(names, ",")
  for k = 1, math.min(#list, MAX_NAMES) do
    if list[k] == "*" or ns.IsMe(list[k]) then forMe = true break end
  end
  ns.Peers:Touch(sender, src)
  if not forMe then return end
  local p = pendingAnswer[channel] or { requester = sender, ids = {} }
  pendingAnswer[channel] = p
  p.requester = sender
  local ids = ns.Split(qids, ",")
  local n = 0
  for _ in pairs(p.ids) do n = n + 1 end
  for k = 1, #ids do
    local qid = tonumber(ids[k])
    if qid and qid > 0 and qid <= 10000000 and qid == math.floor(qid) and n < MAX_QIDS and not p.ids[qid] then
      p.ids[qid] = true
      n = n + 1
    end
  end
  -- several helpers asking at once share one answer
  local delay = channel == "GUILD" and (1 + math.random() * 2) or (0.3 + math.random() * 0.7)
  ns.Coalesce("da:" .. channel, delay, function() Answer(channel) end)
end

ns.Comm.handlers.DA = function(self, body, channel, sender, src)
  local requester, list = string.match(body, "^([^;]*);(.*)$")
  if not requester then return end
  local peer = ns.Peers:Touch(sender, src)
  if not peer then return end
  D.stats.heard = D.stats.heard + 1
  if list == "-" then
    peer.dqOff = true
    peer.dq = nil
  else
    peer.dqOff = nil
    peer.dq = peer.dq or {}
    local parts = ns.Split(list, ",")
    for k = 1, math.min(#parts, MAX_QIDS) do
      local qid, c = string.match(parts[k], "^(%d+)(.)$")
      qid = tonumber(qid)
      if qid and qid > 0 and qid <= 10000000 and WIRE[c] then peer.dq[qid] = c end
    end
  end
  peer.dqTime = GetTime()
  ns.Peers:Changed()
end

-- Our answers go stale when we turn in quests or level up: forget what we
-- asked recently so open blocks ask again on the next refresh.
local function Stale() wipe(D.lastAsk) end
ns.On("QUEST_TURNED_IN", function() C_Timer.After(3, Stale) end)
ns.On("PLAYER_LEVEL_UP", Stale)
ns.On("GROUP_ROSTER_UPDATE", function() ns.Debounce("dq_stale", 2, Stale) end)

---------------------------------------------------------------------------
-- Sharing a quest from the Dungeons section (same steps DungeonJournal uses)
---------------------------------------------------------------------------
function D:CanShareNow(qid)
  if not IsInGroup() then return false end
  local q = ns.QuestState.quests[qid]
  return q ~= nil and q.push == true
end

function D:Share(qid)
  if not self:CanShareNow(qid) then return false end
  if C_QuestLog.SetSelectedQuest then
    pcall(C_QuestLog.SetSelectedQuest, qid)
  elseif SelectQuestLogEntry and C_QuestLog.GetLogIndexForQuestID then
    local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
    if ok and type(idx) == "number" and idx > 0 then pcall(SelectQuestLogEntry, idx) end
  end
  if type(QuestLogPushQuest) == "function" then
    pcall(QuestLogPushQuest)
    return true
  end
  return false
end

-- Quest title for display: our log, the source's name, the game.
function D:Title(q)
  return (ns.QuestState.quests[q.id] and ns.QuestState.quests[q.id].title) or q.name
    or ns.QuestState:GetTitle(q.id) or ("Quest " .. q.id)
end

-- Pre-quests DungeonJournal lists for a quest (names), or nil.
function D:PrereqNames(qid)
  local F = FDJ()
  if not F or type(F.PrereqChainOf) ~= "function" then return nil end
  local ok, chain = pcall(F.PrereqChainOf, qid)
  if not ok or type(chain) ~= "table" or #chain == 0 then return nil end
  local names = {}
  for _, step in ipairs(chain) do
    if type(step) == "table" and type(step.name) == "string" and step.id ~= qid then
      names[#names + 1] = step.name
    end
  end
  return #names > 0 and names or nil
end
