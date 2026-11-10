-- Mapcast: the map window
-- Decoupled Lane Studio - MIT License
--
-- Design notes
--  * Mapcast never touches WorldMapFrame. It builds a second MapCanvas instance
--    (exactly what Blizzard_BattlefieldMap does) and adds Blizzard's own data
--    providers to it, so quests, POIs, flight points, fog of war and the player /
--    party arrows come from the same code the M map uses.
--  * The canvas is view-only. Pin clicks are disabled because several Blizzard
--    pins open the quest log / world map when clicked, and doing that from addon
--    code would spread taint into the default UI.
--  * Quest pin hover normally fires a global EventRegistry event that makes the
--    quest log rebuild itself. Mapcast replaces that hover with a local tooltip
--    so the quest log is never driven from addon code.

local ADDON_NAME, ns = ...

local Map = {}
ns.Map = Map

local HEADER_HEIGHT = 20
local MIN_W, MIN_H = 160, 120
local MAX_W, MAX_H = 2000, 1400
local EXTRA_ZOOM_STEPS = { 1.5, 2, 3, 4 } -- multiples of the "fit" scale added when a map has no zoom levels

local STRATA_ORDER = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN" }

-- Data providers taken from WorldMapMixin:AddStandardDataProviders, minus the
-- ones that are tied to WorldMapFrame (event overlay, world-quest filters,
-- garrison/invasion/neighborhood, debug) or that add click actions.
local PROVIDERS = {
	"MapExplorationDataProviderMixin",
	"MapHighlightDataProviderMixin",
	"BattlefieldFlagDataProviderMixin",
	"BonusObjectiveDataProviderMixin",
	"VehicleDataProviderMixin",
	"FogOfWarDataProviderMixin",
	"DeathMapDataProviderMixin",
	"QuestBlobDataProviderMixin",
	"ScenarioDataProviderMixin",
	"VignetteDataProviderMixin",
	"QuestDataProviderMixin",
	"GossipDataProviderMixin",
	"FlightPointDataProviderMixin",
	"PetTamerDataProviderMixin",
	"DigSiteDataProviderMixin",
	"DungeonEntranceDataProviderMixin",
	"DelveEntranceDataProviderMixin",
	"MapLinkDataProviderMixin",
	"SelectableGraveyardDataProviderMixin",
	"AreaPOIDataProviderMixin",
	"AreaPOIEventDataProviderMixin",
	"QuestSessionDataProviderMixin",
	"EncounterJournalDataProviderMixin",
}

-- Same ordering as the world map so pins stack identically.
local FRAME_LEVELS = {
	"PIN_FRAME_LEVEL_MAP_EXPLORATION",
	"PIN_FRAME_LEVEL_EVENT_OVERLAY",
	"PIN_FRAME_LEVEL_FOG_OF_WAR",
	"PIN_FRAME_LEVEL_QUEST_BLOB",
	"PIN_FRAME_LEVEL_SCENARIO_BLOB",
	"PIN_FRAME_LEVEL_MAP_HIGHLIGHT",
	"PIN_FRAME_LEVEL_DIG_SITE",
	"PIN_FRAME_LEVEL_DUNGEON_ENTRANCE",
	"PIN_FRAME_LEVEL_DELVE_ENTRANCE",
	"PIN_FRAME_LEVEL_FLIGHT_POINT",
	"PIN_FRAME_LEVEL_INVASION",
	"PIN_FRAME_LEVEL_PET_TAMER",
	"PIN_FRAME_LEVEL_SELECTABLE_GRAVEYARD",
	"PIN_FRAME_LEVEL_AREA_POI",
	"PIN_FRAME_LEVEL_MAPCAST_MIRROR",
	"PIN_FRAME_LEVEL_GOSSIP",
	"PIN_FRAME_LEVEL_MAP_LINK",
	"PIN_FRAME_LEVEL_ENCOUNTER",
	{ "PIN_FRAME_LEVEL_VIGNETTE", 200 },
	"PIN_FRAME_LEVEL_SCENARIO",
	"PIN_FRAME_LEVEL_BONUS_OBJECTIVE",
	"PIN_FRAME_LEVEL_AREA_POI_EVENT",
	"PIN_FRAME_LEVEL_QUEST_PING",
	{ "PIN_FRAME_LEVEL_ACTIVE_QUEST", "MAXQUESTS" },
	"PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST",
	"PIN_FRAME_LEVEL_VEHICLE_BELOW_GROUP_MEMBER",
	"PIN_FRAME_LEVEL_BATTLEFIELD_FLAG",
	"PIN_FRAME_LEVEL_GROUP_MEMBER",
	"PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER",
	"PIN_FRAME_LEVEL_CORPSE",
}

