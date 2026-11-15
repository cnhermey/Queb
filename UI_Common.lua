-- Queb: class-colored dot groups + tooltip, shared by all decorators.
--
-- Taint rules followed here: we only create frames we own, parent/anchor them
-- to Blizzard rows, keep all bookkeeping in our own tables, and never write
-- fields onto Blizzard frames.
local addonName, ns = ...

local UI = {
  decorators = {},  -- [name] = function() that (re)decorates visible rows
  owned = {},       -- [decoratorName] = { [key] = group }
  ours = setmetatable({}, { __mode = "k" }), -- frames we created (tooltip hook skips them)
}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
UI.MEDIA = MEDIA
local DOT, GAP = 10, 2
local UNKNOWN_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

---------------------------------------------------------------------------
-- Native look: Blizzard colors and textures.
-- Style rule: every Queb element should look like Blizzard's own UI, so we
-- use Blizzard's color constants and art, falling back to ours only when the
-- Blizzard asset is missing on this build.
---------------------------------------------------------------------------
local function Const(c, r, g, b)
  if type(c) == "table" and c.r then return c end
  return { r = r, g = g, b = b }
end
UI.GOLD  = Const(NORMAL_FONT_COLOR, 1, 0.82, 0)      -- headers, counts
UI.WHITE = Const(HIGHLIGHT_FONT_COLOR, 1, 1, 1)
UI.GRAY  = Const(GRAY_FONT_COLOR, 0.5, 0.5, 0.5)
UI.GREEN = Const(GREEN_FONT_COLOR, 0.1, 1, 0.1)
UI.RED   = Const(RED_FONT_COLOR, 1, 0.1, 0.1)
UI.DISABLED = Const(DISABLED_FONT_COLOR, 0.5, 0.5, 0.5)

local function Hex(c)
  return string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end
-- Wrap text in one of the colors above.
function UI.Wrap(c, text) return "|c" .. Hex(c) .. text .. "|r" end
local Wrap = UI.Wrap

-- Blizzard's round mask (white disc) when this build has it; else our TGA.
local function FileExists(path)
  if GetFileIDFromPath then
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil
  end
  return false
end
local BLIZZ_CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
UI.CIRCLE = FileExists(BLIZZ_CIRCLE) and BLIZZ_CIRCLE or (MEDIA .. "Circle")
UI.RING = MEDIA .. "Ring" -- no Blizzard gold ring at this size; ours is tinted Blizzard gold

-- "Can share" marker: Blizzard's yellow "!" (available quest). Never class-
-- colored, so it can't be mistaken for a guildmate circle or the gold ring.
local SHARE_ATLAS = "QuestNormal"
local SHARE_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"
local function HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
function UI:ShareIcon(size)
  size = size or 12
  if self.shareSource == nil then self.shareSource = HasAtlas(SHARE_ATLAS) and "atlas" or "texture" end
  if self.shareSource == "atlas" then
    return string.format("|A:%s:%d:%d|a", SHARE_ATLAS, size, size)
  end
  return string.format("|T%s:%d:%d|t", SHARE_TEXTURE, size, size)
end

local function ClassColor(classFile)
  if classFile then
    if C_ClassColor and C_ClassColor.GetClassColor then
      local c = C_ClassColor.GetClassColor(classFile)
      if c then return c end
    end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
      return RAID_CLASS_COLORS[classFile]
    end
  end
  return UNKNOWN_COLOR
end
UI.ClassColor = ClassColor

local function ColorName(name, classFile)
  local c = ClassColor(classFile)
  return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end
UI.ColorName = ColorName

-- Why a player's shared quests can't be shown, per Peers:SharedWith status.
-- One source of truth so every Queb tooltip gives the same answer.
-- Style rule: short phrases. Unknown status shows the reason alone (no prefix).
UI.STATUS_REASONS = {
  syncing = "syncing",
  far     = "too far away",
  offline = "offline",
  noaddon = "no Queb, not grouped",
}

-- Inline class-colored circle for tooltip/chat text (|T...|t with vertex color).
function UI:CircleIcon(classFile, size)
  local c = ClassColor(classFile)
  size = size or 12
  return string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t", UI.CIRCLE, size, size,
    math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

-- Append "also on this quest" lines (guildmates and group members) to an already-populated tooltip.
-- Returns true if anything was added. Caller is responsible for :Show().
-- Layout follows Blizzard's tooltips: blank spacer, gold section header,
-- then name / progress double lines.
local TOOLTIP_MAX = 5
local NO_QUEB_ON_QUEST = "on quest, no Queb"
local SHARE_NAMES_MAX = 4

