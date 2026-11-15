-- Queb: shared-quest info in the Guild & Communities member list.
--
-- Hover a guildmate -> the tooltip gains "Queb: N shared quests" with the
-- quest titles and their progress.
--   Modern: CommunitiesFrame (Blizzard_Communities, load-on-demand); member
--           rows carry .memberInfo (ClubMemberInfo with .name, .classID).
--   Classic: GuildFrame rows GuildFrameButtonN / GuildFrameGuildStatusButtonN
--            carry .guildIndex (GetGuildRosterInfo).
-- If Blizzard's row shows a tooltip, UI_Tooltip.lua's GameTooltip:Show hook
-- appends our lines. If a row shows no tooltip at all, our own OnEnter hook
-- (HookScript, post-hook only) shows one. Names/fields still need in-game
-- verification (Settings > Debug messages logs what was found).
local _, ns = ...
local UI = ns.UI

local G = { hooked = setmetatable({}, { __mode = "k" }), ownTip = nil }
ns.GuildUI = G

local MAX_LINES = 6

local function Str(v)
  if type(v) == "string" and not ns.IsSecret(v) and v ~= "" then return v end
end

-- Member name, class file and online flag (true/false/nil = unknown) for a
-- hovered row, or nil.
function G:MemberOf(owner)
  if type(owner) ~= "table" then return nil end
  local info = owner.memberInfo
  if type(info) ~= "table" and owner.GetMemberInfo then
    local ok, mi = pcall(owner.GetMemberInfo, owner)
    if ok then info = mi end
  end
  if type(info) == "table" then
    local name = Str(info.name)
    if name then
      local classFile
      if info.classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local ci = C_CreatureInfo.GetClassInfo(info.classID)
        classFile = ci and ci.classFile
      end
      local online
      local p = Enum and Enum.ClubMemberPresence
      if p and info.presence ~= nil and not ns.IsSecret(info.presence) then
        -- mobile app counts as offline: they aren't in the game
        online = info.presence ~= p.Offline and info.presence ~= p.Unknown and info.presence ~= p.OnlineMobile
      end
      return name, classFile, online
    end
  end
  local idx = owner.guildIndex
  if type(idx) == "number" and GetGuildRosterInfo then
    local name, _, _, _, _, _, _, _, isOnline, _, classFile = GetGuildRosterInfo(idx)
    name = Str(name)
    if name then
      local online
      if not ns.IsSecret(isOnline) then online = isOnline and true or false end
      return name, Str(classFile), online
    end
  end
end

local REASONS = UI.STATUS_REASONS

-- Append our lines for guildmate `name`. Returns true if anything was added.
function G:AddLines(tooltip, name, classFile, online)
  if not ns.db or not ns.db.showInGuild then return false end
  return self:WriteLines(tooltip, name, classFile, online)
end

