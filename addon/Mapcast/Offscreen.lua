-- Mapcast: off-screen mode
-- Decoupled Lane Studio - MIT License
--
-- Mapcast Companion can make the game window taller than its monitor, so a strip
-- of the window (above or below the monitor) is not shown by any screen. Windows
-- still captures that strip. In off-screen mode Mapcast:
--  * puts the map (in capture layout) inside the strip, and
--  * keeps the game on the visible part: UIParent and WorldFrame are inset to
--    exclude the strip, and UIParent's scale is adjusted so the UI stays exactly
--    the size it was before.
-- This is the same mechanism Blizzard uses for notches and debug bars
-- (UpdateUIParentPosition). All changes are made out of combat only.

local ADDON_NAME, ns = ...

local Off = {}
ns.Offscreen = Off

local MIN_VISIBLE = 300 -- physical pixels; never squeeze the game smaller than this

function Off:IsActive()
	return ns.db and ns.db.offscreenEdge ~= nil
end

-- Strip size in physical pixels, the physical screen height, and the edge.
function Off:Geometry()
	local _, physH = GetPhysicalScreenSize()
	local px = math.floor(ns.db.offscreenPixels or 0)
	if not physH or physH <= 0 or px <= 0 then return nil end
	if physH - px < MIN_VISIBLE then return nil end
	return px, physH, ns.db.offscreenEdge
end

local function ScreenTop(frame)
	local _, physH = GetPhysicalScreenSize()
	local top = frame:GetTop()
	return top and top * frame:GetEffectiveScale() * physH / 768
end

local function ScreenBottom(frame)
	local _, physH = GetPhysicalScreenSize()
	local b = frame:GetBottom()
	return b and b * frame:GetEffectiveScale() * physH / 768
end

-- Places `frame` (a full-screen frame without a parent) on the visible part.
local function Inset(frame, px, physH, edge)
	local u = 768 / physH / frame:GetEffectiveScale() -- frame units per physical pixel
	frame:ClearAllPoints()
	if edge == "TOP" then
		frame:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -px * u)
		frame:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
	else
		frame:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
		frame:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, px * u)
	end
end

-- True if UIParent / WorldFrame are where off-screen mode wants them.
function Off:InPlace()
	local px, physH, edge = self:Geometry()
	if not px then return true end
	if self.appliedScale and math.abs(UIParent:GetScale() - self.appliedScale) > 1e-4 then return false end
	for _, f in ipairs({ UIParent, WorldFrame }) do
		local top, bottom = ScreenTop(f), ScreenBottom(f)
		if not top or not bottom then return false end
		local wantTop = edge == "TOP" and physH - px or physH
		local wantBottom = edge == "TOP" and 0 or px
		if math.abs(top - wantTop) > 1 or math.abs(bottom - wantBottom) > 1 then return false end
	end
	return true
end

function Off:Apply()
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = false
	local px, physH, edge = self:Geometry()

	if not px then
		self:Remove()
		return
	end

	-- The game sets UIParent's scale itself (from the UI scale option). Keep that
	-- as the base and shrink it by visible/total so the UI keeps its pixel size.
	local cur = UIParent:GetScale()
	if not self.appliedScale or math.abs(cur - self.appliedScale) > 1e-4 then
		self.baseScale = cur
	end
	local scale = self.baseScale * (physH - px) / physH
	self.applying = true
	UIParent:SetScale(scale)
	self.appliedScale = scale
	Inset(UIParent, px, physH, edge)
	Inset(WorldFrame, px, physH, edge)
	self.applying = false
	self.applied = true
end

function Off:Remove()
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

-- Called from Map:SlowTick. Re-applies if something (cinematics, display or
-- scale changes, Blizzard code) moved UIParent or WorldFrame back.
function Off:Check()
	if not self:IsActive() then
		if self.applied then self:Remove() end
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

-- /mapcast offscreen [top|bottom] [pixels] | off
function Off:SetMode(edge, pixels)
	local db = ns.db
	if edge then
		db.offscreenEdge = edge
		if pixels then db.offscreenPixels = pixels end
	else
		db.offscreenEdge = nil
	end
	if InCombatLockdown() then
		ns.Print("you are in combat; off-screen mode will change when combat ends.")
	end
	self:Apply()
	ns.Map:ApplyLayout()

	if edge then
		local px, physH = self:Geometry()
		if not px then
			ns.Print(("|cffff5555the game window is too small for a %d px strip.|r"):format(db.offscreenPixels))
			return
		end
		ns.Print(("off-screen mode on: the map lives in the %d px strip at the %s of the game window. /mapcast offscreen off to undo.")
			:format(px, edge == "TOP" and "top" or "bottom"))
		local need = db.captureHeight + 2 * db.captureBorder
		if need > px then
			ns.Print(("|cffe0904fthe map (%d px tall) doesn't fit in the strip. Lower the capture height in /mapcast options or use a bigger strip.|r"):format(need))
		end
		if physH - px < 600 then
			ns.Print("|cffe0904fthe visible game area is small. Has Mapcast Companion extended the game window yet? (Right-click it > Off-screen map)|r")
		end
	else
		ns.Print("off-screen mode off.")
	end
	if ns.UI.RefreshOptions then ns.UI:RefreshOptions() end
end

function Off:Initialize()
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("CINEMATIC_STOP")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function()
		if Off:IsActive() or Off.pending then
			C_Timer.After(0, function() Off:Check() end)
		end
	end)
	-- Blizzard re-anchors UIParent for notches / debug bars; put our inset back.
	if UpdateUIParentPosition then
		hooksecurefunc("UpdateUIParentPosition", function()
			if Off.applying or not Off:IsActive() then return end
			C_Timer.After(0, function() Off:Check() end)
		end)
	end
	if self:IsActive() then self:Apply() end
end
