-- Mapcast: third-party pin mirror
-- Decoupled Lane Studio - MIT License
--
-- Most map-pin addons (Questie, TomTom, HandyNotes, GatherMate2, ...) use the
-- HereBeDragons-Pins library. HBD keeps ONE real icon frame per pin and moves it
-- into a WorldMapFrame pin, so those frames can't also live on Mapcast's canvas.
--
-- Instead, Mapcast reads HBD's pin registry (read-only), places pins with the same
-- rules HBD uses, and draws visual copies of each icon's textures. Hovering a copy
-- runs the original icon's OnEnter so the owning addon's tooltip still appears.

local ADDON_NAME, ns = ...

local Mirror = {}
ns.Mirror = Mirror

local TEMPLATE = "MapcastMirrorPinTemplate"
local WORLD_MAP_ID = 947 -- HBD's "Azeroth" world map
local SHOW_PARENT, SHOW_CONTINENT, SHOW_WORLD = 1, 2, 3 -- HBD_PINS_WORLDMAP_SHOW_*
local MIN_REFRESH_INTERVAL = 1.0

local libs = {}   -- { pins = lib, hbd = coreLib, name = string }
local hooked = {}

---------------------------------------------------------------------------
-- Library discovery
---------------------------------------------------------------------------
function Mirror:DiscoverLibs()
	if not LibStub or not LibStub.IterateLibraries then return end
	for name, lib in LibStub:IterateLibraries() do
		if type(name) == "string" and name:match("^HereBeDragons.*%-Pins%-2%.0$")
			and type(lib) == "table" and type(lib.worldmapPins) == "table" and not hooked[lib] then
			local core = LibStub(name:gsub("%-Pins", ""), true)
			if core and core.mapData then
				hooked[lib] = true
				table.insert(libs, { pins = lib, hbd = core, name = name })
				for _, method in ipairs({ "AddWorldMapIconWorld", "AddWorldMapIconMap", "RemoveWorldMapIcon", "RemoveAllWorldMapIcons" }) do
					if type(lib[method]) == "function" then
						hooksecurefunc(lib, method, function() Mirror:MarkDirty() end)
					end
				end
				self:MarkDirty()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Placement (mirrors HereBeDragons-Pins worldmapProvider:HandlePin)
---------------------------------------------------------------------------
local function IsZoneLike(mapType)
	return mapType == Enum.UIMapType.Zone or mapType == Enum.UIMapType.Dungeon or mapType == Enum.UIMapType.Micro
end

local function PlacePin(entry, data, uiMapID)
	local hbd = entry.hbd
	local flag = data.worldMapShowFlag or 0

	if uiMapID == WORLD_MAP_ID then
		if uiMapID ~= data.uiMapID and flag ~= SHOW_WORLD then return end
		if not hbd.GetAzerothWorldMapCoordinatesFromWorld then return end
		return hbd:GetAzerothWorldMapCoordinatesFromWorld(data.x, data.y, data.instanceID)
	end

	local mapData = hbd.mapData[uiMapID]
	if not mapData then return end

	if uiMapID ~= data.uiMapID then
		local mapType = mapData.mapType
		if not data.uiMapID then
			if not (mapType == Enum.UIMapType.Continent and flag >= SHOW_CONTINENT) and not IsZoneLike(mapType) then
				return
			end
		else
			local show = false
			local parentID = hbd.mapData[data.uiMapID] and hbd.mapData[data.uiMapID].parent
			while parentID and hbd.mapData[parentID] do
				if parentID == uiMapID then
					local parentType = hbd.mapData[parentID].mapType
					if flag >= SHOW_PARENT and IsZoneLike(parentType) then
						show = true
					elseif flag >= SHOW_CONTINENT and parentType == Enum.UIMapType.Continent then
						show = true
					end
					break
				end
				parentID = hbd.mapData[parentID].parent
			end
			if not show then return end
		end
	end

	return hbd:GetZoneCoordinatesFromWorldInstance(data.x, data.y, data.instanceID, uiMapID)
end

