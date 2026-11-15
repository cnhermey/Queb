-- Queb: shared quests on OpenMap's player markers.
--
-- OpenMap (jiforever) draws players on its stitched world map, inside
-- WorldMapFrame, and each marker shows a plain GameTooltip:
--   * guild/friend dot (Map/Friends.lua): someone sharing their position.
--       pin.data = { full = "Name-Realm", p = { class, level, guild, guid, ... },
--                    roster = { name, class, guild, guid, ... } }
--   * zone badge (Map/Friends.lua): guildmates/friends known only by zone.
--       pin.data = { map = uiMapID, people = { roster rows } }
--   * group dot (Map/Nav.lua): a party/raid member. pin.unit = "party1"...
-- UI_Tooltip.lua's GameTooltip:Show post-hook hands those owners here and we
-- append our lines. Nothing is written to OpenMap's frames.
--
-- These pin fields are OpenMap internals, not its public OpenMapAPI (read on
-- OpenMap's 2026-11-14 build). Every read is type-checked; anything unexpected
-- adds nothing. The only public API we use is RegisterMenuToggle (a switch in
-- OpenMap's own menu).
local _, ns = ...
local UI = ns.UI

local OM = { kinds = {} }
ns.OpenMapUI = OM

local ZONE_MAX = 6

local function Str(v)
  if type(v) == "string" and not ns.IsSecret(v) and v ~= "" then return v end
end

local function Available() return type(OpenMapAPI) == "table" end

-- A frame made by OpenMap's S.AddPin: a Button with .Icon and world coords.
local function IsPin(owner)
  return type(owner) == "table" and type(owner.u) == "number" and type(owner.v) == "number"
    and owner.anchor ~= nil and owner.Icon ~= nil
end

-- Which kind of OpenMap marker this is, or nil.
function OM:KindOf(owner)
  if not Available() or not IsPin(owner) then return nil end
  local d = owner.data
  if type(d) == "table" then
    if type(d.p) == "table" and Str(d.full) then return "dot" end
    if type(d.people) == "table" then return "zone" end
  end
  if Str(owner.unit) then return "group" end
end

-- Name (+ class) from a GUID, so names match however OpenMap spelled them.
local function FromGUID(guid)
  guid = Str(guid)
  if not guid or not GetPlayerInfoByGUID then return end
  local ok, _, class, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
  if not ok then return end
  name = Str(name)
  if not name then return end
  realm = Str(realm)
  return realm and (name .. "-" .. realm) or name, Str(class)
end

-- OpenMap marks players from another realm with " (*)"; drop it.
local function StripLabel(name)
  name = Str(name)
  if not name then return end
  local label = Str(FOREIGN_SERVER_LABEL) or " (*)"
  if name:sub(-#label) == label then name = name:sub(1, -#label - 1) end
  return ns.NormalizeName(name)
end

local function IsKnown(name)
  return ns.Peers:FindPeer(name) ~= nil or ns.Peers:FindRosterUnit(name) ~= nil
end

---------------------------------------------------------------------------
-- One player: guild/friend dot or group dot. Same lines as the guild tooltip.
---------------------------------------------------------------------------
local function AddDot(tooltip, d)
  local p, r = d.p, type(d.roster) == "table" and d.roster or {}
  local name, class = FromGUID(p.guid or r.guid)
  name = name or Str(d.full)
  class = Str(p.class) or Str(r.class) or class
  local guild = p.guild == true or r.guild == true
  -- friends outside the guild: only if Queb knows them (party sync)
  if not name or (not guild and not IsKnown(name)) then return false end
  return ns.GuildUI:WriteLines(tooltip, name, class, true) -- a live dot = online
end

local function AddGroup(tooltip, unit)
  if not UnitExists(unit) then return false end
  local name = ns.UnitKey(unit)
  if not name then return false end
  local _, class = UnitClass(unit)
  local online = UnitIsConnected(unit)
  if ns.IsSecret(online) then online = nil else online = online and true or false end
  return ns.GuildUI:WriteLines(tooltip, name, Str(class), online)
end

---------------------------------------------------------------------------
-- Zone badge: only the people you share quests with, most shared first.
---------------------------------------------------------------------------
local function AddZone(tooltip, people)
  local rows = {}
  for _, r in ipairs(people) do
    if type(r) == "table" then
      local name, class = FromGUID(r.guid)
      name = name or StripLabel(r.name)
      class = Str(r.class) or class
      if name and not ns.IsMe(name) and (r.guild == true or IsKnown(name)) then
        local info = ns.Peers:SharedWith(name, true)
        local n = #info.shared
        local share = #ns.Peers:ShareableFrom(ns.Peers:FindPeer(name))
        if n > 0 or share > 0 then
          rows[#rows + 1] = { name = StripLabel(r.name) or name, class = class, n = n, share = share,
            exact = info.status == "addon" }
        end
      end
    end
  end
  if #rows == 0 then return false end
  table.sort(rows, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    if a.share ~= b.share then return a.share > b.share end
    return a.name < b.name
  end)
  tooltip:AddLine(" ")
  tooltip:AddLine(UI.Wrap(UI.GOLD, "Queb: shared quests"))
  for i = 1, math.min(#rows, ZONE_MAX) do
    local row = rows[i]
    local c = UI.ClassColor(row.class)
    local right = row.n > 0 and (tostring(row.n) .. (row.exact and "" or (" " .. UI.Wrap(UI.GRAY, "(no Queb)")))) or ""
    if row.share > 0 then right = right .. (right ~= "" and "  " or "") .. UI:ShareIcon(12) .. row.share end
    tooltip:AddDoubleLine(UI:CircleIcon(row.class, 10) .. " " .. row.name, right,
      c.r, c.g, c.b, UI.WHITE.r, UI.WHITE.g, UI.WHITE.b)
  end
  if #rows > ZONE_MAX then
    tooltip:AddLine(UI.Wrap(UI.GRAY, string.format("+%d more", #rows - ZONE_MAX)))
  end
  return true
end

-- Append our lines for an OpenMap marker. Returns true if anything was added.
function OM:AddLines(tooltip, owner, kind)
  if not ns.db or not ns.db.showOnMap then return false end
  kind = kind or self:KindOf(owner)
  local ok, added = pcall(function()
    if kind == "dot" then return AddDot(tooltip, owner.data) end
    if kind == "zone" then return AddZone(tooltip, owner.data.people) end
    if kind == "group" then return AddGroup(tooltip, owner.unit) end
  end)
  if not ok then
    ns.Debug("OpenMap tooltip error:", tostring(added))
    return false
  end
  if ns.db.debug and kind and not self.kinds[kind] then
    self.kinds[kind] = true
    ns.Debug("OpenMap marker:", kind, "lines", tostring(added))
  end
  return added and true or false
end

---------------------------------------------------------------------------
-- A switch in OpenMap's own menu (its public API), mirroring Settings.
---------------------------------------------------------------------------
ns.Listen("LOGIN", function()
  if not Available() or type(OpenMapAPI.RegisterMenuToggle) ~= "function" then return end
  local ok, err = pcall(OpenMapAPI.RegisterMenuToggle, "Queb", {
    id = "players",
    label = "Queb: shared quests",
    icon = UI.CIRCLE,
    get = function() return ns.db and ns.db.showOnMap end,
    set = function(v) ns.Options:Set("showOnMap", v and true or false) end,
  })
  OM.menuRegistered = ok
  if not ok then ns.Debug("OpenMap menu toggle failed:", tostring(err)) end
end)
