-- Mapcast: first-run popup and options panel
-- Decoupled Lane Studio - MIT License

local ADDON_NAME, ns = ...

local UI = {}
ns.UI = UI

local COMPANION_TEXT =
	"World of Warcraft addons can't open a separate window, so Mapcast draws its map inside the game.\n\n" ..
	"To show it on a second monitor, run the free |cff4cd3b6Mapcast Companion|r app for Windows. " ..
	"It mirrors the Mapcast frame into its own window that you can drag anywhere. " ..
	"It only captures the screen. It never reads game memory or sends input.\n\n" ..
	"Download it from the Releases page (click the box, then press |cffffd100Ctrl+C|r to copy):"

-- A read-only, auto-selecting edit box holding the Releases URL.
local function CreateURLBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetText(ns.RELEASES_URL)
	box:SetCursorPosition(0)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then self:SetText(ns.RELEASES_URL); self:HighlightText() end
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnKeyDown", function(self, key)
		if key == "C" and IsControlKeyDown() then
			C_Timer.After(0, function()
				ns.Print("link copied. Paste it into your browser.")
				self:ClearFocus()
			end)
		end
	end)
	return box
end

---------------------------------------------------------------------------
-- First-run popup
---------------------------------------------------------------------------
function UI:CreatePopup()
	local p = CreateFrame("Frame", "MapcastCompanionPopup", UIParent, "BackdropTemplate")
	p:SetSize(440, 300)
	p:SetPoint("CENTER", 0, 80)
	p:SetFrameStrata("DIALOG")
	p:SetMovable(true)
	p:EnableMouse(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)
	p:SetClampedToScreen(true)
	p:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 2,
	})
	p:SetBackdropColor(0.031, 0.078, 0.125, 0.97)
	p:SetBackdropBorderColor(0.298, 0.827, 0.714, 1)
	p:Hide()

	local icon = p:CreateTexture(nil, "ARTWORK")
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 16, -14)
	icon:SetTexture("Interface\\AddOns\\Mapcast\\Media\\Mapcast")

	local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	title:SetText("Mapcast on a second monitor")

	local body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", 18, -66)
	body:SetPoint("RIGHT", -18, 0)
	body:SetJustifyH("LEFT")
	body:SetSpacing(2)
	body:SetText(COMPANION_TEXT)

	local box = CreateURLBox(p, 396)
	box:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 6, -10)
	p.URLBox = box

	local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("BOTTOMLEFT", 14, 12)
	check.Text:SetText("Don't show again")
	check:SetChecked(true)
	p.DontShow = check

	local ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	ok:SetSize(96, 24)
	ok:SetPoint("BOTTOMRIGHT", -14, 14)
	ok:SetText(OKAY or "OK")
	ok:SetScript("OnClick", function() p:Hide() end)

	p:SetScript("OnHide", function()
		ns.db.popupDismissed = check:GetChecked() and true or false
	end)

	self.popup = p
end

-- fromCommand: opened by /mapcast companion (don't touch the saved choice).
function UI:ShowCompanionPopup(fromCommand)
	if not self.popup then self:CreatePopup() end
	-- First run: pre-ticked, so closing it once means "shown once". Untick to see it again next login.
	local checked = true
	if fromCommand then checked = ns.db.popupDismissed and true or false end
	self.popup.DontShow:SetChecked(checked)
	self.popup.URLBox:SetText(ns.RELEASES_URL)
	self.popup:Show()
end

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------
local widgets = {}

local function Checkbox(panel, label, tooltip, get, set)
	local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	c:SetSize(26, 26)
	c.Text:SetText(label)
	c.Text:SetFontObject(GameFontHighlight)
	c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	if tooltip then
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", GameTooltip_Hide)
	end
	c.Refresh = function(self) self:SetChecked(get()) end
	table.insert(widgets, c)
	return c
end

local function Slider(panel, label, minV, maxV, step, fmt, get, set)
	local s = CreateFrame("Slider", nil, panel, "UISliderTemplateWithLabels")
	s:SetWidth(220)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.Low:SetText(fmt(minV))
	s.High:SetText(fmt(maxV))
	local function UpdateLabel(v) s.Text:SetText(label .. ": |cffffffff" .. fmt(v) .. "|r") end
	s:SetScript("OnValueChanged", function(self, v, userInput)
		v = math.floor(v / step + 0.5) * step
		UpdateLabel(v)
		if userInput then set(v) end
	end)
	s.Refresh = function(self)
		local v = get()
		self:SetValue(v)
		UpdateLabel(v)
	end
	table.insert(widgets, s)
	return s
end

local function Button(panel, label, width, onClick)
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Header(panel, text)
	local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetText(text)
	return h
end

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }
local STRATA_LABEL = { BACKGROUND = "Behind everything", LOW = "Low", MEDIUM = "Normal", HIGH = "Above most UI" }

