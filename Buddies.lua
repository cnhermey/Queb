-- Queb: "who should I quest with?"
--   * Login summary in chat: top guildmates by shared quests (clickable names).
--   * Main Queb window (/queb, a circle click, or Esc > Options > AddOns):
--     Quebmates tab (ranked list, roles, level, zone, Invite) + Settings tab,
--     with the role picker beside the tabs. The window is resizable.
local ADDON_NAME, ns = ...

local B = {}
ns.Buddies = B

local ROWS, ROW_H = 13, 26

local function ColorHex(classFile)
  local c = ns.UI.ClassColor(classFile)
  return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Native player link: left-click whispers, right-click opens Blizzard's
-- player menu (invite, etc.). No custom chat code needed.
local function PlayerLink(name, classFile)
  return "|cff" .. ColorHex(classFile) .. "|Hplayer:" .. name .. "|h[" .. name .. "]|h|r"
end

local function InfoText(b)
  local parts = {}
  if b.level then parts[#parts + 1] = "Lv " .. b.level end
  if b.zone and b.zone ~= "" then parts[#parts + 1] = b.zone end
  return table.concat(parts, " · ")
end

---------------------------------------------------------------------------
-- Login summary
---------------------------------------------------------------------------
local function GetLists()
  local buddies = ns.Peers:GetBuddies()
  local nearby = {}
  if ns.db.showNearby then
    local exclude = {}
    for _, b in ipairs(buddies) do exclude[b.name] = true end
    nearby = ns.Peers:GetNearby(exclude)
  end
  return buddies, nearby
end

local function NearbyText(n)
  local info = InfoText(n)
  if n.sameZone then info = info .. " · " .. ns.UI.Wrap(ns.UI.GREEN, "your zone") end
  if not n.hasAddon then info = info .. " · no Queb" end
  return info
end

-- Style rule: short phrases. Names are native player links (click = whisper,
-- right-click = Blizzard menu with Invite).
function B:PrintSummary(force)
  local buddies, nearby = GetLists()
  local P = ns.PrintLine
  if #buddies == 0 and #nearby == 0 then
    if force then ns.Print("No Quebmates online") end
    return
  end
  if #buddies > 0 then
    ns.Print("Quebmates online")
    for i = 1, math.min(3, #buddies) do
      local b = buddies[i]
      local info = InfoText(b)
      if not b.hasAddon then info = info .. (info ~= "" and " · " or "") .. "grouped, no Queb" end
      local what = {}
      if #b.shared > 0 then what[#what + 1] = #b.shared .. " shared" end
      if b.canShare and #b.canShare > 0 then what[#what + 1] = ns.UI:ShareIcon(12) .. "can share " .. #b.canShare end
      P(string.format("  %s  %s%s", PlayerLink(b.name, b.class), table.concat(what, " · "),
        info ~= "" and (" · " .. info) or ""))
    end
    if #nearby > 0 then
      local names = {}
      for i = 1, math.min(3, #nearby) do names[i] = PlayerLink(nearby[i].name, nearby[i].class) end
      P("  Near your level: " .. table.concat(names, ", "))
    end
  else
    ns.Print("Near your level")
    for i = 1, math.min(3, #nearby) do
      local n = nearby[i]
      P("  " .. PlayerLink(n.name, n.class) .. "  " .. NearbyText(n))
    end
  end
  P("  More: /queb")
end

ns.Listen("LOCAL_QUESTS_READY", function()
  -- give guildmates time to answer our hello (their replies are jittered)
  C_Timer.After(20, function()
    if ns.db.loginSummary and ns.db.shareGuild then B:PrintSummary(false) end
  end)
end)

---------------------------------------------------------------------------
-- Window
--
-- Native look: built on Blizzard's ButtonFrameTemplate (portrait, title bar,
-- close button, inset), a WowScrollBoxList + MinimalScrollBar list, Blizzard
-- class icons and quest-log row highlight, UIPanelButtonTemplate buttons.
-- Escape closes it, it plays the standard panel sounds and remembers where
-- it was dragged. Every Blizzard piece is feature-detected with a fallback.
---------------------------------------------------------------------------
local UI = ns.UI
local WIN_W, WIN_H = 520, 480           -- default size
local MIN_W, MIN_H = 470, 220           -- height: title + tabs + a few rows; Settings scrolls
local MAX_W, MAX_H = 1000, 900

local function Invite(name)
  if C_PartyInfo and C_PartyInfo.InviteUnit then
    C_PartyInfo.InviteUnit(name)
  elseif InviteUnit then
    InviteUnit(name)
  end
end

local function PlaySoundSafe(kit)
  if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function ClassAtlas(classFile)
  if not classFile or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
  local atlas = "classicon-" .. string.lower(classFile)
  if C_Texture.GetAtlasInfo(atlas) then return atlas end
end

local DungeonHeaderTooltip, DungeonQuestTooltip -- defined below

local function RowTooltip(row)
  if row.kind == "dheader" then return DungeonHeaderTooltip(row) end
  if row.kind == "dquest" then return DungeonQuestTooltip(row) end
  local b = row.buddy
  if not b then return end
  local c = UI.ClassColor(b.class)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(b.name, c.r, c.g, c.b)
  local roles = ns.Roles:For(b)
  if roles and next(roles) then
    local parts = {}
    for _, r in ipairs(ns.Roles.ORDER) do
      if roles[r] then parts[#parts + 1] = ns.Roles:Inline(r, 14) .. " " .. ns.Roles.LABEL[r] end
    end
    GameTooltip:AddLine(table.concat(parts, "  "), UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
  end
  if row.kind == "nearby" then
    GameTooltip:AddLine("Near your level" .. (b.sameZone and ", same zone" or ""), UI.WHITE.r, UI.WHITE.g, UI.WHITE.b, true)
    -- Same status logic as every other Queb tooltip.
    local info = b.peer and b.peer.demo and { status = "addon", shared = {} } or ns.Peers:SharedWith(b.name)
    local reason = UI.STATUS_REASONS[info.status]
    if reason then
      GameTooltip:AddLine(reason, UI.GRAY.r, UI.GRAY.g, UI.GRAY.b, true)
    elseif #info.shared == 0 then
      GameTooltip:AddLine("No shared quests", UI.GRAY.r, UI.GRAY.g, UI.GRAY.b, true)
    else
      -- shouldn't happen (they'd be listed as a buddy), but never claim "unknown"
      GameTooltip:AddLine(#info.shared .. (#info.shared == 1 and " shared quest" or " shared quests"), UI.GRAY.r, UI.GRAY.g, UI.GRAY.b, true)
    end
    GameTooltip:Show()
    return
  end
  if #b.shared > 0 then
    GameTooltip:AddLine(b.hasAddon and "Shared quests" or ("Shared quests " .. UI.Wrap(UI.GRAY, "(no Queb)")),
      UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, true)
  end
  for _, qid in ipairs(b.shared) do
    local theirs = b.peer and b.peer.quests[qid]
    local mine = ns.QuestState.quests[qid]
    local prog = theirs and UI:ProgressText(theirs.c, theirs.obj) or UI.Wrap(UI.GRAY, "on quest")
    GameTooltip:AddDoubleLine(ns.QuestState:GetTitle(qid) or ("Quest " .. qid), prog, UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
    if mine then
      GameTooltip:AddDoubleLine("   you", UI:ProgressText(mine.c, mine.obj), UI.GRAY.r, UI.GRAY.g, UI.GRAY.b)
    end
  end
  -- quests they can share with you (yellow "!", never a circle)
  if b.canShare and #b.canShare > 0 then
    if #b.shared > 0 then GameTooltip:AddLine(" ") end
    GameTooltip:AddLine(UI:ShareIcon(12) .. " Can share", UI.GOLD.r, UI.GOLD.g, UI.GOLD.b)
    for _, q in ipairs(b.canShare) do
      GameTooltip:AddDoubleLine(q.title or ns.QuestState:GetTitle(q.questID) or ("Quest " .. q.questID),
        q.level and ("Lv " .. q.level) or "", UI.WHITE.r, UI.WHITE.g, UI.WHITE.b, UI.GRAY.r, UI.GRAY.g, UI.GRAY.b)
    end
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Dungeons section (v0.14.0): one collapsible block per dungeon, the dungeon
-- name as its title. Header row: +/- , name, level range, then one class
-- circle per person checked (the column key). Quest rows: one status icon
-- per person in the same columns. Data and status rules: Dungeons.lua.
---------------------------------------------------------------------------
local DG = ns.Dungeons
local CELL = 16

local STATUS_COLOR = {
  L = "WHITE", R = "GREEN", D = "GREEN", A = "GOLD",
}

local function StatusText(code)
  local t = DG.TEXT[code] or DG.TEXT["?"]
  return UI.Wrap(UI[STATUS_COLOR[code] or "GRAY"], t)
end

local function HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetAvailable(tex)
  if HasAtlas("QuestNormal") then
    tex:SetAtlas("QuestNormal")
  else
    tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    tex:SetTexCoord(0, 1, 0, 1)
  end
end

local function HasQueb(p)
  return p.isMe or (p.peer and p.peer.hasState) or false
end

local function MakeCell(row)
  local c = {}
  c.shadow = row:CreateTexture(nil, "ARTWORK", nil, 1)
  c.shadow:SetTexture(UI.CIRCLE)
  c.shadow:SetVertexColor(0, 0, 0, 0.85)
  c.shadow:SetSize(12, 12)
  c.tex = row:CreateTexture(nil, "ARTWORK", nil, 2)
  c.tex:SetPoint("CENTER", c.shadow, "CENTER")
  c.ring = row:CreateTexture(nil, "ARTWORK", nil, 4)
  c.ring:SetTexture(UI.RING)
  c.ring:SetVertexColor(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 1)
  c.ring:SetSize(14, 14)
  c.ring:SetPoint("CENTER", c.shadow, "CENTER")
  c.txt = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  c.txt:SetPoint("CENTER", c.shadow, "CENTER")
  return c
end

local function HideCell(c)
  c.shadow:Hide(); c.tex:Hide(); c.ring:Hide(); c.txt:Hide()
end

local function ResetTex(tex, size)
  tex:SetTexCoord(0, 1, 0, 1)
  tex:SetDesaturated(false)
  tex:SetVertexColor(1, 1, 1, 1)
  tex:SetAlpha(1)
  tex:SetSize(size, size)
  tex:Show()
end

-- One cell: the person's status icon, or (code == nil) their class circle.
local function SetCell(c, code, p)
  HideCell(c)
  if code == nil or code == "L" or code == "R" then
    local col = UI.ClassColor(p.class)
    ResetTex(c.tex, 10)
    c.tex:SetTexture(UI.CIRCLE)
    c.tex:SetVertexColor(col.r, col.g, col.b, HasQueb(p) and 1 or 0.45)
    c.shadow:Show()
    c.ring:SetShown(code == "R")
  elseif code == "D" then
    ResetTex(c.tex, 14)
    c.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  elseif code == "A" or code == "P" or code == "V" then
    ResetTex(c.tex, 14)
    SetAvailable(c.tex)
    if code ~= "A" then
      c.tex:SetDesaturated(true)
      c.tex:SetAlpha(0.7)
    end
  elseif code == "S" then
    ResetTex(c.tex, 14)
    c.tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
    c.tex:SetAlpha(0.8)
  elseif code == "X" then
    c.txt:SetText("–")
    c.txt:Show()
  else
    c.txt:SetText("?")
    c.txt:Show()
  end
end

local function InitDungeonParts(row)
  if row.dg then return end
  local g = { cells = {} }
  row.dg = g
  g.expand = row:CreateTexture(nil, "ARTWORK")
  g.expand:SetSize(14, 14)
  g.expand:SetPoint("LEFT", row, "LEFT", 4, 0)
  g.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  g.title:SetJustifyH("LEFT")
  g.title:SetWordWrap(false)
  g.summary = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  g.summary:SetJustifyH("RIGHT")
end

local function HideDungeonParts(row)
  local g = row.dg
  if not g then return end
  g.expand:Hide(); g.title:Hide(); g.summary:Hide()
  for _, c in ipairs(g.cells) do HideCell(c) end
end

-- Cells right-aligned, first person leftmost; title + summary left of them.
local function LayoutDungeonRow(row, n, indent, font)
  local g = row.dg
  for i = 1, n do
    local c = g.cells[i] or MakeCell(row)
    g.cells[i] = c
    c.shadow:ClearAllPoints()
    c.shadow:SetPoint("CENTER", row, "RIGHT", -(4 + CELL / 2) - (n - i) * CELL, 0)
  end
  for i = n + 1, #g.cells do HideCell(g.cells[i]) end
  local cellsW = n * CELL + 8
  g.summary:ClearAllPoints()
  g.summary:SetPoint("RIGHT", row, "RIGHT", -cellsW, 0)
  g.title:ClearAllPoints()
  g.title:SetPoint("LEFT", row, "LEFT", indent, 0)
  g.title:SetPoint("RIGHT", g.summary, "LEFT", -6, 0)
  g.title:SetFontObject(font)
  g.title:Show()
end

local function Counts(block, pIndex)
  local n = {}
  for qi = 1, #block.quests do
    local code = block.codes[qi][pIndex]
    n[code] = (n[code] or 0) + 1
  end
  return n
end

local function PersonSummary(block, pIndex)
  local n = Counts(block, pIndex)
  local parts = {}
  if n.L or n.R then parts[#parts + 1] = ((n.L or 0) + (n.R or 0)) .. " on" end
  if n.D then parts[#parts + 1] = n.D .. " done" end
  if n.A then parts[#parts + 1] = UI.Wrap(UI.GOLD, n.A .. " to pick up") end
  if n.P or n.V then parts[#parts + 1] = ((n.P or 0) + (n.V or 0)) .. " not yet" end
  if #parts == 0 then
    -- nothing known: the one reason (e.g. "no Queb", "syncing")
    local code = block.codes[1] and block.codes[1][pIndex]
    return StatusText(code or "?")
  end
  return table.concat(parts, " · ")
end

local function RenderDungeonHeader(row, item)
  InitDungeonParts(row)
  local b, g = item.block, row.dg
  local d = b.dungeon
  LayoutDungeonRow(row, #b.people, 22, "GameFontNormal")
  g.expand:SetTexture(item.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
  g.expand:Show()
  local lv = d.minL and ((d.maxL and d.maxL ~= d.minL) and ("Lv " .. d.minL .. "-" .. d.maxL) or ("Lv " .. d.minL)) or nil
  g.title:SetText(d.name .. (lv and ("  " .. UI.Wrap(UI.GRAY, lv)) or ""))
  local avail = 0
  for qi = 1, #b.quests do
    for pi = 1, #b.people do
      if b.codes[qi][pi] == "A" then avail = avail + 1 end
    end
  end
  g.summary:SetText(avail > 0 and (UI:ShareIcon(12) .. avail) or "")
  g.summary:Show()
  for i, p in ipairs(b.people) do SetCell(g.cells[i], nil, p) end
end

local function RenderDungeonQuest(row, item)
  InitDungeonParts(row)
  local b, g, qi = item.block, row.dg, item.qi
  local q = b.quests[qi]
  LayoutDungeonRow(row, #b.people, 24, "GameFontHighlightSmall")
  g.expand:Hide()
  local lvl = q.level and UI.Wrap(UI.GRAY, "[" .. q.level .. "] ") or ""
  g.title:SetText(lvl .. DG:Title(q))
  g.summary:SetText(DG:CanShareNow(q.id) and UI.Wrap(UI.GREEN, "share") or "")
  g.summary:Show()
  for i, p in ipairs(b.people) do SetCell(g.cells[i], b.codes[qi][i], p) end
end

DungeonHeaderTooltip = function(row)
  local b = row.item.block
  local d = b.dungeon
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(d.name, UI.GOLD.r, UI.GOLD.g, UI.GOLD.b)
  if d.minL then
    GameTooltip:AddLine((d.maxL and d.maxL ~= d.minL) and ("Lv " .. d.minL .. "-" .. d.maxL) or ("Lv " .. d.minL),
      UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
  end
  GameTooltip:AddLine(" ")
  for i, p in ipairs(b.people) do
    local name = p.isMe and "You" or p.name
    GameTooltip:AddDoubleLine(UI:CircleIcon(p.class, 10) .. " " .. UI.ColorName(name, p.class), PersonSummary(b, i))
  end
  GameTooltip:AddLine(row.item.open and "<Click: close>" or "<Click: open>", UI.GREEN.r, UI.GREEN.g, UI.GREEN.b)
  GameTooltip:AddLine("<Shift-click: names to chat>", UI.GREEN.r, UI.GREEN.g, UI.GREEN.b)
  GameTooltip:Show()
end

DungeonQuestTooltip = function(row)
  local b, qi = row.item.block, row.item.qi
  local q = b.quests[qi]
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(DG:Title(q), UI.GOLD.r, UI.GOLD.g, UI.GOLD.b)
  local lv = {}
  if q.level then lv[#lv + 1] = "Lv " .. q.level end
  if q.req then lv[#lv + 1] = "needs Lv " .. q.req end
  if #lv > 0 then GameTooltip:AddLine(table.concat(lv, " · "), UI.WHITE.r, UI.WHITE.g, UI.WHITE.b) end
  if q.pickup then GameTooltip:AddLine(q.pickup, UI.GRAY.r, UI.GRAY.g, UI.GRAY.b, true) end
  local pre = DG:PrereqNames(q.id)
  if pre then GameTooltip:AddLine("Pre-quests: " .. table.concat(pre, ", "), UI.GRAY.r, UI.GRAY.g, UI.GRAY.b, true) end
  GameTooltip:AddLine(" ")
  for i, p in ipairs(b.people) do
    local name = p.isMe and "You" or p.name
    GameTooltip:AddDoubleLine(UI:CircleIcon(p.class, 10) .. " " .. UI.ColorName(name, p.class), StatusText(b.codes[qi][i]))
  end
  if DG:CanShareNow(q.id) then
    GameTooltip:AddLine("<Click: share>", UI.GREEN.r, UI.GREEN.g, UI.GREEN.b)
  end
  GameTooltip:Show()
end

-- Shift-click a dungeon: "Deadmines: Quest A, Quest B" into the open chat
-- box (Blizzard's shift-click-to-link behavior; never sent by Queb).
local function InsertIntoChat(text)
  local fns = {}
  if ChatFrameUtil and ChatFrameUtil.InsertLink then fns[#fns + 1] = function(t) return ChatFrameUtil.InsertLink(t) end end
  if ChatEdit_InsertLink then fns[#fns + 1] = ChatEdit_InsertLink end
  for _, fn in ipairs(fns) do
    local ok, done = pcall(fn, text)
    if ok and done then return true end
  end
  return false
end

local function DungeonChatText(b)
  local names = {}
  for qi, q in ipairs(b.quests) do
    for pi, p in ipairs(b.people) do
      if not p.isMe and b.codes[qi][pi] == "A" then names[#names + 1] = DG:Title(q) break end
    end
  end
  if #names == 0 then
    for _, q in ipairs(b.quests) do names[#names + 1] = DG:Title(q) end
  end
  return b.dungeon.name .. ": " .. table.concat(names, ", ")
end

local function OnRowClick(row)
  local item = row.item
  if not item then return end
  if item.kind == "dheader" then
    if IsShiftKeyDown() then
      if not InsertIntoChat(DungeonChatText(item.block)) then ns.Print("Open chat first") end
      return
    end
    PlaySoundSafe(item.open and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
    DG:SetOpen(item.block.dungeon.key, not item.open)
    B:Update()
  elseif item.kind == "dquest" then
    local q = item.block.quests[item.qi]
    if DG:CanShareNow(q.id) then DG:Share(q.id) end
  end
end

-- Builds a row's parts once (rows are recycled by the ScrollBox). Rows are
-- our own frames, so keeping parts on them is fine.
local function InitRow(row)
  if row.qbInit then return end
  row.qbInit = true
  row:SetHeight(ROW_H)

  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight") -- Blizzard list-row highlight
  hl:SetBlendMode("ADD")
  hl:SetAllPoints()
  hl:SetAlpha(0.5)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetWidth(120)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  ns.Roles:InitRowIcons(row, row.name)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.count:SetPoint("LEFT", row.name, "RIGHT", 6 + ns.Roles.ROW_SLOTS_W, 0)
  row.count:SetWidth(84)
  row.count:SetJustifyH("LEFT")

  row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.info:SetPoint("LEFT", row.count, "RIGHT", 4, 0)
  row.info:SetPoint("RIGHT", row, "RIGHT", -74, 0)
  row.info:SetJustifyH("LEFT")
  row.info:SetWordWrap(false)

  row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- gold, like Blizzard list headers
  row.header:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 4)
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetColorTexture(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.25)
  row.divider:SetHeight(1)
  row.divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 1)
  row.divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)

  row.invite = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.invite:SetSize(66, 20)
  row.invite:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row.invite:SetText("Invite")
  row.invite:SetScript("OnClick", function(self)
    local b = self:GetParent().buddy
    if b then Invite(b.name) end
  end)

  row:SetScript("OnEnter", RowTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", OnRowClick)
end

-- header = gold section title; member = Quebmate row; none = dungeon rows.
local function ShowMemberParts(row, shown, header)
  if header == nil then header = not shown end
  if not shown then ns.Roles:HideRowIcons(row) end
  row.icon:SetShown(shown)
  row.name:SetShown(shown)
  row.count:SetShown(shown)
  row.info:SetShown(shown)
  row.invite:SetShown(shown)
  row.header:SetShown(header)
  row.divider:SetShown(header)
end

local function RenderRow(row, item)
  InitRow(row)
  row.kind = item.kind
  row.item = item
  row.buddy = item.data
  HideDungeonParts(row)
  if item.kind == "header" then
    ShowMemberParts(row, false)
    row.header:SetText(item.text)
    row:EnableMouse(false)
    return
  end
  if item.kind == "dnote" then
    ShowMemberParts(row, false, false)
    InitDungeonParts(row)
    LayoutDungeonRow(row, 0, 8, "GameFontDisable")
    row.dg.title:SetText(item.text)
    row:EnableMouse(false)
    return
  end
  if item.kind == "dheader" or item.kind == "dquest" then
    ShowMemberParts(row, false, false)
    row:EnableMouse(true)
    if item.kind == "dheader" then RenderDungeonHeader(row, item) else RenderDungeonQuest(row, item) end
    return
  end
  row:EnableMouse(true)
  ShowMemberParts(row, true)
  local b = item.data
  local c = UI.ClassColor(b.class)
  local faded = item.kind == "nearby" and not b.hasAddon
  local atlas = ClassAtlas(b.class)
  if atlas then
    row.icon:SetAtlas(atlas)
    row.icon:SetVertexColor(1, 1, 1)
  else
    row.icon:SetTexture(UI.CIRCLE)
    row.icon:SetVertexColor(c.r, c.g, c.b)
  end
  row.icon:SetAlpha(faded and 0.5 or 1)
  row.name:SetText(b.name)
  row.name:SetTextColor(c.r, c.g, c.b)
  ns.Roles:ShowRowIcons(row, ns.Roles:For(b), faded and 0.5 or 1)
  if item.kind == "buddy" then
    local parts = {}
    if #b.shared > 0 then parts[#parts + 1] = #b.shared .. " shared" end
    if b.canShare and #b.canShare > 0 then parts[#parts + 1] = UI:ShareIcon(12) .. #b.canShare end
    row.count:SetText(table.concat(parts, "  "))
  else
    row.count:SetText(b.sameZone and UI.Wrap(UI.GREEN, "your zone") or "")
  end
  row.info:SetText(InfoText(b) .. (b.hasAddon and "" or " · no Queb"))
  local isDemo = b.peer and b.peer.demo
  row.invite:SetEnabled(not b.unit and not isDemo)
  row.invite:SetText(b.unit and "Grouped" or "Invite")
end

-- Build display items: buddies first, then a "near your level" section.
local function BuildItems()
  local buddies, nearby = GetLists()
  local items = {}
  for _, b in ipairs(buddies) do items[#items + 1] = { kind = "buddy", data = b } end
  if #nearby > 0 then
    items[#items + 1] = { kind = "header", text = "Near your level (±" .. (ns.db.nearbyLevelRange or 3) .. ")" }
    for _, n in ipairs(nearby) do items[#items + 1] = { kind = "nearby", data = n } end
  end
  -- Dungeons section: one collapsible block per dungeon
  local open = {}
  if ns.db.dungeonsGroup or ns.db.dungeonsGuild then
    local blocks = DG:Blocks()
    if blocks == nil then
      items[#items + 1] = { kind = "header", text = "Dungeons" }
      items[#items + 1] = { kind = "dnote", text = DG:HasSource() and "loading" or "needs DungeonJournal or Questie" }
    elseif #blocks > 0 then
      items[#items + 1] = { kind = "header", text = "Dungeons" }
      for _, b in ipairs(blocks) do
        b.codes = {}
        for qi, q in ipairs(b.quests) do
          b.codes[qi] = {}
          for pi, p in ipairs(b.people) do b.codes[qi][pi] = DG:Status(p, q.id) end
        end
        local isOpen = DG:IsOpen(b.dungeon.key)
        items[#items + 1] = { kind = "dheader", block = b, open = isOpen }
        if isOpen then
          open[#open + 1] = b
          for qi in ipairs(b.quests) do items[#items + 1] = { kind = "dquest", block = b, qi = qi } end
        end
      end
    end
  end
  return items, open
end

local function SetTitle(f, text)
  if f.SetTitle then
    f:SetTitle(text)
  else
    local t = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
    if t then t:SetText(text) end
  end
end

-- Queb's own icon (a web with one class-colored circle per class) in the
-- window's round portrait slot. Blizzard's SetPortraitToTexture rounds it the
-- same way it rounds Blizzard's own portraits.
local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"
B.ICON = ICON
local function SetPortrait(f)
  if f.qbPortraitSet then return end
  local tex = (f.GetPortrait and f:GetPortrait()) or (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
  if not tex then return end
  if SetPortraitToTexture and pcall(SetPortraitToTexture, tex, ICON) then
    f.qbPortraitSet = true
  else
    tex:SetTexture(ICON)
    f.qbPortraitSet = true
  end
end

local function SavePosition(f)
  local point, _, relPoint, x, y = f:GetPoint(1)
  if point then ns.db.buddiesPos = { point, relPoint, x, y } end
end

local function SaveSize(f)
  ns.db.windowSize = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
end

local function RestoreSize(f)
  local s = ns.db.windowSize
  local w, h = WIN_W, WIN_H
  if type(s) == "table" and tonumber(s[1]) and tonumber(s[2]) then w, h = s[1], s[2] end
  f:SetSize(math.max(MIN_W, math.min(MAX_W, w)), math.max(MIN_H, math.min(MAX_H, h)))
end

-- Resizable like Blizzard's resizable windows: size grabber in the bottom
-- right corner (Blizzard's chat-frame grabber art), bounded, size remembered.
local function MakeResizable(f)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
    if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
  end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
  grip:SetFrameLevel(f:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    -- anchor by the top-left corner first, so only the bottom/right edges move
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then -- same units as SetPoint offsets (the window's own scale)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    SaveSize(f)
    SavePosition(f)
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Drag to resize", 1, 1, 1)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.resizeGrip = grip
end

local function RestorePosition(f)
  f:ClearAllPoints()
  local p = ns.db.buddiesPos
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

-- Blizzard window frame, best template this build has.
local function CreateWindow()
  for _, tpl in ipairs({ "ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset" }) do
    local ok, f = pcall(CreateFrame, "Frame", "QuebBuddiesFrame", UIParent, tpl)
    if ok and f then
      B.template = tpl
      if tpl == "ButtonFrameTemplate" then
        if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
      end
      return f
    end
  end
  -- last resort: plain frame with Blizzard's dialog backdrop
  B.template = "backdrop"
  local f = CreateFrame("Frame", "QuebBuddiesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.TitleText:SetPoint("TOP", f, "TOP", 0, -16)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  return f
end

---------------------------------------------------------------------------
-- Main Queb panel: Blizzard top tabs "Quebmates" / "Settings". The same panel
-- is built twice from this code: inside the /queb window and inside
-- Esc > Options > AddOns > Queb. Both instances share QuebDB and refresh
-- together.
---------------------------------------------------------------------------
B.panels = {}
local TABS = { { id = "buddies", text = "Quebmates" }, { id = "settings", text = "Settings" } }

local function MakeInset(parent)
  local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if ok and inset then return inset end
  return CreateFrame("Frame", nil, parent)
end

-- Buddy list inside `inset`: Blizzard ScrollBox + MinimalScrollBar, or fixed rows.
local function BuildList(panel, inset)
  if CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar and CreateDataProvider then
    local ok = pcall(function()
      local box = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
      box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
      box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -20, 4)
      local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
      bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
      bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
      local view = CreateScrollBoxListLinearView()
      view:SetElementExtent(ROW_H)
      view:SetElementInitializer("Button", RenderRow)
      ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
      panel.box = box
    end)
    if not ok then panel.box = nil end
  end
  B.list = panel.box and "ScrollBox" or "fixed rows"
  if not panel.box then
    panel.rows = {}
    for i = 1, ROWS do
      local row = CreateFrame("Button", nil, inset)
      row:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
      row:SetPoint("RIGHT", inset, "RIGHT", -4, 0)
      InitRow(row)
      panel.rows[i] = row
    end
  end
end

local function MakeTab(panel, text)
  for _, tpl in ipairs({ "PanelTopTabButtonTemplate", "PanelTabButtonTemplate" }) do
    local ok, t = pcall(CreateFrame, "Button", nil, panel, tpl)
    if ok and t then
      t.qbBlizzTab = true
      t:SetText(text)
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, t, 0) end
      return t
    end
  end
  local t = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  t:SetSize(90, 22)
  t:SetText(text)
  return t
end

local function SelectTab(panel, id)
  local index = 1
  for i, tab in ipairs(TABS) do
    if tab.id == id then index = i end
  end
  id = TABS[index].id
  panel.selected = id
  panel.pages.buddies:SetShown(id == "buddies")
  panel.pages.settings:SetShown(id == "settings")
  if panel.Tabs[1].qbBlizzTab and PanelTemplates_SetTab then
    pcall(PanelTemplates_SetTab, panel, index)
  else
    for i, t in ipairs(panel.Tabs) do t:SetEnabled(i ~= index) end
  end
  if ns.db then ns.db.lastTab = id end
  if id == "buddies" then B:Update() end
end

-- Build one Queb panel in `parent`. `tabIndent` leaves room for a portrait.
function B:BuildPanel(parent, tabIndent)
  local panel = CreateFrame("Frame", nil, parent)
  panel.SelectTab = SelectTab
  panel.Tabs, panel.pages = {}, {}
  for i, tab in ipairs(TABS) do
    local t = MakeTab(panel, tab.text)
    if i == 1 then
      t:SetPoint("TOPLEFT", panel, "TOPLEFT", tabIndent or 0, 0)
    else
      t:SetPoint("LEFT", panel.Tabs[i - 1], "RIGHT", 2, 0)
    end
    t:SetScript("OnClick", function()
      PlaySoundSafe("IG_CHARACTER_INFO_TAB")
      panel:SelectTab(tab.id)
    end)
    panel.Tabs[i] = t
  end
  panel.numTabs = #TABS

  -- your roles: right of the tabs, same row
  panel.rolePicker = ns.Roles:BuildPicker(panel)
  panel.rolePicker:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, 0)

  -- Quebmates page
  local bp = CreateFrame("Frame", nil, panel)
  bp:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
  bp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  local inset = MakeInset(bp)
  inset:SetPoint("TOPLEFT", bp, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", 0, 20)
  panel.empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  panel.empty:SetPoint("CENTER")
  panel.empty:SetText("No Quebmates online")
  local footer = bp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", bp, "BOTTOMLEFT", 6, 4)
  footer:SetText("Hover a row for details")
  BuildList(panel, inset)
  panel.pages.buddies = bp

  -- Settings page
  -- Settings page, in a Blizzard scroll frame so the window can be made
  -- shorter than the settings list.
  local holder = CreateFrame("Frame", nil, panel)
  holder:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
  holder:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  local scroll
  for _, tpl in ipairs({ "ScrollFrameTemplate", "UIPanelScrollFrameTemplate" }) do
    local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, holder, tpl)
    if ok and sf then scroll = sf break end
  end
  local sp
  if scroll then
    scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -22, 0)
    sp = ns.Options:BuildPage(scroll)
    sp:SetSize(math.max(sp.contentWidth, 1), sp.contentHeight)
    scroll:SetScrollChild(sp)
    scroll:SetScript("OnSizeChanged", function(self, w)
      if w and w > 0 then sp:SetWidth(math.max(w, sp.contentWidth)) end
    end)
    holder:SetScript("OnShow", function() ns.Options:RefreshPage(sp) end)
  else
    sp = ns.Options:BuildPage(holder)
    sp:SetAllPoints(holder)
  end
  panel.pages.settings = holder

  panel:SetScript("OnShow", function(self) B:UpdatePanel(self) end)
  self.panels[#self.panels + 1] = panel
  panel:SelectTab((ns.db and ns.db.lastTab) or "buddies")
  return panel
end

function B:UpdatePanel(panel)
  if not panel:IsVisible() or panel.selected ~= "buddies" then return end
  local items, open = BuildItems()
  -- ask the people of open dungeon blocks for what only they can know
  for _, b in ipairs(open) do DG:Ask(b) end
  if panel.box then
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    panel.box:SetDataProvider(CreateDataProvider(items), retain)
  else
    for i, row in ipairs(panel.rows) do
      local item = items[i]
      if item then
        RenderRow(row, item)
        row:Show()
      else
        row.buddy = nil
        row:Hide()
      end
    end
  end
  panel.empty:SetShown(#items == 0)
end

function B:Update()
  if not ns.db then return end
  for _, panel in ipairs(self.panels) do self:UpdatePanel(panel) end
end

---------------------------------------------------------------------------
-- The /queb window
---------------------------------------------------------------------------
function B:Create()
  if self.frame then return self.frame end
  local f = CreateWindow()
  RestoreSize(f)
  MakeResizable(f)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
  end)
  SetTitle(f, "Queb")
  -- Template close buttons call HideUIPanel; our window isn't a managed
  -- Blizzard panel, so just hide it (keeps us out of Blizzard's panel code).
  local close = f.CloseButton or (f.GetName and _G[f:GetName() .. "CloseButton"])
  if close then close:SetScript("OnClick", function() f:Hide() end) end
  if UISpecialFrames then tinsert(UISpecialFrames, "QuebBuddiesFrame") end -- Escape closes
  if f.Inset then f.Inset:Hide() end -- the panel brings its own inset

  local hasPortrait = B.template == "ButtonFrameTemplate" or B.template == "PortraitFrameTemplate"
  f.panel = self:BuildPanel(f, hasPortrait and 54 or 4)
  f.panel:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
  f.panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

  f:Hide() -- before the sound scripts, so creating it is silent
  f:SetScript("OnShow", function(self)
    SetPortrait(self)
    PlaySoundSafe("IG_CHARACTER_INFO_OPEN")
  end)
  f:SetScript("OnHide", function() PlaySoundSafe("IG_CHARACTER_INFO_CLOSE") end)
  SetPortrait(f)
  RestorePosition(f)
  self.frame = f
  return f
end

-- Open/close the window. With `tab`, open on that tab (a second click on
-- the same tab closes it).
function B:Toggle(tab)
  local f = self:Create()
  if f:IsShown() and (not tab or f.panel.selected == tab) then
    f:Hide()
    return
  end
  if tab then f.panel:SelectTab(tab) end
  f:Show()
end

---------------------------------------------------------------------------
-- Esc > Options > AddOns > Queb: the same panel on a Blizzard settings canvas
---------------------------------------------------------------------------
local function RegisterOptions()
  if B.optionsCanvas then return end
  local canvas = CreateFrame("Frame")
  canvas.name = "Queb"
  canvas:Hide()
  canvas:SetScript("OnShow", function(self)
    if not self.panel then
      local icon = self:CreateTexture(nil, "ARTWORK")
      icon:SetSize(28, 28)
      icon:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -8)
      icon:SetTexture(ICON)
      local title = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
      title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
      title:SetText("Queb")
      self.panel = B:BuildPanel(self, 0)
      self.panel:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -44)
      self.panel:SetSize(MIN_W + 40, WIN_H - 36)
    end
  end)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "Queb")
    if ok and cat then
      Settings.RegisterAddOnCategory(cat)
      B.optionsCategory = cat
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(canvas)
  end
  B.optionsCanvas = canvas
end
ns.Listen("LOGIN", RegisterOptions)

local function Refresh()
  ns.Coalesce("buddies_update", 0.2, function() B:Update() end)
end
ns.Listen("PEERS_CHANGED", Refresh)
ns.Listen("DUNGEONS_READY", Refresh)
ns.Listen("LOCAL_QUESTS_CHANGED", Refresh)
ns.On("GROUP_ROSTER_UPDATE", Refresh)
