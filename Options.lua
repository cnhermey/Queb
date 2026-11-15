-- Queb: Settings tab of the main Queb window.
--
-- Every setting that used to be a slash command lives here as a Blizzard
-- control (UICheckButtonTemplate checkboxes, MinimalSliderWithSteppers
-- sliders, UIPanelButtonTemplate buttons). The same page is built inside the
-- /queb window and inside Esc > Options > AddOns > Queb (see Buddies.lua);
-- both read and write QuebDB through Options:Set, so they stay in sync.
-- Style rules: native Blizzard look, short labels.
local _, ns = ...

local O = { pages = {} }
ns.Options = O

local function PlaySoundSafe(kit)
  if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

-- Settings that change who we talk to need the comm layer to react.
local COMM_KEYS = { shareGuild = true, shareParty = true }

-- Central setter: every control (and any future caller) goes through here.
function O:Set(key, value)
  if not ns.db or ns.db[key] == value then return end
  ns.db[key] = value
  if COMM_KEYS[key] and ns.Comm and ns.Comm.OnSettingsChanged then ns.Comm:OnSettingsChanged() end
  if key == "shareQuests" and ns.Comm and ns.Comm.OnShareChanged then ns.Comm:OnShareChanged() end
  ns.Fire("SETTINGS_CHANGED")
  ns.UI:Refresh()
  if ns.Buddies and ns.Buddies.Update then ns.Buddies:Update() end
  self:RefreshAll()
end

function O:SetDemo(on)
  if (ns.demoOn and true or false) == on then return end
  ns.demoOn = on
  ns.Peers:SetDemo(on)
  self:RefreshAll()
end

---------------------------------------------------------------------------
-- Layout: two columns of sections.
---------------------------------------------------------------------------
-- kind: check (saved bool), slider (saved number), demo, debug-like checks, button
local LAYOUT = {
  {
    { header = "Circles" },
    { kind = "check", key = "showInQuestLog", label = "Quest log" },
    { kind = "check", key = "showInTracker",  label = "Objective tracker" },
    { kind = "check", key = "showInTooltips", label = "Quest tooltips" },
    { kind = "check", key = "showInGuild",    label = "Guild tooltips" },
    { kind = "check", key = "showOnMap",      label = "OpenMap players" },
    { kind = "slider", key = "maxDots", label = "Max circles", min = 1, max = 10 },
    { header = "Testing" },
    { kind = "demo", label = "Demo guildmates" },
    { kind = "check", key = "debug", label = "Debug messages" },
    { kind = "button", label = "Resync", width = 100, onClick = function()
        for _, ch in ipairs(ns.Comm:ActiveChannels()) do ns.Comm:SendHello(ch, true) end
        ns.Print("Sync requested")
      end },
  },
  {
    { header = "Sharing" },
    { kind = "check", key = "shareGuild",        label = "Guild" },
    { kind = "check", key = "shareParty",        label = "Party and raid" },
    { kind = "check", key = "showNonAddonParty", label = "Group members without Queb" },
    { header = "Quebmates" },
    { kind = "check", key = "loginSummary", label = "Summary at login" },
    { kind = "check", key = "showNearby",   label = "Near your level" },
    { kind = "check", key = "shareQuests",  label = "Can share" },
    { kind = "slider", key = "nearbyLevelRange", label = "Level range", min = 0, max = 10, prefix = "±" },
  },
}

local COL_W = 214
local CHECK_H, SLIDER_H, HEADER_H, BUTTON_H = 26, 44, 26, 30

local function CheckLabel(cb)
  local t = cb.Text or cb.text
  if not t then
    t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  else
    t:SetFontObject("GameFontHighlight")
  end
  return t
end

