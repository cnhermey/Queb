-- Queb: snapshot of the player's own quest log.
local _, ns = ...

local QS = {
  quests = {},       -- [questID] = { c = bool, obj = { {fulfilled, required}, ... }, title = string,
                     --               lvl = number?, push = bool (the game lets us share it) }
  serialized = {},   -- [questID] = wire entry string
  hash = ns.Hash(""),
  ready = false,     -- true after the first successful scan
}
ns.QuestState = QS

local function ReadObjectives(questID)
  local objs = C_QuestLog.GetQuestObjectives(questID)
  if type(objs) ~= "table" then return nil end
  local out = {}
  for i, o in ipairs(objs) do
    local f, r = o.numFulfilled, o.numRequired
    if ns.IsSecret(f) or ns.IsSecret(r) then return nil end
    f, r = tonumber(f), tonumber(r)
    if not r or r <= 0 then
      -- objectives without a counter (e.g. "Talk to X"): finished = 1/1
      r = 1
      f = o.finished and 1 or 0
    end
    f = f or 0
    if f > r then f = r end
    out[i] = { f, r }
  end
  return out
end

function QS:Scan()
  local new = {}
  local needRetry = false
  local num = C_QuestLog.GetNumQuestLogEntries() or 0

  for i = 1, num do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and not info.isHidden then
      local qid = info.questID
      if type(qid) == "number" and qid > 0 then
        local objs = ReadObjectives(qid)
        local old = self.quests[qid]
        -- GetQuestObjectives can briefly return {} right after events: keep the
        -- old data and look again shortly.
        if (not objs or #objs == 0) and old and #old.obj > 0 then
          objs = old.obj
          needRetry = true
        end
        local push = false
        if C_QuestLog.IsPushableQuest then
          local ok, p = pcall(C_QuestLog.IsPushableQuest, qid)
          push = ok and not ns.IsSecret(p) and p and true or false
        end
        local lvl = info.level
        if ns.IsSecret(lvl) then lvl = nil end
        new[qid] = {
          c = C_QuestLog.IsComplete(qid) and true or false,
          obj = objs or {},
          title = info.title,
          lvl = tonumber(lvl),
          push = push,
        }
      end
    end
  end

  local changed, removed = {}, {}
  local serialized = {}
  for qid, q in pairs(new) do
    local e = ns.EncodeEntry(qid, q)
    serialized[qid] = e
    if self.serialized[qid] ~= e then changed[qid] = true end
    -- "can share" isn't part of the entry: send an update when it flips too
    local old = self.quests[qid]
    if old and (old.push and true or false) ~= q.push then changed[qid] = true end
  end
  for qid in pairs(self.quests) do
    if not new[qid] then removed[qid] = true end
  end

  local initial = not self.ready
  self.quests, self.serialized = new, serialized
  self.hash = ns.HashEntries(serialized)
  self.ready = true

  if initial then
    ns.Fire("LOCAL_QUESTS_READY")
  elseif next(changed) or next(removed) then
    ns.Fire("LOCAL_QUESTS_CHANGED", changed, removed)
  end
  if initial or next(changed) or next(removed) then
    ns.UI:Refresh()
  end
  if needRetry then
    ns.Debounce("qs_retry", 1, function() QS:Scan() end)
  end
end

function QS:RequestScan()
  ns.Coalesce("qs_scan", 0.5, function() QS:Scan() end)
end

function QS:GetTitle(questID)
  local q = self.quests[questID]
  if q and q.title then return q.title end
  if C_QuestLog.GetTitleForQuestID then
    local t = C_QuestLog.GetTitleForQuestID(questID)
    if t and not ns.IsSecret(t) then return t end
  end
end

-- "Can share" wire part for one of our quests, or nil (not shareable, or
-- the player turned Settings > Can share off).
function QS:SharePart(questID)
  local q = self.quests[questID]
  if not q or not q.push or not (ns.db and ns.db.shareQuests) then return nil end
  return ns.EncodeShare(questID, q.lvl, q.title)
end

-- All share parts, sorted by questID.
function QS:ShareParts()
  local ids = {}
  for qid in pairs(self.quests) do ids[#ids + 1] = qid end
  table.sort(ids)
  local out = {}
  for _, qid in ipairs(ids) do
    local part = self:SharePart(qid)
    if part then out[#out + 1] = part end
  end
  return out
end

-- Full-state payload: hash;entry;entry;...
function QS:StatePayload()
  local ids = {}
  for qid in pairs(self.serialized) do ids[#ids + 1] = qid end
  table.sort(ids)
  local parts = { self.hash }
  for _, qid in ipairs(ids) do parts[#parts + 1] = self.serialized[qid] end
  return table.concat(parts, ";")
end

local function OnQuestEvent() QS:RequestScan() end
ns.On("QUEST_LOG_UPDATE", OnQuestEvent)
ns.On("QUEST_ACCEPTED", OnQuestEvent)
ns.On("QUEST_REMOVED", OnQuestEvent)
ns.On("QUEST_TURNED_IN", OnQuestEvent)
ns.On("PLAYER_ENTERING_WORLD", OnQuestEvent)
