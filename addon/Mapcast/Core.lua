-- Mapcast: core (constants, saved variables, slash commands, key bindings)
-- Decoupled Lane Studio - MIT License

local ADDON_NAME, ns = ...

local Mapcast = CreateFrame("Frame")
ns.Mapcast = Mapcast
_G.Mapcast = Mapcast -- for /dump and other addons; nothing secure depends on it

---------------------------------------------------------------------------
-- Constants (single source of truth)
---------------------------------------------------------------------------
-- Where users download Mapcast Companion. Used by the first-run popup and
-- the options panel. Keep this the ONLY copy of the URL.
ns.RELEASES_URL = "https://github.com/TankerALane/mapcast/releases"

-- Capture-mode marker colour. Mapcast Companion looks for this exact colour
-- (pure magenta, #FF00FF). If you change it here, change MarkerDetector.cs too.
ns.MARKER_R, ns.MARKER_G, ns.MARKER_B = 1, 0, 1

ns.TITLE = "Mapcast"
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "dev"
if ns.VERSION:find("@project") then ns.VERSION = "dev" end

local DEFAULTS = {
	shown = true,
	locked = false,
	follow = true,           -- auto-switch to the player's current zone
	centerOnPlayer = true,   -- keep the arrow centred when zoomed in
	autoResume = 30,         -- seconds after manual browsing before follow resumes (0 = never)
	alpha = 1.0,
	scale = 1.0,
	pinScale = 1.0,
	width = 420,
	height = 320,
	strata = "MEDIUM",
	mirrorPins = true,       -- copy HereBeDragons pins (Questie, TomTom, HandyNotes, ...)
	captureMode = false,
	captureWidth = 640,      -- physical screen pixels, inside the marker border
	captureHeight = 480,
	captureBorder = 4,       -- physical pixels
	popupDismissed = false,
}
ns.DEFAULTS = DEFAULTS

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function ns.Print(...)
	print("|cff4cd3b6Mapcast|r:", ...)
end

---------------------------------------------------------------------------
-- Public toggles (also used by Bindings.xml)
---------------------------------------------------------------------------
function Mapcast_Toggle()
	ns.Map:SetShownSaved(not ns.Map:IsShownSaved())
end

function Mapcast_ToggleLock()
	ns.Map:SetLocked(not ns.db.locked)
	ns.Print(ns.db.locked and "locked." or "unlocked.")
end

function Mapcast_ToggleCapture()
	ns.Map:SetCaptureMode(not ns.db.captureMode)
end

BINDING_HEADER_MAPCAST = "Mapcast"
BINDING_NAME_MAPCAST_TOGGLE = "Show/hide Mapcast"
BINDING_NAME_MAPCAST_LOCK = "Lock/unlock Mapcast"
BINDING_NAME_MAPCAST_CAPTURE = "Toggle Mapcast capture mode"

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local HELP = {
	"/mapcast - show or hide the map",
	"/mapcast show | hide",
	"/mapcast lock | unlock",
	"/mapcast follow - toggle auto-follow of your current zone",
	"/mapcast capture - toggle capture mode (for Mapcast Companion)",
	"/mapcast reset - reset position, size and scale",
	"/mapcast companion - how to show Mapcast on a second monitor",
	"/mapcast options - open the options panel",
}

local function HandleSlash(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	local map = ns.Map
	if cmd == "" or cmd == "toggle" then
		Mapcast_Toggle()
	elseif cmd == "show" then
		map:SetShownSaved(true)
	elseif cmd == "hide" then
		map:SetShownSaved(false)
	elseif cmd == "lock" then
		map:SetLocked(true); ns.Print("locked.")
	elseif cmd == "unlock" then
		map:SetLocked(false); ns.Print("unlocked. Drag the title bar to move, the corner to resize.")
	elseif cmd == "follow" then
		map:SetFollow(not ns.db.follow)
		ns.Print("auto-follow " .. (ns.db.follow and "on." or "off."))
	elseif cmd == "capture" then
		Mapcast_ToggleCapture()
	elseif cmd == "reset" then
		map:ResetLayout(); ns.Print("position, size and scale reset.")
	elseif cmd == "companion" then
		ns.UI:ShowCompanionPopup(true)
	elseif cmd == "debug" then
		ns.Mirror:DiscoverLibs()
		ns.Mirror:Refresh()
		ns.Mirror:PrintDebug()
	elseif cmd == "options" or cmd == "config" then
		ns.UI:OpenOptions()
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end

SLASH_MAPCAST1 = "/mapcast"
SlashCmdList.MAPCAST = HandleSlash

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
Mapcast:RegisterEvent("ADDON_LOADED")
Mapcast:RegisterEvent("PLAYER_LOGIN")
Mapcast:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		MapcastDB = MapcastDB or {}
		CopyDefaults(DEFAULTS, MapcastDB)
		ns.db = MapcastDB
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		local ok, err = pcall(ns.Map.Initialize, ns.Map)
		if not ok then
			ns.Print("|cffff5555could not create the map:|r " .. tostring(err))
			return
		end
		ns.UI:Initialize()
		if not ns.db.popupDismissed then
			C_Timer.After(3, function() ns.UI:ShowCompanionPopup(false) end)
		end
	end
end)
