-- Queb: addon-to-addon sync.
--
-- Wire frame (one addon message, <= 255 bytes):
--   <protocol>:<TYPE>:<msgId>:<part>:<parts>:<payload chunk>
-- Payloads (after reassembly):
--   HI  addonVersion;stateHash;wantState(0|1);CLASS     presence / heartbeat
--   RQ  name,name,...  or  *                            "send your full state"
--   ST  stateHash;CLASS;entry;entry;...                 full quest state
--   QU  stateHash;entry;entry;...                       changed quests ("qid,-" = removed)
--   WT  qid,qid,...  or  -                              quests I could take from a guildmate
-- Entry format: see ns.EncodeEntry (Util.lua).
-- ST/QU may also carry "can share" parts (!qid:level:title, ns.EncodeShare)
-- for quests the sender can share. Older builds skip those parts and ignore
-- WT, so this needs no protocol bump. Neither is part of the state hash.
--
-- Everything is state-based and idempotent, so when sending is blocked
-- (instances, throttling) we drop messages and resync the full state later
-- instead of queueing an ever-growing backlog. Incoming data is only parsed,
-- never executed.
local _, ns = ...

local C = {
  blocked = {},      -- [channel] = true after a failed send
  needResync = {},   -- [channel] = true: send full state when unblocked
  lastReq = {},      -- [channel|name] = time of last RQ we sent for that peer
  wasInGroup = false,
  stats = { sent = 0, recv = 0, dropped = 0, throttled = 0 },
}
ns.Comm = C

local PREFIX = ns.PREFIX
local MAX_LEN = 255
-- ChatThrottleLib defaults to 800 B/s with a 4000 B burst; we stay at half.
local CPS, BURST, OVERHEAD = 400, 2000, 40
local HEARTBEAT = 300 -- seconds between presence pings

local myClass
local function MyClass()
  if not myClass then
    local _, c = UnitClass("player")
    if c and not ns.IsSecret(c) then myClass = c end
  end
  return myClass or ""
end

local function ValidClass(c)
  if c and string.match(c, "^%u+$") and #c <= 16 then return c end
end

---------------------------------------------------------------------------
-- Outbound queue with a token bucket
---------------------------------------------------------------------------
local queue = {}
local bucket, lastRefill = BURST, 0
local pumpTicker

local R = Enum and Enum.SendAddonMessageResult
local function IsSuccess(res)
  if res == nil or res == true then return true end
  if res == false then return false end
  if R and R.Success ~= nil then return res == R.Success end
  return res == 0
end
local function IsThrottle(res)
  if not R then return false end
  return res == R.AddonMessageThrottle or res == R.ChannelThrottle
end

function C:MarkBlocked(channel)
  if not self.blocked[channel] then
    ns.Debug("sending blocked on", channel, "- will resync later")
  end
  self.blocked[channel] = true
  self.needResync[channel] = true
end

local function Pump()
  local now = GetTime()
  bucket = math.min(BURST, bucket + (now - lastRefill) * CPS)
  lastRefill = now
  while queue[1] do
    local m = queue[1]
    if C.blocked[m.channel] then
      table.remove(queue, 1)
      C.stats.dropped = C.stats.dropped + 1
      C.needResync[m.channel] = true
    else
      local cost = #m.text + OVERHEAD
      if bucket < cost then break end
      local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.channel, m.target)
      if ok and IsSuccess(res) then
        table.remove(queue, 1)
        bucket = bucket - cost
        C.stats.sent = C.stats.sent + 1
      elseif ok and IsThrottle(res) then
        C.stats.throttled = C.stats.throttled + 1
        bucket = 0
        break
      else
        ns.Debug("send failed:", m.channel, ok and ("result " .. tostring(res)) or res)
        C:MarkBlocked(m.channel) -- next loop iteration drops it
      end
    end
  end
  if not queue[1] and pumpTicker then
    pumpTicker:Cancel()
    pumpTicker = nil
  end
end

