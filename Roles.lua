-- Queb: roles (Tank / Healer / Damage).
--
-- Each player picks any combination of roles in the role picker next to the
-- Quebmates / Settings tabs (like Blizzard's Dungeon Finder role check).
-- Roles a class can't play on Forever aren't shown at all. The choice is saved in
-- QuebDB.roles and sent to other Queb users (HI field 5 and an "@TH" part in
-- ST; older builds ignore both). Quebmates then show role icons next to each
-- name. Group members without Queb fall back to their assigned group role.
-- Style rules: Blizzard role icons (feature-detected), short labels.
local _, ns = ...

local R = { pickers = {} }
ns.Roles = R

R.ORDER = { "tank", "healer", "damage" }
local LETTER = { tank = "T", healer = "H", damage = "D" }
local FROM_LETTER = { T = "tank", H = "healer", D = "damage" }
local LABEL = { tank = "Tank", healer = "Healer", damage = "Damage" }
local BLIZZ_ROLE = { tank = "TANK", healer = "HEALER", damage = "DAMAGER" }
local FROM_BLIZZ = { TANK = "tank", HEALER = "healer", DAMAGER = "damage" }
R.LABEL = LABEL

-- Forever: 9 classes; tanks Warrior/Paladin/Druid, healers Paladin/Priest/Shaman/Druid.
local CLASS_ROLES = {
  WARRIOR = { tank = true, damage = true },
  PALADIN = { tank = true, healer = true, damage = true },
  HUNTER  = { damage = true },
  ROGUE   = { damage = true },
  PRIEST  = { healer = true, damage = true },
  SHAMAN  = { healer = true, damage = true },
  MAGE    = { damage = true },
  WARLOCK = { damage = true },
  DRUID   = { tank = true, healer = true, damage = true },
}

local function MyClass()
  local _, c = UnitClass("player")
  if ns.IsSecret(c) then return nil end
  return c
end

-- Can this class play this role? Unknown class = allow everything.
function R:Allowed(classFile, role)
  local t = classFile and CLASS_ROLES[classFile]
  if not t then return true end
  return t[role] == true
end

---------------------------------------------------------------------------
-- Wire format: letters "THD" in that order, or "-" for none.
---------------------------------------------------------------------------
function R:Encode(roles)
  local s = ""
  for _, r in ipairs(self.ORDER) do
    if roles and roles[r] then s = s .. LETTER[r] end
  end
  return s ~= "" and s or "-"
end

-- Returns a roles table ({} for "-") or nil when the text isn't a role field.
function R:Decode(text)
  if text == "-" then return {} end
  if type(text) ~= "string" or not string.match(text, "^[THD]+$") or #text > 3 then return nil end
  local t = {}
  for ch in string.gmatch(text, ".") do t[FROM_LETTER[ch]] = true end
  return t
end

function R:EncodeMine()
  return self:Encode(ns.db and ns.db.roles)
end

---------------------------------------------------------------------------
-- Your roles
---------------------------------------------------------------------------
function R:Mine()
  return ns.db and ns.db.roles or {}
end

function R:Set(role, on)
  local roles = ns.db.roles
  if (roles[role] and true or false) == on then return end
  roles[role] = on or nil
  self:RefreshPickers()
  ns.Fire("ROLES_CHANGED")
  if ns.Buddies and ns.Buddies.Update then ns.Buddies:Update() end
  -- tell other Queb users (coalesced, so clicking three boxes sends once)
  ns.Coalesce("roles_hi", 2, function()
    for _, ch in ipairs(ns.Comm:ActiveChannels()) do ns.Comm:SendHello(ch, false) end
  end)
end

-- First run: a class with only one possible role gets it ticked; others
-- start empty so the player picks.
ns.Listen("LOGIN", function()
  local db = ns.db
  local class = MyClass()
  if type(db.roles) ~= "table" then
    db.roles = {}
    local t = class and CLASS_ROLES[class]
    if t then
      local only, n = nil, 0
      for r in pairs(t) do only, n = r, n + 1 end
      if n == 1 then db.roles[only] = true end
    end
  end
  -- drop roles this class can't play (e.g. SavedVariables shared oddly)
  for _, r in ipairs(R.ORDER) do
    if db.roles[r] and not R:Allowed(class, r) then db.roles[r] = nil end
  end
end)

---------------------------------------------------------------------------
-- Someone else's roles
---------------------------------------------------------------------------
-- `entry` = a Quebmates/nearby list entry ({ peer?, unit? }) or a peer.
function R:For(entry)
  local peer = entry and (entry.peer or (entry.sources and entry))
  if peer and peer.roles then return peer.roles end
  local unit = entry and entry.unit
  if unit and UnitGroupRolesAssigned then
    local ok, r = pcall(UnitGroupRolesAssigned, unit)
    if ok and r and not ns.IsSecret(r) and FROM_BLIZZ[r] then return { [FROM_BLIZZ[r]] = true } end
  end
  return nil
end

---------------------------------------------------------------------------
-- Icons: Blizzard's role icons. Atlases first, then the classic LFG texture
-- with Blizzard's own coordinates.
---------------------------------------------------------------------------
local ATLASES = {
  tank   = { "roleicon-tiny-tank", "UI-LFG-RoleIcon-Tank-Micro", "UI-LFG-RoleIcon-Tank" },
  healer = { "roleicon-tiny-healer", "UI-LFG-RoleIcon-Healer-Micro", "UI-LFG-RoleIcon-Healer" },
  damage = { "roleicon-tiny-dps", "UI-LFG-RoleIcon-DPS-Micro", "UI-LFG-RoleIcon-DPS" },
}
local ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local FILE_COORDS = { -- GetTexCoordsForRoleSmallCircle values
  tank = { 0, 19 / 64, 22 / 64, 41 / 64 },
  healer = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
  damage = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

local atlasCache = {}
local function Atlas(role)
  if atlasCache[role] ~= nil then return atlasCache[role] or nil end
  local found = false
  if C_Texture and C_Texture.GetAtlasInfo then
    for _, a in ipairs(ATLASES[role]) do
      if C_Texture.GetAtlasInfo(a) then found = a break end
    end
  end
  atlasCache[role] = found
  return found or nil
end

local function Coords(role)
  if GetTexCoordsForRoleSmallCircle then
    local ok, l, r, t, b = pcall(GetTexCoordsForRoleSmallCircle, BLIZZ_ROLE[role])
    if ok and l then return l, r, t, b end
  end
  return unpack(FILE_COORDS[role])
end

function R:SetIcon(tex, role)
  local atlas = Atlas(role)
  if atlas then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture(ROLE_FILE)
    tex:SetTexCoord(Coords(role))
  end
end

-- Inline icon for tooltips / chat.
function R:Inline(role, size)
  size = size or 12
  local atlas = Atlas(role)
  if atlas then return string.format("|A:%s:%d:%d|a", atlas, size, size) end
  local l, r, t, b = Coords(role)
  return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", ROLE_FILE, size, size,
    math.floor(l * 64 + 0.5), math.floor(r * 64 + 0.5), math.floor(t * 64 + 0.5), math.floor(b * 64 + 0.5))
end

function R:IconSource()
  return Atlas("tank") or "LFG texture"
end

---------------------------------------------------------------------------
-- Role picker: three Blizzard role icons, each with a checkbox, like the
-- Dungeon Finder role check. Built inside each Queb panel's tab row.
---------------------------------------------------------------------------
local CELL = 30

local function PlaySoundSafe(kit)
  if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

function R:BuildPicker(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(#self.ORDER * CELL + 44, 30)
  p.label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- gold, short
  p.label:SetPoint("LEFT", p, "LEFT", 0, 0)
  p.label:SetText("Role")
  p.cells = {}
  for i, role in ipairs(self.ORDER) do
    local cell = CreateFrame("Button", nil, p)
    cell:SetSize(CELL - 4, 26)
    cell:SetPoint("LEFT", p, "LEFT", 40 + (i - 1) * CELL, 0)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(22, 22)
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    self:SetIcon(cell.icon, role)
    local cb = CreateFrame("CheckButton", nil, cell, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 4, -4)
    cb:SetScript("OnClick", function(btn)
      local on = btn:GetChecked() and true or false
      PlaySoundSafe(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
      R:Set(role, on)
    end)
    cell.check = cb
    -- clicking the icon toggles too, like Blizzard's role buttons
    cell:SetScript("OnClick", function()
      if cb:IsEnabled() then cb:Click() end
    end)
    local function Tip(owner)
      GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
      GameTooltip:SetText(LABEL[role], 1, 1, 1)
      GameTooltip:Show()
    end
    cell:SetScript("OnEnter", Tip)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnEnter", function() Tip(cell) end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cell.role = role
    p.cells[i] = cell
  end
  p:SetScript("OnShow", function(self) R:RefreshPicker(self) end)
  self.pickers[#self.pickers + 1] = p
  self:RefreshPicker(p)
  return p
end

-- Only the roles this class can play get a cell; the rest are hidden and
-- the visible ones close up (e.g. a Mage sees just "Role [Damage]").
function R:RefreshPicker(p)
  if not ns.db or not ns.db.roles then return end
  local class = MyClass()
  local n = 0
  for _, cell in ipairs(p.cells) do
    local allowed = self:Allowed(class, cell.role)
    cell:SetShown(allowed)
    if allowed then
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", p, "LEFT", 40 + n * CELL, 0)
      cell.check:SetChecked(ns.db.roles[cell.role] and true or false)
      n = n + 1
    end
  end
  p:SetWidth(40 + n * CELL + 4) -- picker is anchored by its right edge
end

function R:RefreshPickers()
  for _, p in ipairs(self.pickers) do self:RefreshPicker(p) end
end

---------------------------------------------------------------------------
-- Role icons inside a list row: up to three textures, left to right.
---------------------------------------------------------------------------
R.ROW_SLOTS_W = 3 * 15

function R:InitRowIcons(row, anchorTo)
  row.roleIcons = {}
  for i = 1, 3 do
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    t:SetPoint("LEFT", anchorTo, "RIGHT", 2 + (i - 1) * 15, 0)
    t:Hide()
    row.roleIcons[i] = t
  end
end

function R:ShowRowIcons(row, roles, alpha)
  local n = 0
  for _, role in ipairs(self.ORDER) do
    if roles and roles[role] then
      n = n + 1
      local t = row.roleIcons[n]
      self:SetIcon(t, role)
      t:SetAlpha(alpha or 1)
      t:Show()
    end
  end
  for i = n + 1, 3 do row.roleIcons[i]:Hide() end
end

function R:HideRowIcons(row)
  if not row.roleIcons then return end
  for i = 1, 3 do row.roleIcons[i]:Hide() end
end