-- Questie's copy of HBD has an extra "hide icons on continents" option.
local function QuestieHidesHere(entry, uiMapID)
	if not entry.name:find("Questie") then return false end
	local q = _G.Questie
	local hide = q and q.db and q.db.profile and q.db.profile.hideIconsOnContinents
	if not hide then return false end
	local md = entry.hbd.mapData[uiMapID]
	return (md and md.mapType == Enum.UIMapType.Continent) or uiMapID == WORLD_MAP_ID
end

---------------------------------------------------------------------------
-- Pin + provider
---------------------------------------------------------------------------
function Mirror:CreateMixins()
	local PinMixin = CreateFromMixins(MapCanvasPinMixin)
	MapcastMirrorPinMixin = PinMixin -- global: referenced by the XML template

	function PinMixin:OnLoad()
		self:UseFrameLevelType("PIN_FRAME_LEVEL_MAPCAST_MIRROR")
		self:SetScalingLimits(1, 1.0, 1.2)
		self.holder = CreateFrame("Frame", nil, self)
		self.holder:SetPoint("CENTER")
		self.textures = {}
	end

	function PinMixin:OnAcquired(icon, x, y)
		self.source = icon
		self:SetPosition(x, y)
		local w, h = icon:GetSize()
		if not w or w <= 0 then w, h = 16, 16 end
		local s = icon:GetScale() or 1
		self:SetSize(w * s, h * s)
		self.holder:SetSize(w, h)
		self.holder:SetScale(s)
		self:CopyVisuals(icon)
	end

	function PinMixin:OnReleased()
		self:RestoreBorrowed()
		self.source = nil
		for _, t in ipairs(self.textures) do t:Hide() end
	end

	function PinMixin:CopyVisuals(icon)
		local n = 0
		local holder = self.holder
		for _, region in ipairs({ icon:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region:IsShown() then
				n = n + 1
				local t = self.textures[n]
				if not t then
					t = holder:CreateTexture()
					self.textures[n] = t
				end
				local layer, sub = region:GetDrawLayer()
				t:SetDrawLayer(layer or "ARTWORK", sub or 0)
				local atlas = region.GetAtlas and region:GetAtlas()
				if atlas then
					t:SetAtlas(atlas)
				else
					t:SetTexture(region:GetTexture())
					t:SetTexCoord(region:GetTexCoord())
				end
				t:SetVertexColor(region:GetVertexColor())
				if region.IsDesaturated then t:SetDesaturated(region:IsDesaturated()) end
				t:SetBlendMode(region:GetBlendMode())
				t:SetAlpha(region:GetAlpha())
				t:ClearAllPoints()
				local anchored = false
				for i = 1, region:GetNumPoints() do
					local point, relTo, relPoint, ox, oy = region:GetPoint(i)
					if relTo == nil or relTo == icon then
						t:SetPoint(point, holder, relPoint, ox, oy)
						anchored = true
					end
				end
				if not anchored then
					t:SetAllPoints(holder)
				elseif region:GetNumPoints() == 1 then
					t:SetSize(region:GetSize())
				end
				t:Show()
			end
		end
		for i = n + 1, #self.textures do self.textures[i]:Hide() end
		self:SetAlpha(icon:GetAlpha() > 0 and 1 or 0)
	end

	-- To show the owning addon's tooltip we briefly park its (hidden) icon on our
	-- pin, invisible, so tooltip code that anchors to the icon has a real frame.
	function PinMixin:OnMouseEnter()
		local src = self.source
		if not src then return end
		local onEnter = src:GetScript("OnEnter")
		if not onEnter then return end
		if not src:IsVisible() then
			self.borrowed = { parent = src:GetParent(), alpha = src:GetAlpha(), mouse = src:IsMouseEnabled() }
			src:EnableMouse(false) -- otherwise it steals focus from our pin and the hover flickers
			src:SetParent(self)
			src:ClearAllPoints()
			src:SetPoint("CENTER", self, "CENTER")
			src:SetAlpha(0)
			src:Show()
		end
		pcall(onEnter, src)
		if GameTooltip:IsOwned(src) then
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 4, 4)
		end
	end

	function PinMixin:OnMouseLeave()
		local src = self.source
		local onLeave = src and src:GetScript("OnLeave")
		if onLeave then pcall(onLeave, src) end
		if src and GameTooltip:IsOwned(src) then GameTooltip:Hide() end
		self:RestoreBorrowed()
	end

	function PinMixin:RestoreBorrowed()
		local b, src = self.borrowed, self.source
		if not b or not src then self.borrowed = nil return end
		self.borrowed = nil
		if src:GetParent() == self then -- still ours (HBD didn't reclaim it meanwhile)
			src:Hide()
			src:EnableMouse(b.mouse and true or false)
			src:SetAlpha(b.alpha or 1)
			src:SetParent(b.parent or UIParent)
			src:ClearAllPoints()
		end
	end

	local provider = CreateFromMixins(MapCanvasDataProviderMixin)
	self.provider = provider

	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
	end

	function provider:RefreshAllData()
		self:RemoveAllData()
		Mirror.lastRefresh = GetTime()
		Mirror.dirty = false
		if not ns.db.mirrorPins then return end
		local map = self:GetMap()
		local uiMapID = map:GetMapID()
		if not uiMapID then return end
		-- Diagnostics: kept small and saved to MapcastDB.debug (see /mapcast debug).
		local stats = { mapID = uiMapID, time = date("%H:%M:%S"), libs = {} }
		Mirror.stats = stats
		for _, entry in ipairs(libs) do
			local s = { name = entry.name, registered = 0, hidden = 0, notHere = 0, placed = 0 }
			table.insert(stats.libs, s)
			if QuestieHidesHere(entry, uiMapID) then
				s.questieHidesOnContinents = true
			else
				for icon, data in pairs(entry.pins.worldmapPins) do
					s.registered = s.registered + 1
					if icon.hidden then
						s.hidden = s.hidden + 1
					elseif data.x and data.y then
						local ok, x, y = pcall(PlacePin, entry, data, uiMapID)
						if not ok then
							s.placeError = s.placeError or tostring(x)
						elseif x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
							local aok, err = pcall(map.AcquirePin, map, TEMPLATE, icon, x, y)
							if aok then
								s.placed = s.placed + 1
							else
								s.acquireError = s.acquireError or tostring(err)
							end
						else
							s.notHere = s.notHere + 1
						end
					end
				end
			end
		end
		ns.db.debug = stats
	end

	function provider:OnMapChanged()
		self:RefreshAllData()
	end
end

function Mirror:PrintDebug()
	local libNames = {}
	for _, e in ipairs(libs) do table.insert(libNames, e.name) end
	ns.Print("pin libraries found: " .. (#libNames > 0 and table.concat(libNames, ", ") or "none"))
	local s = self.stats
	if not s then
		ns.Print("the mirror hasn't refreshed yet.")
		return
	end
	ns.Print(("last refresh %s on map %s:"):format(s.time, tostring(s.mapID)))
	for _, l in ipairs(s.libs) do
		ns.Print(("  %s: %d registered, %d hidden, %d not on this map, %d drawn%s%s"):format(l.name, l.registered,
			l.hidden, l.notHere, l.placed,
			l.placeError and (" |cffff5555place error: " .. l.placeError .. "|r") or "",
			l.acquireError and (" |cffff5555draw error: " .. l.acquireError .. "|r") or ""))
	end
end

function Mirror:Attach(canvas)
	self:DiscoverLibs()
	canvas:AddDataProvider(self.provider)
end

function Mirror:MarkDirty()
	self.dirty = true
end

function Mirror:Refresh()
	local map = self.provider and self.provider:GetMap()
	if map and map:IsVisible() then
		self.provider:RefreshAllData()
	end
end

-- Called once a second by Map.lua.
function Mirror:Tick()
	self.discoverAcc = (self.discoverAcc or 0) + 1
	if self.discoverAcc >= 10 then -- pick up libraries from late-loading addons
		self.discoverAcc = 0
		self:DiscoverLibs()
	end
	if self.dirty and GetTime() - (self.lastRefresh or 0) >= MIN_REFRESH_INTERVAL then
		self:Refresh()
	end
end
