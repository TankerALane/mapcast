-- Mapcast: screen layouts (span and off-screen modes)
-- Decoupled Lane Studio - MIT License
--
-- Mapcast Companion can make the game window bigger than the monitor it is on.
-- Mapcast then keeps the game on that monitor and uses the rest of the window:
--
--  * span:      the window covers a second monitor too. Mapcast's map fills that
--               monitor and is fully interactive (the mouse simply moves onto it).
--  * offscreen: the window reaches into a strip no monitor shows. The map is drawn
--               there in capture layout and the companion mirrors it.
--
-- In both modes UIParent and WorldFrame are inset to the game monitor's part of the
-- window, and UIParent's scale is adjusted so the UI keeps its size. This is the same
-- mechanism Blizzard uses for notches and debug bars (UpdateUIParentPosition).
-- All changes are made out of combat only.
--
-- Everything is stored as insets in physical pixels from the window's edges
-- (left, top, right, bottom), so it keeps working if the window size changes.

local ADDON_NAME, ns = ...

local Layout = {}
ns.Layout = Layout

local MIN_GAME = 300 -- physical pixels; never squeeze the game smaller than this

function Layout:Mode()
	local db = ns.db
	if not db then return nil end
	if db.screenMode == "span" and db.spanGame and db.spanMap then return "span" end
	if db.screenMode == "offscreen" and db.offscreenEdge then return "offscreen" end
	return nil
end

function Layout:IsActive() return self:Mode() ~= nil end
function Layout:IsSpan() return self:Mode() == "span" end
function Layout:IsOffscreen() return self:Mode() == "offscreen" end

local function Physical()
	local w, h = GetPhysicalScreenSize()
	if not w or not h or w <= 0 or h <= 0 then return nil end
	return w, h
end

-- Insets of the game area (l, t, r, b) in physical pixels, plus the window size.
function Layout:GameInsets()
	local physW, physH = Physical()
	if not physW then return nil end
	local mode, db = self:Mode(), ns.db
	local l, t, r, b
	if mode == "offscreen" then
		local px = math.floor(db.offscreenPixels or 0)
		if db.offscreenEdge == "TOP" then l, t, r, b = 0, px, 0, 0 else l, t, r, b = 0, 0, 0, px end
	elseif mode == "span" then
		l, t, r, b = unpack(db.spanGame)
	else
		return nil
	end
	if physW - l - r < MIN_GAME or physH - t - b < MIN_GAME then return nil end
	return l, t, r, b, physW, physH
end