local function Enqueue(channel, text, target)
  queue[#queue + 1] = { channel = channel, text = text, target = target }
  Pump()
  if queue[1] and not pumpTicker then
    pumpTicker = C_Timer.NewTicker(0.2, Pump)
  end
end

local msgId = 0
function C:Send(msgType, payload, channel, target)
  if not channel or self.blocked[channel] then
    if channel then self.needResync[channel] = true end
    return
  end
  msgId = (msgId % 999) + 1
  local head = ns.PROTOCOL .. ":" .. msgType .. ":" .. msgId .. ":"
  local room = MAX_LEN - #head - 6 -- leave space for "pp:nn:"
  local total = math.max(1, math.ceil(#payload / room))
  if total > 99 then
    ns.Debug("payload too large, not sent:", msgType, #payload)
    return
  end
  for i = 1, total do
    local chunk = string.sub(payload, (i - 1) * room + 1, i * room)
    Enqueue(channel, head .. i .. ":" .. total .. ":" .. chunk, target)
  end
end

---------------------------------------------------------------------------
-- Which channels we talk on
---------------------------------------------------------------------------
function C:ActiveChannels()
  local t = {}
  if ns.db.shareGuild and IsInGuild() then t[#t + 1] = "GUILD" end
  if ns.db.shareParty then
    local g = ns.GetGroupChannel()
    if g then t[#t + 1] = g end
  end
  return t
end

function C:IsActive(channel)
  for _, ch in ipairs(self:ActiveChannels()) do
    if ch == channel then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- High-level sends
---------------------------------------------------------------------------
function C:SendHello(channel, wantState)
  if not self:IsActive(channel) then return end
  local payload = ns.VERSION .. ";" .. ns.QuestState.hash .. ";" .. (wantState and "1" or "0") .. ";" .. MyClass()
  self:Send("HI", payload, channel)
end

function C:SendState(channel)
  if not self:IsActive(channel) or not ns.QuestState.ready then return end
  local qs = ns.QuestState:StatePayload() -- "hash;entry;entry"
  local hash, rest = string.match(qs, "^([^;]*);?(.*)$")
  local payload = hash .. ";" .. MyClass()
  if rest and rest ~= "" then payload = payload .. ";" .. rest end
  local shares = ns.QuestState:ShareParts()
  if #shares > 0 then payload = payload .. ";" .. table.concat(shares, ";") end
  self:Send("ST", payload, channel)
end

-- Quests we could take from guildmates (they show "Can share with" on their
-- side). Sent when the set changes, and with our state.
local MAX_WANTS = 60
C.lastWants = {} -- [channel] = payload last sent
function C:SendWants(channel, force)
  if not self:IsActive(channel) then return end
  local ids = ns.Peers:ComputeWants()
  local list = {}
  for i = 1, math.min(#ids, MAX_WANTS) do list[i] = tostring(ids[i]) end
  local payload = #list > 0 and table.concat(list, ",") or "-"
  if not force and self.lastWants[channel] == payload then return end
  if not self.lastWants[channel] and payload == "-" and not force then return end -- nothing to say yet
  self.lastWants[channel] = payload
  self:Send("WT", payload, channel)
end

function C:ScheduleWants()
  for _, ch in ipairs(self:ActiveChannels()) do
    local delay = ch == "GUILD" and 8 or 2
    ns.Coalesce("wt:" .. ch, delay, function() C:SendWants(ch) end)
  end
end

function C:ScheduleState(channel)
  -- jitter so a whole guild doesn't answer in the same instant
  local delay = channel == "GUILD" and (2 + math.random() * 6) or (0.5 + math.random() * 1.5)
  ns.Coalesce("st:" .. channel, delay, function()
    C:SendState(channel)
    -- a newcomer also needs our wants (they can't ask for them separately)
    if C.lastWants[channel] and C.lastWants[channel] ~= "-" then C:SendWants(channel, true) end
  end)
end

local pendingReq = {}
function C:ScheduleRequest(channel, name)
  local key = channel .. "|" .. name
  local now = GetTime()
  if self.lastReq[key] and now - self.lastReq[key] < 20 then return end
  self.lastReq[key] = now
  pendingReq[channel] = pendingReq[channel] or {}
  pendingReq[channel][name] = true
  ns.Coalesce("rq:" .. channel, 1, function()
    local names = {}
    for n in pairs(pendingReq[channel] or {}) do names[#names + 1] = n end
    pendingReq[channel] = nil
    if #names > 0 then C:Send("RQ", table.concat(names, ","), channel) end
  end)
end

local pendingUpd = {} -- [channel] = { [questID] = true }
function C:FlushUpdates(channel)
  local p = pendingUpd[channel]
  pendingUpd[channel] = nil
  if not p or not self:IsActive(channel) then return end
  local qs = ns.QuestState
  local parts = { qs.hash }
  local count = 0
  local shares = {}
  for qid in pairs(p) do
    count = count + 1
    parts[#parts + 1] = qs.serialized[qid] or (qid .. ",-")
    local sp = qs.serialized[qid] and qs:SharePart(qid)
    if sp then shares[#shares + 1] = sp end
  end
  if count == 0 then return end
  if count > 15 then return self:SendState(channel) end
  for _, sp in ipairs(shares) do parts[#parts + 1] = sp end
  self:Send("QU", table.concat(parts, ";"), channel)
end

---------------------------------------------------------------------------
-- Inbound
---------------------------------------------------------------------------
local partial = {}
local PARTIAL_TTL = 30
local warnedNewer = false

function C:OnRaw(text, channel, rawSender)
  local sender = ns.NormalizeName(rawSender)
  if not sender or ns.IsMe(sender) then return end

  local src
  if channel == "GUILD" then
    if not ns.db.shareGuild then return end
    src = "GUILD"
  elseif channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
    if not ns.db.shareParty then return end
    src = "GROUP"
  else
    return
  end

  local ver, mtype, id, i, n, body = string.match(text, "^(%d+):(%u%u):(%d+):(%d+):(%d+):(.*)$")
  ver, i, n = tonumber(ver), tonumber(i), tonumber(n)
  if not ver then return end
  if ver ~= ns.PROTOCOL then
    if ver > ns.PROTOCOL and not warnedNewer then
      warnedNewer = true
      ns.Print("Newer version available")
    end
    return
  end
  if not i or not n or n < 1 or n > 99 or i < 1 or i > n then return end

  if not self.loggedSenderFormat then
    self.loggedSenderFormat = true
    ns.Debug("first sender name as received: [" .. sender .. "] via", channel)
  end
  self.stats.recv = self.stats.recv + 1

  if n == 1 then
    return self:Dispatch(mtype, body, channel, sender, src)
  end

  local now = GetTime()
  for k, p in pairs(partial) do
    if now - p.t > PARTIAL_TTL then partial[k] = nil end
  end
  local key = sender .. "\001" .. id
  local p = partial[key]
  if not p or p.n ~= n then
    p = { n = n, got = 0, parts = {}, t = now }
    partial[key] = p
  end
  if not p.parts[i] then
    p.parts[i] = body
    p.got = p.got + 1
  end
  if p.got == n then
    partial[key] = nil
    self:Dispatch(mtype, table.concat(p.parts, "", 1, n), channel, sender, src)
  end
end

C.handlers = {}

function C:Dispatch(mtype, body, channel, sender, src)
  local h = self.handlers[mtype]
  if h then h(self, body, channel, sender, src) end
end

local function IsHash(h) return h and string.match(h, "^%x%x%x%x%x%x%x%x$") ~= nil end

C.handlers.HI = function(self, body, channel, sender, src)
  local f = ns.Split(body, ";")
  local addonVer, hash, want, class = f[1], f[2], f[3], f[4]
  if not IsHash(hash) then return end
  local peer = ns.Peers:Touch(sender, src)
  if not peer then return end
  peer.ver = addonVer and string.sub(addonVer, 1, 16)
  peer.class = ValidClass(class) or peer.class
  if want == "1" then self:ScheduleState(channel) end
  if not peer.hasState or peer.hash ~= hash then self:ScheduleRequest(channel, sender) end
  ns.Peers:Changed()
end

C.handlers.RQ = function(self, body, channel, sender, src)
  ns.Peers:Touch(sender, src)
  if body == "*" then return self:ScheduleState(channel) end
  for _, name in ipairs(ns.Split(body, ",")) do
    if ns.IsMe(name) then return self:ScheduleState(channel) end
  end
end

local MAX_ENTRIES = 200
local MAX_PARTS = 2 * MAX_ENTRIES -- entries + "can share" parts

C.handlers.ST = function(self, body, channel, sender, src)
  local parts = ns.Split(body, ";")
  local hash, class = parts[1], parts[2]
  if not IsHash(hash) then return end
  local entries, quests, shares = {}, {}, {}
  for k = 3, math.min(#parts, 2 + MAX_PARTS) do
    local qid, q = ns.DecodeEntry(parts[k])
    if qid and q then
      entries[qid] = parts[k]
      quests[qid] = q
    else
      local sid, sh = ns.DecodeShare(parts[k])
      if sid then shares[sid] = sh end
    end
  end
  local peer = ns.Peers:Touch(sender, src)
  if not peer then return end
  peer.class = ValidClass(class) or peer.class
  peer.entries, peer.quests, peer.hasState, peer.hash = entries, quests, true, hash
  peer.push = {}
  for qid, sh in pairs(shares) do
    if quests[qid] then peer.push[qid] = sh end
  end
  if ns.HashEntries(entries) ~= hash then ns.Debug("state hash mismatch from", sender) end
  ns.Peers:Changed()
end

C.handlers.QU = function(self, body, channel, sender, src)
  local peer = ns.Peers:Touch(sender, src)
  if not peer then return end
  if not peer.hasState then return self:ScheduleRequest(channel, sender) end
  local parts = ns.Split(body, ";")
  local hash = parts[1]
  if not IsHash(hash) then return end
  local updated, shares = {}, {}
  for k = 2, math.min(#parts, 1 + MAX_PARTS) do
    local qid, q = ns.DecodeEntry(parts[k])
    if qid then
      updated[qid] = true
      if q then
        peer.entries[qid] = parts[k]
        peer.quests[qid] = q
      else
        peer.entries[qid] = nil
        peer.quests[qid] = nil
      end
    else
      local sid, sh = ns.DecodeShare(parts[k])
      if sid then shares[sid] = sh end
    end
  end
  -- every updated quest carries its share part if (and only if) shareable
  peer.push = peer.push or {}
  for qid in pairs(updated) do
    peer.push[qid] = peer.quests[qid] and shares[qid] or nil
  end
  peer.hash = hash
  -- we missed something: ask for the full state
  if ns.HashEntries(peer.entries) ~= hash then self:ScheduleRequest(channel, sender) end
  ns.Peers:Changed()
end

C.handlers.WT = function(self, body, channel, sender, src)
  local peer = ns.Peers:Touch(sender, src)
  if not peer then return end
  local wants = {}
  if body ~= "-" then
    local ids = ns.Split(body, ",")
    for k = 1, math.min(#ids, MAX_WANTS) do
      local qid = tonumber(ids[k])
      if qid and qid > 0 and qid <= 10000000 then wants[qid] = true end
    end
  end
  peer.wants = wants
  ns.Peers:Changed()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
ns.Listen("INIT", function()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
  if ns.IsSecret(prefix) or prefix ~= PREFIX then return end
  if ns.IsSecret(text) or ns.IsSecret(sender) or ns.IsSecret(channel) then return end
  C:OnRaw(text, channel, sender)
end)

-- First scan done: announce ourselves and ask everyone for their state.
ns.Listen("LOCAL_QUESTS_READY", function()
  C_Timer.After(3, function()
    for _, ch in ipairs(C:ActiveChannels()) do C:SendHello(ch, true) end
  end)
  C_Timer.NewTicker(HEARTBEAT, function()
    for _, ch in ipairs(C:ActiveChannels()) do C:SendHello(ch, false) end
  end)
end)

ns.Listen("LOCAL_QUESTS_CHANGED", function(changed, removed)
  for _, ch in ipairs(C:ActiveChannels()) do
    local p = pendingUpd[ch] or {}
    pendingUpd[ch] = p
    for qid in pairs(changed) do p[qid] = true end
    for qid in pairs(removed) do p[qid] = true end
    local delay = ch == "GUILD" and 5 or 1.5
    ns.Coalesce("qu:" .. ch, delay, function() C:FlushUpdates(ch) end)
  end
end)

ns.On("GROUP_ROSTER_UPDATE", function()
  local inGroup = IsInGroup()
  if inGroup and not C.wasInGroup and ns.db.shareParty and ns.QuestState.ready then
    C_Timer.After(2, function()
      local g = ns.GetGroupChannel()
      if g then C:SendHello(g, true) end
    end)
  end
  C.wasInGroup = inGroup
end)

-- Leaving an instance / zoning / leaving combat: try again and resync.
local function Unblock()
  if not next(C.blocked) and not next(C.needResync) then return end
  wipe(C.blocked)
  local resync = C.needResync
  C.needResync = {}
  C_Timer.After(2, function()
    for ch in pairs(resync) do
      if C:IsActive(ch) then
        C:SendHello(ch, false)
        C:SendState(ch)
      end
    end
  end)
end
ns.On("PLAYER_ENTERING_WORLD", Unblock)
ns.On("ZONE_CHANGED_NEW_AREA", Unblock)
ns.On("PLAYER_REGEN_ENABLED", Unblock)

-- Called when sharing settings change (Settings tab).
function C:OnSettingsChanged()
  ns.Peers:Prune()
  for _, ch in ipairs(self:ActiveChannels()) do self:SendHello(ch, true) end
end

-- Settings > Can share toggled: our state hash doesn't change, so peers
-- won't ask again. Push the new state and wants ourselves.
function C:OnShareChanged()
  for _, ch in ipairs(self:ActiveChannels()) do
    self:SendState(ch)
    self:SendWants(ch, true)
  end
end

-- Our wants depend on peers' shareable quests, our quest log and our level.
ns.Listen("PEERS_CHANGED", function() C:ScheduleWants() end)
ns.Listen("LOCAL_QUESTS_CHANGED", function() C:ScheduleWants() end)
ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() C:ScheduleWants() end) end)