-- Same lines without the Guild tooltips setting check (OpenMap markers use
-- their own setting, see UI_OpenMap.lua).
function G:WriteLines(tooltip, name, classFile, online)
  name = ns.NormalizeName(name)
  if not name or ns.IsMe(name) then return false end
  local info = ns.Peers:SharedWith(name, online)
  local icon = UI:CircleIcon(classFile, 12)
  local head = icon .. " " .. UI.Wrap(UI.GOLD, "Queb:") .. " "
  tooltip:AddLine(" ")
  if ns.db.debug then tooltip:AddLine(UI.Wrap(UI.GRAY, "[debug] status: " .. info.status)) end

  local reason = REASONS[info.status]
  if reason then
    tooltip:AddLine(head .. UI.Wrap(UI.GRAY, reason), 1, 1, 1, true)
    return true
  end

  -- "addon" (exact, with progress) or "group" (from the game, no progress)
  local exact = info.status == "addon"
  local n = #info.shared
  if n == 0 then
    tooltip:AddLine(head .. "no shared quests", 1, 1, 1, true)
    if exact then self:AddCanShare(tooltip, name) end
    return true
  end
  tooltip:AddLine(string.format("%s%d shared quest%s%s", head, n,
    n == 1 and "" or "s", exact and "" or (" " .. UI.Wrap(UI.GRAY, "(no Queb)"))), 1, 1, 1, true)
  for i = 1, math.min(n, MAX_LINES) do
    local s = info.shared[i]
    local title = ns.QuestState:GetTitle(s.questID) or ("Quest " .. s.questID)
    local prog = exact and UI:ProgressText(s.complete, s.objectives) or UI.Wrap(UI.GRAY, "on quest")
    tooltip:AddDoubleLine("   " .. title, prog, UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
  end
  if n > MAX_LINES then
    tooltip:AddLine("   " .. UI.Wrap(UI.GRAY, string.format("+%d more", n - MAX_LINES)))
  end
  if exact then self:AddCanShare(tooltip, name) end
  return true
end

-- "! Can share" + quest titles: quests this guildmate can share with you.
local SHARE_LINES = 4
function G:AddCanShare(tooltip, name)
  local list = ns.Peers:ShareableFrom(ns.Peers:FindPeer(name))
  if #list == 0 then return false end
  tooltip:AddLine(UI:ShareIcon(12) .. " " .. UI.Wrap(UI.GOLD, "Can share"), 1, 1, 1)
  for i = 1, math.min(#list, SHARE_LINES) do
    local q = list[i]
    tooltip:AddDoubleLine("   " .. (q.title or ns.QuestState:GetTitle(q.questID) or ("Quest " .. q.questID)),
      q.level and ("Lv " .. q.level) or "", UI.WHITE.r, UI.WHITE.g, UI.WHITE.b, UI.GRAY.r, UI.GRAY.g, UI.GRAY.b)
  end
  if #list > SHARE_LINES then
    tooltip:AddLine("   " .. UI.Wrap(UI.GRAY, string.format("+%d more", #list - SHARE_LINES)))
  end
  return true
end

---------------------------------------------------------------------------
-- Fallback for rows that show no tooltip of their own.
---------------------------------------------------------------------------
local function OnRowEnter(row)
  if not ns.db or not ns.db.showInGuild then return end
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == row then return end -- Blizzard's own; Show hook handled it
  local name, classFile, online = G:MemberOf(row)
  if not name then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  local c = UI.ClassColor(classFile)
  GameTooltip:SetText(name, c.r, c.g, c.b)
  G:AddLines(GameTooltip, name, classFile, online)
  ns.Tooltip.appended[GameTooltip] = true -- don't let the Show hook add a second copy
  G.ownTip = row
  GameTooltip:Show()
end

local function OnRowLeave(row)
  if G.ownTip == row then
    G.ownTip = nil
    GameTooltip:Hide()
  end
end

local function HookRow(row)
  if not row or G.hooked[row] or not row.HookScript then return end
  G.hooked[row] = true
  row:HookScript("OnEnter", OnRowEnter)
  row:HookScript("OnLeave", OnRowLeave)
end

-- Modern: member list rows live in a ScrollBox and are created on demand.
local function HookCommunities()
  local list = CommunitiesFrame and CommunitiesFrame.MemberList
  local box = list and list.ScrollBox
  if not box or G.boxHooked then return end
  G.boxHooked = true
  local function hookVisible()
    if box.ForEachFrame then
      box:ForEachFrame(function(frame) HookRow(frame) end)
    end
  end
  if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
    ScrollUtil.AddAcquiredFrameCallback(box, function(_, frame) HookRow(frame) end, G, true)
  end
  CommunitiesFrame:HookScript("OnShow", function() C_Timer.After(0, hookVisible) end)
  hookVisible()
  ns.Debug("guild UI: Communities member list hooked")
end

-- Classic: fixed row buttons.
local function HookClassicGuild()
  if G.classicHooked or not GuildFrame then return end
  G.classicHooked = true
  for i = 1, 30 do
    HookRow(_G["GuildFrameButton" .. i])
    HookRow(_G["GuildFrameGuildStatusButton" .. i])
  end
  ns.Debug("guild UI: Classic guild rows hooked")
end

ns.Listen("LOGIN", function()
  HookClassicGuild()
  HookCommunities()
end)

ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" then
    C_Timer.After(0, function()
      HookCommunities()
      HookClassicGuild()
    end)
  end
end)