-- Offscreen: strip height in pixels (nil if the layout doesn't fit).
function Layout:StripPixels()
	if not self:IsOffscreen() then return nil end
	local l, t, r, b = self:GameInsets()
	if not l then return nil end
	return math.max(t, b)
end

-- Span: the map monitor's rectangle in pixels, relative to the game area's top-left.
function Layout:MapRect()
	local gl, gt, gr, gb, physW, physH = self:GameInsets()
	if not gl or not self:IsSpan() then return nil end
	local ml, mt, mr, mb = unpack(ns.db.spanMap)
	local w, h = physW - ml - mr, physH - mt - mb
	if w < 100 or h < 100 then return nil end
	return ml - gl, mt - gt, w, h
end

local function Edges(frame, physH)
	local s = frame:GetEffectiveScale() * physH / 768 -- physical pixels per frame unit
	local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (l and r and t and b) then return nil end
	return l * s, r * s, t * s, b * s
end

local function Inset(frame, l, t, r, b, physH)
	local u = 768 / physH / frame:GetEffectiveScale() -- frame units per physical pixel
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", nil, "TOPLEFT", l * u, -t * u)
	frame:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", -r * u, b * u)
end

-- True if UIParent / WorldFrame are where the layout wants them.
function Layout:InPlace()
	local l, t, r, b, physW, physH = self:GameInsets()
	if not l then return true end
	if self.appliedScale and math.abs(UIParent:GetScale() - self.appliedScale) > 1e-4 then return false end
	for _, f in ipairs({ UIParent, WorldFrame }) do
		local fl, fr, ft, fb = Edges(f, physH)
		if not fl then return false end
		if math.abs(fl - l) > 1 or math.abs(fr - (physW - r)) > 1
			or math.abs(ft - (physH - t)) > 1 or math.abs(fb - b) > 1 then
			return false
		end
	end
	return true
end

function Layout:Apply()
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = false
	local l, t, r, b, physW, physH = self:GameInsets()
	if not l then
		self:Remove()
		return
	end

	-- The game sets UIParent's scale itself (from the UI scale option). Keep that as
	-- the base and scale it by gameHeight/windowHeight so the UI keeps its pixel size.
	local cur = UIParent:GetScale()
	if not self.appliedScale or math.abs(cur - self.appliedScale) > 1e-4 then
		self.baseScale = cur
	end
	local scale = self.baseScale * (physH - t - b) / physH
	self.applying = true
	UIParent:SetScale(scale)
	self.appliedScale = scale
	Inset(UIParent, l, t, r, b, physH)
	Inset(WorldFrame, l, t, r, b, physH)
	self.applying = false
	self.applied = true
end

function Layout:Remove()
	if not self.applied then return end
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.applying = true
	if self.baseScale then UIParent:SetScale(self.baseScale) end
	UIParent:ClearAllPoints()
	UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
	UIParent:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
	WorldFrame:ClearAllPoints()
	WorldFrame:SetAllPoints(nil)
	self.applying = false
	self.applied, self.appliedScale, self.baseScale = false, nil, nil
	if UpdateUIParentPosition then UpdateUIParentPosition() end -- let Blizzard re-add notch / debug offsets
end

-- Called every second (Map:SlowTick) and after relevant events. Re-applies if
-- something (cinematics, display or scale changes, Blizzard code) moved things back.
function Layout:Check()
	if not self:IsActive() then
		if self.applied then
			self:Remove()
			ns.Map:ApplyLayout()
		end
		return
	end
	if InCombatLockdown() then return end
	-- Cinematics letterbox WorldFrame themselves; re-apply after CINEMATIC_STOP instead.
	if (CinematicFrame and CinematicFrame:IsShown()) or (MovieFrame and MovieFrame:IsShown()) then return end
	if self.pending or not self.applied or not self:InPlace() then
		self:Apply()
		ns.Map:ApplyLayout()
	end
end

local function Changed()
	if InCombatLockdown() then
		ns.Print("you are in combat; the layout will change when combat ends.")
	end
	Layout:Apply()
	ns.Map:ApplyLayout()
	if ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end

function Layout:SetNormal()
	ns.db.screenMode = nil
	Changed()
	ns.Print("normal layout: the game uses the whole window again. Use Mapcast Companion > Game window > Restore game window to shrink the window back.")
end

-- /mapcast offscreen top|bottom <pixels>
function Layout:SetOffscreen(edge, pixels)
	local db = ns.db
	db.screenMode = "offscreen"
	db.offscreenEdge = edge
	if pixels then db.offscreenPixels = pixels end
	Changed()
	local px = self:StripPixels()
	if not px then
		ns.Print(("|cffff5555the game window is too small for a %d px strip. Has Mapcast Companion extended it? (right-click it > Game window)|r"):format(db.offscreenPixels))
		return
	end
	ns.Print(("off-screen mode on: the map lives in the %d px strip at the %s of the game window. /mapcast normal to undo.")
		:format(px, edge == "TOP" and "top" or "bottom"))
	local need = db.captureHeight + 2 * db.captureBorder
	if need > px then
		ns.Print(("|cffe0904fthe map (%d px tall) doesn't fit in the strip. Lower the capture height in /mapcast options or use a bigger strip.|r"):format(need))
	end
end

-- /mapcast span l,t,r,b l,t,r,b  (game insets, map insets; from Mapcast Companion)
function Layout:SetSpan(game, map)
	ns.db.screenMode = "span"
	ns.db.spanGame, ns.db.spanMap = game, map
	Changed()
	if not self:MapRect() then
		ns.Print("|cffff5555the game window doesn't match these numbers. Use Mapcast Companion > Game window > Span game onto..., then paste the command it shows.|r")
		return
	end
	ns.Print("span mode on: the map fills your other monitor. Move the mouse onto it to zoom, pan and browse. /mapcast normal to undo.")
end

function Layout:Initialize()
	local db = ns.db
	-- Settings from before span mode existed.
	if db.offscreenEdge and not db.screenMode then db.screenMode = "offscreen" end

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("CINEMATIC_STOP")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function()
		if Layout:IsActive() or Layout.pending or Layout.applied then
			C_Timer.After(0, function() Layout:Check() end)
		end
	end)
	-- Blizzard re-anchors UIParent for notches / debug bars; put our inset back.
	if UpdateUIParentPosition then
		hooksecurefunc("UpdateUIParentPosition", function()
			if Layout.applying or not Layout:IsActive() then return end
			C_Timer.After(0, function() Layout:Check() end)
		end)
	end
	if self:IsActive() then self:Apply() end
end