-- "! Can share with: Asha, Bren" — guildmates who could take this quest
-- from you. Returns true if a line was added.
function UI:AddShareTargetsLine(tooltip, questID)
  local targets = ns.Peers:ShareTargets(questID)
  if #targets == 0 then return false end
  local names = {}
  for i = 1, math.min(#targets, SHARE_NAMES_MAX) do names[i] = ColorName(targets[i].name, targets[i].class) end
  local text = self:ShareIcon(12) .. " " .. Wrap(UI.GOLD, "Can share with:") .. " " .. table.concat(names, ", ")
  if #targets > SHARE_NAMES_MAX then text = text .. Wrap(UI.GRAY, string.format(" +%d", #targets - SHARE_NAMES_MAX)) end
  tooltip:AddLine(text, 1, 1, 1, true)
  return true
end

function UI:AddSharersToTooltip(tooltip, questID)
  local sharers = ns.Peers:GetSharers(questID)
  local hasTargets = #ns.Peers:ShareTargets(questID) > 0
  if #sharers == 0 and not hasTargets then return false end
  tooltip:AddLine(" ")
  if #sharers > 0 then
    tooltip:AddLine("Also on this quest", UI.GOLD.r, UI.GOLD.g, UI.GOLD.b)
    for i = 1, math.min(#sharers, TOOLTIP_MAX) do
      local s = sharers[i]
      local prog = s.hasAddon and self:ProgressText(s.complete, s.objectives) or Wrap(UI.GRAY, NO_QUEB_ON_QUEST)
      tooltip:AddDoubleLine(self:CircleIcon(s.class, 10) .. " " .. ColorName(s.name, s.class), prog)
    end
    if #sharers > TOOLTIP_MAX then
      tooltip:AddLine(Wrap(UI.GRAY, string.format("+%d more", #sharers - TOOLTIP_MAX)))
    end
  end
  self:AddShareTargetsLine(tooltip, questID)
  return true
end

---------------------------------------------------------------------------
-- Progress text for tooltips (Blizzard colors: green done, white counts)
---------------------------------------------------------------------------
function UI:ProgressText(complete, objectives)
  if complete then return Wrap(UI.GREEN, "Ready to turn in") end
  if not objectives then return Wrap(UI.GRAY, "no progress data") end
  if #objectives == 0 then return Wrap(UI.WHITE, "In progress") end
  local parts = {}
  for i = 1, math.min(#objectives, 4) do
    local o = objectives[i]
    parts[#parts + 1] = Wrap((o[1] >= o[2]) and UI.GREEN or UI.WHITE, o[1] .. "/" .. o[2])
  end
  if #objectives > 4 then parts[#parts + 1] = "…" end
  return table.concat(parts, "  ")
end

local SOURCE_TAG = { group = "group", demo = "demo", other = nil, guild = nil }

function UI:ShowSharersTooltip(owner, questID)
  if not questID then return end
  local sharers = ns.Peers:GetSharers(questID)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(ns.QuestState:GetTitle(questID) or ("Quest " .. questID), UI.GOLD.r, UI.GOLD.g, UI.GOLD.b)
  GameTooltip:AddLine("Also on this quest", UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
  local mine = ns.QuestState.quests[questID]
  if mine then
    local _, myClassFile = UnitClass("player")
    if ns.IsSecret(myClassFile) then myClassFile = nil end
    GameTooltip:AddDoubleLine(ColorName("You", myClassFile), self:ProgressText(mine.c, mine.obj))
  end
  for _, s in ipairs(sharers) do
    local label = ColorName(s.name, s.class)
    local tag = SOURCE_TAG[s.source]
    if tag then label = label .. " " .. Wrap(UI.GRAY, "(" .. tag .. ")") end
    local prog = s.hasAddon and self:ProgressText(s.complete, s.objectives) or Wrap(UI.GRAY, NO_QUEB_ON_QUEST)
    GameTooltip:AddDoubleLine(label, prog)
  end
  if #sharers == 0 then GameTooltip:AddLine("Nobody yet", UI.GRAY.r, UI.GRAY.g, UI.GRAY.b) end
  self:AddShareTargetsLine(GameTooltip, questID)
  -- Blizzard-style click hint: green, in angle brackets
  GameTooltip:AddLine("<Click: Quebmates>", UI.GREEN.r, UI.GREEN.g, UI.GREEN.b)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Dot group widget (our own frame; pooled)
---------------------------------------------------------------------------
local free = {}

-- One dot = Blizzard's round mask in three layers, shaded like the class-
-- colored party blips on Blizzard's minimap: dark rim, class-colored fill,
-- soft highlight on top. Gold ring (Blizzard gold) = ready to turn in.
local function CreateDot(g)
  local d = {}
  d.shadow = g:CreateTexture(nil, "ARTWORK", nil, 1)
  d.shadow:SetTexture(UI.CIRCLE)
  d.shadow:SetVertexColor(0, 0, 0, 0.85)
  d.shadow:SetSize(DOT + 2, DOT + 2)

  d.fill = g:CreateTexture(nil, "ARTWORK", nil, 2)
  d.fill:SetTexture(UI.CIRCLE)
  d.fill:SetSize(DOT, DOT)
  d.fill:SetPoint("CENTER", d.shadow, "CENTER")

  d.shine = g:CreateTexture(nil, "ARTWORK", nil, 3)
  d.shine:SetTexture(UI.CIRCLE)
  d.shine:SetVertexColor(1, 1, 1, 0.3)
  d.shine:SetBlendMode("ADD")
  d.shine:SetSize(DOT * 0.45, DOT * 0.45)
  d.shine:SetPoint("CENTER", d.shadow, "CENTER", -DOT * 0.15, DOT * 0.18)

  d.ring = g:CreateTexture(nil, "ARTWORK", nil, 4)
  d.ring:SetTexture(UI.RING)
  d.ring:SetVertexColor(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 1)
  d.ring:SetSize(DOT + 4, DOT + 4)
  d.ring:SetPoint("CENTER", d.shadow, "CENTER")
  return d
end

local function SetDotShown(d, shown)
  d.shadow:SetShown(shown)
  d.fill:SetShown(shown)
  d.shine:SetShown(shown)
  if not shown then d.ring:Hide() end
end

local function CreateGroup()
  local g = CreateFrame("Button", nil, UIParent)
  UI.ours[g] = true
  g:SetSize(DOT, DOT + 2)
  g.dots = {}
  g.more = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  g.more:SetPoint("LEFT", g, "LEFT", 0, 0)
  g:SetScript("OnEnter", function(self) UI:ShowSharersTooltip(self, self.questID) end)
  g:SetScript("OnLeave", function() GameTooltip:Hide() end)
  g:SetScript("OnClick", function() ns.Buddies:Toggle("buddies") end)
  return g
end

-- Width of `n` dots plus a "+N" label for the rest.
local function GroupWidth(g, n, total)
  local w = n * (DOT + GAP)
  if total > n then
    g.more:SetText("+" .. (total - n))
    w = w + g.more:GetStringWidth() + 1
  end
  return w
end

-- Lays out dots left-to-right (first sharer closest to the title), then
-- "+N". With g.maxWidth set, drops dots until everything fits; returns false
-- if not even one dot fits.
local function Layout(g, sharers)
  local total = #sharers
  local maxDots = math.max(1, math.min(g.maxDots or 99, ns.db.maxDots or 5))
  local shown = math.min(total, maxDots)
  if g.maxWidth then
    while shown > 0 and GroupWidth(g, shown, total) > g.maxWidth do shown = shown - 1 end
    if shown == 0 then return false end
  end
  local x = 0
  for i = 1, shown do
    local s = sharers[i]
    local d = g.dots[i] or CreateDot(g)
    g.dots[i] = d
    local c = ClassColor(s.class)
    d.fill:SetVertexColor(c.r, c.g, c.b, s.hasAddon and 1 or 0.45)
    d.shine:SetAlpha(s.hasAddon and 1 or 0.4)
    d.shadow:ClearAllPoints()
    d.shadow:SetPoint("LEFT", g, "LEFT", x + 1, 0)
    SetDotShown(d, true)
    d.ring:SetShown(s.complete == true)
    x = x + DOT + GAP
  end
  for i = shown + 1, #g.dots do SetDotShown(g.dots[i], false) end
  if total > shown then
    g.more:SetText("+" .. (total - shown))
    g.more:ClearAllPoints()
    g.more:SetPoint("LEFT", g, "LEFT", x, 0)
    g.more:Show()
    x = x + g.more:GetStringWidth() + 1
  else
    g.more:Hide()
  end
  g:SetSize(math.max(DOT, x), DOT + 4)
  return true
end

-- Show dots for questID on a row. `key` identifies the row (any table; it
-- is only used as a key in our own table). `maxDots` caps the dot count and
-- `maxWidth` the group's width, for tight spaces. Returns true if shown.
function UI:SetDots(decorator, key, parent, questID, point, relTo, relPoint, x, y, maxDots, maxWidth)
  local owned = self.owned[decorator]
  if not owned then
    owned = setmetatable({}, { __mode = "k" })
    self.owned[decorator] = owned
  end
  local sharers = ns.Peers:GetSharers(questID)
  if #sharers == 0 then
    self:Release(decorator, key)
    return false
  end
  local g = owned[key]
  if not g then
    g = table.remove(free) or CreateGroup()
    owned[key] = g
  end
  g.questID = questID
  g.maxDots = maxDots
  g.maxWidth = maxWidth
  if not Layout(g, sharers) then
    self:Release(decorator, key)
    return false
  end
  g:SetParent(parent)
  g:SetFrameLevel(parent:GetFrameLevel() + 10)
  g:ClearAllPoints()
  g:SetPoint(point, relTo, relPoint, x or 0, y or 0)
  g:Show()
  return true
end

---------------------------------------------------------------------------
-- Placement after a title's text, inside free space only.
--
-- Measures where the title's text actually ends, skips small icons glued to
-- its end (e.g. the Classic quest log's watch checkmark), then finds the
-- nearest visible element to its right inside the row (Modern checkmark,
-- buttons, ...). Dots go in the gap; if the title wraps or is truncated, or
-- the gap is too small, no dots are drawn on that row (the tooltip still
-- shows them). Nothing is ever drawn over Blizzard's own elements.
---------------------------------------------------------------------------
local function Num(v)
  if v == nil or ns.IsSecret(v) then return nil end
  return v
end

local function ForEachElement(container, fn)
  for _, r in ipairs({ container:GetRegions() }) do fn(r) end
  for _, c in ipairs({ container:GetChildren() }) do
    if not UI.ours[c] then fn(c) end
  end
end

function UI:SetDotsAfterText(decorator, key, container, questID, text, maxDots)
  local left, width = Num(text:GetLeft()), Num(text:GetWidth())
  local rowRight = Num(container:GetRight())
  if not (left and width and rowRight) or width <= 0 then
    self:Release(decorator, key)
    return false
  end
  local full = Num(text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth())
  if not full or full > width + 1 then -- wrapped or cut with "..."
    self:Release(decorator, key)
    return false
  end
  local textEnd = left + full
  local textTop, textBottom = Num(text:GetTop()), Num(text:GetBottom())

  -- Small icons attached right after the text: start after them.
  ForEachElement(container, function(r)
    if r ~= text and r:IsVisible() then
      local l, rr, w = Num(r:GetLeft()), Num(r:GetRight()), Num(r:GetWidth())
      if l and rr and w and w <= 24 and l >= textEnd - 2 and l <= textEnd + 10 then
        textEnd = math.max(textEnd, rr)
      end
    end
  end)

  -- Nearest element to the right on the same line.
  local bound = rowRight - 2
  ForEachElement(container, function(r)
    if r ~= text and r:IsVisible() then
      local l, t, b = Num(r:GetLeft()), Num(r:GetTop()), Num(r:GetBottom())
      local sameLine = not (textTop and textBottom and t and b) or (b < textTop and t > textBottom)
      if l and sameLine and l > textEnd + 1 and l < bound then bound = l end
    end
  end)

  local startX = textEnd + 5
  local room = bound - 3 - startX
  if room < DOT + 2 then
    self:Release(decorator, key)
    return false
  end
  return self:SetDots(decorator, key, container, questID, "TOPLEFT", text, "TOPLEFT",
    startX - left, 1, maxDots, room)
end

function UI:Release(decorator, key)
  local owned = self.owned[decorator]
  local g = owned and owned[key]
  if not g then return end
  owned[key] = nil
  g:Hide()
  g:ClearAllPoints()
  g:SetParent(UIParent)
  g.questID = nil
  free[#free + 1] = g
end

-- Release every group of `decorator` whose key wasn't seen this pass.
function UI:ReleaseUnseen(decorator, seen)
  local owned = self.owned[decorator]
  if not owned then return end
  local stale = {}
  for key in pairs(owned) do
    if not seen[key] then stale[#stale + 1] = key end
  end
  for _, key in ipairs(stale) do self:Release(decorator, key) end
end

---------------------------------------------------------------------------
-- Refresh: always deferred and coalesced, never inside a Blizzard call stack.
---------------------------------------------------------------------------
function UI:RegisterDecorator(name, fn)
  self.decorators[name] = fn
end

function UI:Refresh()
  ns.Coalesce("ui_refresh", 0.1, function()
    if not ns.db then return end
    for _, fn in pairs(UI.decorators) do fn() end
  end)
end

ns.Listen("LOGIN", function() UI:Refresh() end)
