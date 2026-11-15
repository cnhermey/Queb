-- Queb: "who should I quest with?"
--   * Login summary in chat: top guildmates by shared quests (clickable names).
--   * Main Queb window (/queb, a circle click, or Esc > Options > AddOns):
--     Buddies tab (ranked list, level, zone, Invite) + Settings tab.
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
    if force then ns.Print("No quest buddies online") end
    return
  end
  if #buddies > 0 then
    ns.Print("Quest buddies online")
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
local WIN_W, WIN_H = 460, 470

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

local function RowTooltip(row)
  local b = row.buddy
  if not b then return end
  local c = UI.ClassColor(b.class)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(b.name, c.r, c.g, c.b)
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
  row.name:SetWidth(130)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
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
end

local function ShowMemberParts(row, shown)
  row.icon:SetShown(shown)
  row.name:SetShown(shown)
  row.count:SetShown(shown)
  row.info:SetShown(shown)
  row.invite:SetShown(shown)
  row.header:SetShown(not shown)
  row.divider:SetShown(not shown)
end

local function RenderRow(row, item)
  InitRow(row)
  row.kind = item.kind
  row.buddy = item.data
  if item.kind == "header" then
    ShowMemberParts(row, false)
    row.header:SetText(item.text)
    row:EnableMouse(false)
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
  return items
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
-- Main Queb panel: Blizzard top tabs "Buddies" / "Settings". The same panel
-- is built twice from this code: inside the /queb window and inside
-- Esc > Options > AddOns > Queb. Both instances share QuebDB and refresh
-- together.
---------------------------------------------------------------------------
B.panels = {}
local TABS = { { id = "buddies", text = "Buddies" }, { id = "settings", text = "Settings" } }

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

  -- Buddies page
  local bp = CreateFrame("Frame", nil, panel)
  bp:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
  bp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  local inset = MakeInset(bp)
  inset:SetPoint("TOPLEFT", bp, "TOPLEFT", 0, 0)
  inset:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", 0, 20)
  panel.empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  panel.empty:SetPoint("CENTER")
  panel.empty:SetText("No quest buddies online")
  local footer = bp:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", bp, "BOTTOMLEFT", 6, 4)
  footer:SetText("Hover a row for details")
  BuildList(panel, inset)
  panel.pages.buddies = bp

  -- Settings page
  local sp = ns.Options:BuildPage(panel)
  sp:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
  sp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  panel.pages.settings = sp

  panel:SetScript("OnShow", function(self) B:UpdatePanel(self) end)
  self.panels[#self.panels + 1] = panel
  panel:SelectTab((ns.db and ns.db.lastTab) or "buddies")
  return panel
end

function B:UpdatePanel(panel)
  if not panel:IsVisible() or panel.selected ~= "buddies" then return end
  local items = BuildItems()
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
  f:SetSize(WIN_W, WIN_H)
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
      self.panel:SetSize(WIN_W - 16, WIN_H - 36)
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
ns.Listen("LOCAL_QUESTS_CHANGED", Refresh)
ns.On("GROUP_ROSTER_UPDATE", Refresh)