local function noop() end

-- Capture layout (pixel exact, magenta border) is used in capture mode and
-- always in off-screen mode.
local function IsCapture()
	return ns.db.captureMode or ns.Offscreen:IsActive()
end
ns.IsCapture = IsCapture

---------------------------------------------------------------------------
-- Pin safety
---------------------------------------------------------------------------
local function SafeQuestPinEnter(pin)
	local questID = (pin.GetQuestID and pin:GetQuestID()) or pin.questID
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT", 5, 2)
	local title = questID and C_QuestLog.GetTitleForQuestID(questID)
	GameTooltip:SetText(title or QUESTS_LABEL or "Quest", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	local objectives = questID and C_QuestLog.GetQuestObjectives(questID)
	if objectives then
		for _, o in ipairs(objectives) do
			if o.text and o.text ~= "" then
				local c = o.finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR
				GameTooltip:AddLine("- " .. o.text, c.r, c.g, c.b, true)
			end
		end
	end
	if questID and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then
		GameTooltip:AddLine(COMPLETE or "Complete", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
	end
	GameTooltip:Show()
end

local function SafeQuestPinLeave()
	GameTooltip:Hide()
end

-- Runs once per newly created pin frame, before Blizzard wires its scripts.
local function MakePinViewOnly(pin)
	-- Blocked in combat for addon-owned frames; we never need passthrough because
	-- pins don't take clicks at all on this map.
	pin.SetPassThroughButtons = noop
	pin.CheckMouseButtonPassthrough = noop
	pin.OnClick = noop
	pin.OnMouseDown = noop
	pin.OnMouseUp = noop
	pin.OnMouseClickAction = noop
	-- Global "legend" highlight events would drive the M map's legend from addon code.
	pin.OnLegendPinMouseEnter = noop
	pin.OnLegendPinMouseLeave = noop
	if QuestPinMixin and pin.OnMouseEnter == QuestPinMixin.OnMouseEnter then
		pin.OnMouseEnter = SafeQuestPinEnter
		pin.OnMouseLeave = SafeQuestPinLeave
	end
end

local function OnPinReleased(pinPool, pin)
	local map = pin:GetMap()
	if map then
		map:UnregisterPin(pin)
	end
	Pool_HideAndClearAnchors(pinPool, pin)
	pin:OnReleased()
	pin.pinTemplate = nil
	pin:SetOwningMap(nil)
end

---------------------------------------------------------------------------
-- Canvas mixin (created at runtime once Blizzard_MapCanvas is loaded)
---------------------------------------------------------------------------
local CanvasOverrides = {}

function CanvasOverrides:OnLoad()
	MapCanvasMixin.OnLoad(self)
	self:MapcastSetup()
end

-- Idempotent; also called after creation in case the XML mixin order differs.
function CanvasOverrides:MapcastSetup()
	self:SetShouldZoomInOnClick(false)
	self:SetShouldPanOnClick(false)
	self:SetShouldNavigateOnClick(true) -- left click: open sub-zone, right click: go up
	self:SetShouldZoomInstantly(false)
	self:SetToplevel(false)
end

function CanvasOverrides:OnShow()
	local id = Map:GetPlayerMapID()
	if not self.mapID or (Map:IsFollowing() and id) then
		self.mcInternal = true
		self:SetMapID(id or Map:GetFallbackMapID())
		self.mcInternal = false
	end
	MapCanvasMixin.OnShow(self)
end

function CanvasOverrides:SetMapID(mapID)
	local previous = self.mapID
	MapCanvasMixin.SetMapID(self, mapID)
	if self.mapID ~= previous then
		Map:OnCanvasMapChanged(self.mapID, self.mcInternal)
	end
end

-- Copy of MapCanvasMixin:AcquirePin with Mapcast's view-only changes.
function CanvasOverrides:AcquirePin(pinTemplate, ...)
	if not self.pinPools[pinTemplate] then
		local pinTemplateType = self:GetPinTemplateType(pinTemplate)
		self.pinPools[pinTemplate] = CreateFramePool(pinTemplateType, self:GetCanvas(), pinTemplate, OnPinReleased)
	end

	local pin, newPin = self.pinPools[pinTemplate]:Acquire()
	pin.pinTemplate = pinTemplate
	pin:SetOwningMap(self)

	if newPin then
		MakePinViewOnly(pin)
		pin:SetScript("OnMouseUp", nil)
		pin:SetScript("OnMouseDown", nil)
		if pin:IsObjectType("Button") then
			pin:SetScript("OnClick", nil)
		end
		if pin:IsMouseMotionEnabled() then
			pin:SetScript("OnEnter", pin.OnMouseEnter)
			pin:SetScript("OnLeave", pin.OnMouseLeave)
		end
		pin:SetMouseClickEnabled(false)
		pin:OnLoad()
	end

	self.ScrollContainer:MarkCanvasDirty()
	pin:Show()
	pin:OnAcquired(...)
	if pin:IsMouseClickEnabled() then
		pin:SetMouseClickEnabled(false)
	end
	self:RegisterPin(pin)
	return pin
end

function CanvasOverrides:AddMapcastProviders()
	for _, name in ipairs(PROVIDERS) do
		local mixin = _G[name]
		if mixin then
			local ok, err = pcall(self.AddDataProvider, self, CreateFromMixins(mixin))
			if not ok then
				ns.Print("skipped " .. name .. ": " .. tostring(err))
			end
		end
	end

	if AreaLabelDataProviderMixin then
		local areaLabel = CreateFromMixins(AreaLabelDataProviderMixin)
		if areaLabel.SetOffsetY then areaLabel:SetOffsetY(-10) end
		self:AddDataProvider(areaLabel)
	end

	if GroupMembersDataProviderMixin then
		self.groupMembersDataProvider = CreateFromMixins(GroupMembersDataProviderMixin)
		self:AddDataProvider(self.groupMembersDataProvider)
	end

	local levels = self:GetPinFrameLevelsManager()
	for _, entry in ipairs(FRAME_LEVELS) do
		if type(entry) == "table" then
			local range = entry[2]
			if range == "MAXQUESTS" then
				range = (C_QuestLog.GetMaxNumQuests and C_QuestLog.GetMaxNumQuests()) or 35
			end
			levels:AddFrameLevel(entry[1], range)
		else
			levels:AddFrameLevel(entry)
		end
	end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function Map:GetPlayerMapID()
	if MapUtil and MapUtil.GetDisplayableMapForPlayer then
		local id = MapUtil.GetDisplayableMapForPlayer()
		if id then return id end
	end
	return C_Map.GetBestMapForUnit("player")
end

-- Used before the player's position is known (very early login, loading screens).
function Map:GetFallbackMapID()
	return (C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID()) or 947
end

local function OverlayStrata(strata)
	for i, s in ipairs(STRATA_ORDER) do
		if s == strata then
			return STRATA_ORDER[math.min(i + 1, #STRATA_ORDER)]
		end
	end
	return "HIGH"
end

-- UI units of `frame` that make up one physical screen pixel.
local function UnitsPerPixel(frame)
	local _, physH = GetPhysicalScreenSize()
	if not physH or physH == 0 then return 1 end
	return 768 / physH / frame:GetEffectiveScale()
end

local function MakeTextButton(parent, label, width, onClick, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, HEADER_HEIGHT - 4)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Text:SetPoint("CENTER")
	b.Text:SetText(label)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	b:SetScript("OnClick", onClick)
	if tooltip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function Map:Initialize()
	local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	for _, addon in ipairs({ "Blizzard_MapCanvas", "Blizzard_SharedMapDataProviders" }) do
		if not isLoaded(addon) then loader(addon) end
	end
	assert(MapCanvasMixin, "Blizzard_MapCanvas is not available on this client")

	-- Global because the XML template references it by name.
	MapcastCanvasMixin = CreateFromMixins(MapCanvasMixin, CanvasOverrides)
	ns.Mirror:CreateMixins()

	self:CreateFrames()
	ns.Offscreen:Initialize()
	self:ApplyLayout()
	self:SetShownSaved(ns.db.shown)
end

function Map:CreateFrames()
	local db = ns.db

	-- Container: holds chrome, border and the canvas.
	local f = CreateFrame("Frame", "MapcastFrame", UIParent, "BackdropTemplate")
	self.frame = f
	f:Hide() -- shown by SetShownSaved once the layout is applied
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetClampedToScreen(true)
	f:SetDontSavePosition(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	else
		f:SetMinResize(MIN_W, MIN_H); f:SetMaxResize(MAX_W, MAX_H)
	end
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropColor(0.031, 0.078, 0.125, 0.92)      -- brand navy #081420
	f:SetBackdropBorderColor(0.298, 0.827, 0.714, 0.6) -- brand teal #4CD3B6

	-- Canvas
	local canvas = CreateFrame("Frame", "MapcastMapCanvas", f, "MapcastCanvasTemplate")
	self.canvas = canvas
	Mixin(canvas, CanvasOverrides) -- make sure our overrides win whatever order XML applied mixins in
	canvas:MapcastSetup()
	canvas:AddMapcastProviders()
	ns.Mirror:Attach(canvas)
	canvas:SetScript("OnSizeChanged", function(c) c:OnFrameSizeChanged() end)
	canvas:SetGlobalPinScale(db.pinScale)
	canvas:Show()
	self:InstallZoomLevels(canvas.ScrollContainer)
	self:HookInteraction(canvas.ScrollContainer)

	-- Overlay layer (above pins): header, resize grip, capture border.
	local overlay = CreateFrame("Frame", nil, f)
	overlay:SetAllPoints()
	self.overlay = overlay

	local header = CreateFrame("Frame", nil, overlay)
	self.header = header
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(HEADER_HEIGHT)
	header:EnableMouse(true)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(0.055, 0.118, 0.180, 0.95) -- brand navy #0E1E2E
	header:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and not db.locked then f:StartMoving() end
	end)
	header:SetScript("OnMouseUp", function() Map:StopMoving() end)

	header.Title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	header.Title:SetPoint("LEFT", 6, 0)
	header.Title:SetJustifyH("LEFT")
	header.Title:SetWordWrap(false)

	header.Close = MakeTextButton(header, "x", 18, function() Map:SetShownSaved(false) end, "Hide (/mapcast to show)")
	header.Close:SetPoint("RIGHT", -2, 0)
	header.Lock = MakeTextButton(header, "Lock", 42, function() Mapcast_ToggleLock() end, "Lock position and size, and hide this bar until you hover the map")
	header.Lock:SetPoint("RIGHT", header.Close, "LEFT", -2, 0)
	header.Zones = MakeTextButton(header, "Zones", 40, function(b) Map:OpenBrowseMenu(b) end, "Browse other zones")
	header.Zones:SetPoint("RIGHT", header.Lock, "LEFT", -2, 0)
	header.Follow = MakeTextButton(header, "Follow", 44, function() Map:OnFollowClicked() end)
	header.Follow:SetPoint("RIGHT", header.Zones, "LEFT", -2, 0)
	header.Follow:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Auto-follow", 1, 1, 1)
		GameTooltip:AddLine("When on, the map switches to the zone you are in.", nil, nil, nil, true)
		GameTooltip:AddLine("Browsing pauses it; it resumes after a short delay or when you click here.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	header.Follow:SetScript("OnLeave", GameTooltip_Hide)
	header.Title:SetPoint("RIGHT", header.Follow, "LEFT", -4, 0)

	local grip = CreateFrame("Button", nil, overlay)
	self.grip = grip
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() if not db.locked and not IsCapture() then f:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function() Map:StopMoving() end)

	-- Capture-mode marker border: four solid textures, pixel exact.
	self.border = {}
	for i = 1, 4 do
		local t = overlay:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(ns.MARKER_R, ns.MARKER_G, ns.MARKER_B, 1)
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
		self.border[i] = t
	end

	-- Events and ticking
	f:SetScript("OnEvent", function(_, event) Map:OnEvent(event) end)
	for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK",
		"PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
		f:RegisterEvent(e)
	end
	local acc, slowAcc = 0, 0
	f:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		slowAcc = slowAcc + elapsed
		if acc >= 0.1 then
			acc = 0
			Map:FastTick()
		end
		if slowAcc >= 1 then
			slowAcc = 0
			Map:SlowTick()
		end
	end)
	f:SetScript("OnSizeChanged", function() Map:UpdateBorder() end)
end

-- Zone maps on some clients have a single zoom level; add a few more so the
-- mouse wheel always zooms. Only applies to Mapcast's own scroll container.
function Map:InstallZoomLevels(sc)
	local base = sc.CreateZoomLevels
	sc.CreateZoomLevels = function(container)
		base(container)
		local levels = container.zoomLevels
		if not levels or #levels == 0 or not container.baseScale then return end
		local layerIndex = levels[#levels].layerIndex
		for _, mult in ipairs(EXTRA_ZOOM_STEPS) do
			local scale = container.baseScale * mult
			if scale > levels[#levels].scale + 0.01 then
				table.insert(levels, { scale = scale, layerIndex = layerIndex })
			end
		end
	end
end

function Map:HookInteraction(sc)
	sc:HookScript("OnMouseDown", function(_, button)
		local x, y = GetCursorPosition()
		Map.downX, Map.downY = x, y
		if button == "LeftButton" and IsAltKeyDown() and not ns.db.locked then
			Map.altMoving = true
			Map.frame:StartMoving()
		end
	end)
	sc:HookScript("OnMouseUp", function(_, button)
		if Map.altMoving then
			Map.altMoving = false
			Map:StopMoving()
			return
		end
		if button == "LeftButton" and Map.downX then
			local x, y = GetCursorPosition()
			local dx, dy = x - Map.downX, y - Map.downY
			if dx * dx + dy * dy > 64 and sc:CanPan() then
				Map:PauseFollow() -- user dragged the map
			end
		end
		Map.downX = nil
	end)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function Map:SavePosition()
	local f = self.frame
	local s = f:GetScale()
	local left, bottom = f:GetLeft(), f:GetBottom()
	if left and bottom then
		ns.db.pos = { x = left * s, y = bottom * s }
	end
end

function Map:StopMoving()
	local f = self.frame
	f:StopMovingOrSizing()
	if ns.Offscreen:IsActive() then self:ApplyLayout() return end
	if not IsCapture() then
		ns.db.width, ns.db.height = f:GetSize()
	end
	self:SavePosition()
	self:ApplyLayout()
end

function Map:ApplyPosition()
	local f, db = self.frame, ns.db
	local s = f:GetScale()
	f:ClearAllPoints()
	if ns.Offscreen:IsActive() then
		-- Inside the hidden strip, pixel aligned, centred vertically, 8 px from the left.
		local px = ns.Offscreen:Geometry() or 0
		local upp = UnitsPerPixel(f)
		local h = math.floor(f:GetHeight() / upp + 0.5)
		local gap = math.max(0, math.floor((px - h) / 2))
		if ns.db.offscreenEdge == "TOP" then
			f:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", 8 * upp, gap * upp)
		else
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 8 * upp, -gap * upp)
		end
	elseif db.pos then
		local x, y = db.pos.x / s, db.pos.y / s
		if db.captureMode then
			local upp = UnitsPerPixel(f)
			x = math.floor(x / upp + 0.5) * upp
			y = math.floor(y / upp + 0.5) * upp
		end
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
	else
		-- Default: tucked into the bottom-right corner, above the action bars.
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40 / s, 220 / s)
	end
end

function Map:ApplyLayout()
	local f, db, canvas = self.frame, ns.db, self.canvas
	if not f then return end

	-- Off-screen: no parent, so hiding the UI (Alt+Z) or UIParent's scale don't affect it.
	local wantParent = ns.Offscreen:IsActive() and nil or UIParent
	if f:GetParent() ~= wantParent then f:SetParent(wantParent) end

	local strata = db.strata or "MEDIUM"
	f:SetFrameStrata(strata)
	canvas:SetFrameStrata(strata)
	self.overlay:SetFrameStrata(OverlayStrata(strata))
	f:SetAlpha(db.alpha)

	canvas:ClearAllPoints()
	self.headerHover = nil
	if IsCapture() then
		f:SetScale(1)
		local upp = UnitsPerPixel(f)
		local b = db.captureBorder
		f:SetSize((db.captureWidth + 2 * b) * upp, (db.captureHeight + 2 * b) * upp)
		canvas:SetPoint("TOPLEFT", b * upp, -b * upp)
		canvas:SetPoint("BOTTOMRIGHT", -b * upp, b * upp)
		f:SetBackdropColor(0, 0, 0, 1)
		f:SetBackdropBorderColor(0, 0, 0, 0)
		self.header:Hide()
		self.grip:Hide()
		for _, t in ipairs(self.border) do t:Show() end
	else
		f:SetScale(db.scale)
		f:SetSize(db.width, db.height)
		f:SetBackdropColor(0.031, 0.078, 0.125, 0.92)
		f:SetBackdropBorderColor(0.298, 0.827, 0.714, db.locked and 0.25 or 0.6)
		local top = db.locked and 1 or (HEADER_HEIGHT + 1)
		canvas:SetPoint("TOPLEFT", 1, -top)
		canvas:SetPoint("BOTTOMRIGHT", -1, 1)
		self.header:SetShown(not db.locked)
		self.header:SetAlpha(1)
		self.grip:SetShown(not db.locked)
		for _, t in ipairs(self.border) do t:Hide() end
	end
	self:ApplyPosition()
	self:UpdateBorder()
	self:UpdateButtons()
end

function Map:UpdateBorder()
	if not IsCapture() then return end
	local f = self.frame
	local upp = UnitsPerPixel(f)
	local b = ns.db.captureBorder * upp
	local top, right, bottom, left = unpack(self.border)
	top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(b)
	bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(b)
	left:ClearAllPoints(); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(b)
	right:ClearAllPoints(); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(b)
end

function Map:ResetLayout()
	local db, d = ns.db, ns.DEFAULTS
	db.pos = nil
	db.width, db.height, db.scale, db.alpha = d.width, d.height, d.scale, d.alpha
	self:ApplyLayout()
end

---------------------------------------------------------------------------
-- State setters (used by slash commands, bindings and options)
---------------------------------------------------------------------------
function Map:IsShownSaved() return ns.db.shown end

function Map:SetShownSaved(shown)
	ns.db.shown = shown and true or false
	if self.frame then
		self.frame:SetShown(ns.db.shown)
		if ns.db.shown and self:IsFollowing() then self:SyncToPlayer() end
	end
end

function Map:SetLocked(locked)
	ns.db.locked = locked and true or false
	self:ApplyLayout()
	if ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end

function Map:SetCaptureMode(on)
	ns.db.captureMode = on and true or false
	self:ApplyLayout()
	if on then
		ns.Print(("capture mode on (%dx%d px, magenta border). Alt+drag to move while unlocked. /mapcast capture to exit.")
			:format(ns.db.captureWidth, ns.db.captureHeight))
	else
		ns.Print("capture mode off.")
	end
	if ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end

function Map:SetFollow(on)
	ns.db.follow = on and true or false
	self.followPausedAt = nil
	if on then self:SyncToPlayer() end
	self:UpdateButtons()
	if ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end

function Map:IsFollowing()
	return ns.db.follow and not self.followPausedAt
end

function Map:PauseFollow()
	if ns.db.follow then
		self.followPausedAt = GetTime()
		self:UpdateButtons()
	end
end

function Map:OnFollowClicked()
	if self:IsFollowing() then
		self:SetFollow(false)
	else
		self:SetFollow(true)
	end
end

function Map:BrowseTo(mapID)
	if mapID then self.canvas:SetMapID(mapID) end
end

function Map:SyncToPlayer()
	local id = self:GetPlayerMapID()
	if id and id ~= self.canvas:GetMapID() then
		self.canvas.mcInternal = true
		self.canvas:SetMapID(id)
		self.canvas.mcInternal = false
	end
end

function Map:OnCanvasMapChanged(mapID, internal)
	if not internal then
		self:PauseFollow()
	end
	self:UpdateTitle()
	self:UpdateButtons()
end

function Map:UpdateTitle()
	if not self.header then return end
	local info = self.canvas.mapID and C_Map.GetMapInfo(self.canvas.mapID)
	self.header.Title:SetText(info and info.name or "Mapcast")
end

function Map:UpdateButtons()
	local h = self.header
	if not h then return end
	if self:IsFollowing() then
		h.Follow.Text:SetText("|cff4cd3b6Follow|r")
	elseif ns.db.follow then
		h.Follow.Text:SetText("|cffe0904fPaused|r")
	else
		h.Follow.Text:SetText("|cff808080Follow|r")
	end
	h.Lock.Text:SetText(ns.db.locked and "Unlock" or "Lock")
end

---------------------------------------------------------------------------
-- Browse menu
---------------------------------------------------------------------------
local BROWSABLE = {}
if Enum and Enum.UIMapType then
	BROWSABLE[Enum.UIMapType.Continent] = true
	BROWSABLE[Enum.UIMapType.Zone] = true
	BROWSABLE[Enum.UIMapType.Dungeon] = true
end

local function SortedChildren(mapID)
	local out = {}
	for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, nil, false) or {}) do
		if BROWSABLE[child.mapType] then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function TopMapID(mapID)
	local info = C_Map.GetMapInfo(mapID)
	while info and info.parentMapID and info.parentMapID > 0 do
		local parent = C_Map.GetMapInfo(info.parentMapID)
		if not parent then break end
		info = parent
	end
	return info and info.mapID
end

function Map:OpenBrowseMenu(owner)
	local current = self.canvas:GetMapID()
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- Fallback: just go up one level.
		local info = current and C_Map.GetMapInfo(current)
		if info and info.parentMapID and info.parentMapID > 0 then self:BrowseTo(info.parentMapID) end
		return
	end

	MenuUtil.CreateContextMenu(owner, function(_, root)
		if root.SetScrollMode then root:SetScrollMode(420) end
		root:CreateButton("|cff4cd3b6My location|r", function() Map:SetFollow(true) end)

		local info = current and C_Map.GetMapInfo(current)
		if info and info.parentMapID and info.parentMapID > 0 then
			local parent = C_Map.GetMapInfo(info.parentMapID)
			if parent then
				root:CreateButton("Up: " .. parent.name, function() Map:BrowseTo(parent.mapID) end)
			end
		end

		local top = current and TopMapID(current)
		if top then
			local continents = root:CreateButton("Continents")
			for _, c in ipairs(C_Map.GetMapChildrenInfo(top, Enum.UIMapType.Continent, false) or {}) do
				continents:CreateButton(c.name, function() Map:BrowseTo(c.mapID) end)
			end
		end

		local list = current and SortedChildren(current) or {}
		local label = "In this map"
		if #list == 0 and info and info.parentMapID and info.parentMapID > 0 then
			list = SortedChildren(info.parentMapID)
			label = "Nearby"
		end
		if #list > 0 then
			root:CreateDivider()
			root:CreateTitle(label)
			for _, child in ipairs(list) do
				root:CreateButton(child.name, function() Map:BrowseTo(child.mapID) end)
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Events and ticks
---------------------------------------------------------------------------
function Map:OnEvent(event)
	if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		if ns.Offscreen:IsActive() then ns.Offscreen:Apply() end
		self:ApplyLayout()
		return
	end
	if self:IsFollowing() then
		self:SyncToPlayer()
	end
end

function Map:CenterOnPlayer()
	local sc = self.canvas.ScrollContainer
	if self.downX or not sc:CanPan() or sc:IsPanning() then return end
	local mapID = self.canvas:GetMapID()
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if not x or (x == 0 and y == 0) then return end
	local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(sc:GetCanvasScale())
	sc:SetPanTarget(Clamp(x, minX, maxX), Clamp(y, minY, maxY))
end

function Map:FastTick()
	local f, db = self.frame, ns.db
	if not f:IsVisible() then return end

	-- Locked: show the header as an overlay only while hovering.
	if db.locked and not IsCapture() then
		local over = f:IsMouseOver()
		if over ~= self.headerHover then
			self.headerHover = over
			self.header:SetShown(over)
		end
	end

	if self:IsFollowing() and db.centerOnPlayer then
		self:CenterOnPlayer()
	end
end

function Map:SlowTick()
	local f, db = self.frame, ns.db
	ns.Offscreen:Check()
	if not f:IsVisible() then return end
	if self.followPausedAt and db.autoResume > 0 and not f:IsMouseOver()
		and GetTime() - self.followPausedAt >= db.autoResume then
		self.followPausedAt = nil
		self:SyncToPlayer()
		self:UpdateButtons()
	end
	if self:IsFollowing() then
		self:SyncToPlayer() -- safety net for transitions that fire no zone event
	end
	ns.Mirror:Tick()
end