function UI:CreateOptions()
	local db = ns.db
	local Map = ns.Map
	local panel = CreateFrame("Frame")
	panel.name = "Mapcast"
	self.panel = panel

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Mapcast")
	local ver = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)
	ver:SetText("v" .. ns.VERSION .. "  -  Decoupled Lane Studio  -  MIT")

	-- Companion info (same text and URL constant as the popup)
	local comp = Header(panel, "Second monitor")
	comp:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -18)
	local compText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	compText:SetPoint("TOPLEFT", comp, "BOTTOMLEFT", 0, -6)
	compText:SetWidth(600)
	compText:SetJustifyH("LEFT")
	compText:SetText(COMPANION_TEXT)
	local url = CreateURLBox(panel, 380)
	url:SetPoint("TOPLEFT", compText, "BOTTOMLEFT", 6, -8)
	panel.URLBox = url

	-- Left column: behaviour
	local beh = Header(panel, "Map")
	beh:SetPoint("TOPLEFT", url, "BOTTOMLEFT", -6, -22)

	local cShow = Checkbox(panel, "Show Mapcast", nil, function() return db.shown end, function(v) Map:SetShownSaved(v) end)
	cShow:SetPoint("TOPLEFT", beh, "BOTTOMLEFT", -4, -6)
	local cLock = Checkbox(panel, "Lock position and size",
		"Hides the title bar and resize grip. Hover the map to bring the title bar back.",
		function() return db.locked end, function(v) Map:SetLocked(v) end)
	cLock:SetPoint("TOPLEFT", cShow, "BOTTOMLEFT", 0, -2)
	local cFollow = Checkbox(panel, "Auto-follow my zone",
		"Switch to the zone you are in. Browsing another zone pauses this until the auto-resume delay passes.",
		function() return db.follow end, function(v) Map:SetFollow(v) end)
	cFollow:SetPoint("TOPLEFT", cLock, "BOTTOMLEFT", 0, -2)
	local cCenter = Checkbox(panel, "Keep my arrow centred when zoomed in", nil,
		function() return db.centerOnPlayer end, function(v) db.centerOnPlayer = v end)
	cCenter:SetPoint("TOPLEFT", cFollow, "BOTTOMLEFT", 0, -2)
	local cMirror = Checkbox(panel, "Show pins from other addons",
		"Copies pins from addons that use HereBeDragons (Questie, TomTom, HandyNotes, GatherMate2 and others).",
		function() return db.mirrorPins end, function(v) db.mirrorPins = v; ns.Mirror:Refresh() end)
	cMirror:SetPoint("TOPLEFT", cCenter, "BOTTOMLEFT", 0, -2)

	local strataBtn = Button(panel, "", 200, function(self)
		local idx = 1
		for i, s in ipairs(STRATA) do if s == db.strata then idx = i end end
		db.strata = STRATA[idx % #STRATA + 1]
		Map:ApplyLayout()
		self:Refresh()
	end)
	strataBtn:SetPoint("TOPLEFT", cMirror, "BOTTOMLEFT", 4, -8)
	strataBtn.Refresh = function(self) self:SetText("Layer: " .. (STRATA_LABEL[db.strata] or db.strata)) end
	table.insert(widgets, strataBtn)

	local reset = Button(panel, "Reset position and size", 200, function() Map:ResetLayout(); UI:RefreshOptions() end)
	reset:SetPoint("TOPLEFT", strataBtn, "BOTTOMLEFT", 0, -6)

	-- Right column: appearance and capture
	local look = Header(panel, "Appearance")
	look:SetPoint("TOPLEFT", beh, "TOPLEFT", 330, 0)
	local pct = function(v) return math.floor(v * 100 + 0.5) .. "%" end
	local sAlpha = Slider(panel, "Opacity", 0.2, 1, 0.05, pct,
		function() return db.alpha end, function(v) db.alpha = v; Map:ApplyLayout() end)
	sAlpha:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 4, -20)
	local sScale = Slider(panel, "Scale", 0.5, 2, 0.05, pct,
		function() return db.scale end, function(v) db.scale = v; Map:ApplyLayout() end)
	sScale:SetPoint("TOPLEFT", sAlpha, "BOTTOMLEFT", 0, -30)
	local sPins = Slider(panel, "Pin size", 0.5, 2, 0.05, pct,
		function() return db.pinScale end, function(v) db.pinScale = v; Map.canvas:SetGlobalPinScale(v) end)
	sPins:SetPoint("TOPLEFT", sScale, "BOTTOMLEFT", 0, -30)
	local sResume = Slider(panel, "Auto-resume follow", 0, 120, 5,
		function(v) return v == 0 and "never" or (v .. "s") end,
		function() return db.autoResume end, function(v) db.autoResume = v end)
	sResume:SetPoint("TOPLEFT", sPins, "BOTTOMLEFT", 0, -30)

	local cap = Header(panel, "Capture mode (for Mapcast Companion)")
	cap:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", -4, -24)
	local capText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	capText:SetPoint("TOPLEFT", cap, "BOTTOMLEFT", 0, -6)
	capText:SetWidth(600)
	capText:SetJustifyH("LEFT")
	capText:SetText("Capture mode draws a clean, fixed-size map with a solid magenta border that the companion detects automatically. " ..
		"Size is in real screen pixels. Smaller sizes take less room in game but look softer on the second monitor. " ..
		"Opacity also affects what the companion sees. Alt+drag the map to move it while unlocked.")
	local cCapture = Checkbox(panel, "Capture mode", nil,
		function() return db.captureMode end, function(v) Map:SetCaptureMode(v) end)
	cCapture:SetPoint("TOPLEFT", capText, "BOTTOMLEFT", -4, -6)
	local px = function(v) return v .. " px" end
	local sCapW = Slider(panel, "Width", 200, 1600, 20, px,
		function() return db.captureWidth end, function(v) db.captureWidth = v; Map:ApplyLayout() end)
	sCapW:SetPoint("TOPLEFT", cCapture, "BOTTOMLEFT", 8, -22)
	local sCapH = Slider(panel, "Height", 150, 1200, 20, px,
		function() return db.captureHeight end, function(v) db.captureHeight = v; Map:ApplyLayout() end)
	sCapH:SetPoint("LEFT", sCapW, "RIGHT", 60, 0)

	local cOff = Checkbox(panel, "Off-screen mode",
		"Puts the map in a strip of the game window that no monitor shows. First use Mapcast Companion: " ..
		"right-click > Off-screen map > Hide the map off-screen. It tells you the exact command, for example /mapcast offscreen top 600.",
		function() return db.offscreenEdge ~= nil end,
		function(v) ns.Offscreen:SetMode(v and (db.offscreenLastEdge or "TOP") or nil) end)
	cOff:SetPoint("TOPLEFT", sCapW, "BOTTOMLEFT", -8, -26)
	local offText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	offText:SetPoint("LEFT", cOff.Text or cOff, "RIGHT", 8, 0)
	offText:SetText("Hides the map completely. Needs the companion's \"Off-screen map\" option; hover for details.")

	panel:SetScript("OnShow", function() UI:RefreshOptions() end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Mapcast")
		Settings.RegisterAddOnCategory(category)
		self.category = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function UI:RefreshOptions()
	if not self.panel then return end
	for _, w in ipairs(widgets) do w:Refresh() end
end

function UI:OpenOptions()
	if self.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
		InterfaceOptionsFrame_OpenToCategory(self.panel)
	end
end

function UI:Initialize()
	self:CreateOptions()
end