local function MakeCheck(page, parent, item)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  CheckLabel(cb):SetText(item.label)
  cb:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    PlaySoundSafe(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
    if item.kind == "demo" then O:SetDemo(on) else O:Set(item.key, on) end
  end)
  page.refreshers[#page.refreshers + 1] = function()
    if item.kind == "demo" then
      cb:SetChecked(ns.demoOn and true or false)
    else
      cb:SetChecked(ns.db[item.key] and true or false)
    end
  end
  return cb, CHECK_H
end

-- Slider: Blizzard's MinimalSliderWithSteppers when available, else
-- Blizzard buttons as - / + steppers. Value shown in a Blizzard font.
local function MakeSlider(page, parent, item)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(COL_W - 8, SLIDER_H)
  local label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, 0)
  label:SetText(item.label)
  local valueText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

  local function Show(v) valueText:SetText((item.prefix or "") .. v) end
  local function Set(v)
    v = math.max(item.min, math.min(item.max, math.floor(v + 0.5)))
    Show(v)
    O:Set(item.key, v)
  end

  local slider
  if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
    local ok, s = pcall(CreateFrame, "Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
    if ok and s and s.Init then
      s:SetSize(150, 20)
      s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
      local initOk = pcall(s.Init, s, ns.db[item.key] or item.min, item.min, item.max, item.max - item.min)
      if initOk then
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v) Set(v) end, holder)
        slider = s
        valueText:SetPoint("LEFT", s, "RIGHT", 8, 0)
      else
        s:Hide()
      end
    end
  end
  if not slider then
    local minus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    minus:SetSize(24, 20)
    minus:SetText("-")
    minus:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    valueText:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    valueText:SetWidth(30)
    local plus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    plus:SetSize(24, 20)
    plus:SetText("+")
    plus:SetPoint("LEFT", valueText, "RIGHT", 6, 0)
    minus:SetScript("OnClick", function() Set((ns.db[item.key] or item.min) - 1) end)
    plus:SetScript("OnClick", function() Set((ns.db[item.key] or item.min) + 1) end)
  end

  page.refreshers[#page.refreshers + 1] = function()
    local v = ns.db[item.key] or item.min
    Show(v)
    if slider and slider.SetValue then
      page.updating = true
      pcall(slider.SetValue, slider, v)
      page.updating = false
    end
  end
  return holder, SLIDER_H
end

local function MakeButton(_, parent, item)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(item.width or 100, 22)
  b:SetText(item.label)
  b:SetScript("OnClick", function()
    PlaySoundSafe("IG_MAINMENU_OPTION")
    item.onClick()
  end)
  return b, BUTTON_H
end

local function MakeHeader(_, parent, item)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- gold, like Blizzard's option headers
  fs:SetText(item.header)
  return fs, HEADER_H
end

-- Build the Settings page inside `parent`. Returns the page frame.
function O:BuildPage(parent)
  local page = CreateFrame("Frame", nil, parent)
  page.refreshers = {}
  local lowest = 0
  for col, items in ipairs(LAYOUT) do
    local x, y = 8 + (col - 1) * COL_W, -6
    for _, item in ipairs(items) do
      local widget, h
      if item.header then
        widget, h = MakeHeader(page, page, item)
        if y < -6 then y = y - 6 end
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 6)
      elseif item.kind == "check" or item.kind == "demo" then
        widget, h = MakeCheck(page, page, item)
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
      elseif item.kind == "slider" then
        widget, h = MakeSlider(page, page, item)
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", x, y - 2)
      elseif item.kind == "button" then
        widget, h = MakeButton(page, page, item)
        widget:SetPoint("TOPLEFT", page, "TOPLEFT", x + 4, y - 4)
      end
      y = y - h
    end
    lowest = math.min(lowest, y)
  end
  -- height the content needs (the panel scrolls the page when it's taller
  -- than the window)
  page.contentHeight = -lowest + 10
  page.contentWidth = 8 + #LAYOUT * COL_W
  page:SetScript("OnShow", function(self) O:RefreshPage(self) end)
  self.pages[#self.pages + 1] = page
  return page
end

function O:RefreshPage(page)
  if not ns.db then return end
  for _, fn in ipairs(page.refreshers) do fn() end
end

function O:RefreshAll()
  for _, page in ipairs(self.pages) do
    if page:IsVisible() then self:RefreshPage(page) end
  end
end
