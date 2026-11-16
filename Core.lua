local ADDON, ns = ...

AMap = {}

local defaults = {
	map = {
		window = true,
		alpha = 1,
		fade = true,
		fadeAlpha = 0.45,
		coords = true,
		arrow = true,
		arrowSize = 1.4,
		party = true,
		zoom = true,
		title = true,
		send = false,
		follow = false,
	},
	minimap = {
		square = false,
		hideZoom = true,
		hideClock = false,
		hideTracking = false,
		hideMapButton = true,
		wheel = true,
		coords = true,
		zone = false,
		scale = 1,
		locked = true,
	},
}

ACore.New(ADDON, ns, { db = "AMapDB", defaults = defaults, profile = true })

local queue = {}
function ns.Safe(fn)
	if InCombatLockdown and InCombatLockdown() then
		queue[#queue + 1] = fn
		return false
	end
	fn()
	return true
end

ns:On("PLAYER_REGEN_ENABLED", function()
	local q = queue
	queue = {}
	for i = 1, #q do q[i]() end
end)

function ns.Queued()
	return #queue
end

function ns.Num(v)
	if v == nil or ns.IsSecret(v) or type(v) ~= "number" then return nil end
	return v
end

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local function changed() ns:Fire("OPTIONS") end
	local entries = {
		{ text = "World map", title = true },
		UI.Check(db.map, "window", "Movable window", changed),
		UI.Check(db.map, "zoom", "Deeper zoom", changed),
		UI.Check(db.map, "coords", "Coordinates", changed),
		UI.Check(db.map, "title", "Zone level and faction", changed),
		UI.Check(db.map, "arrow", "Large player arrow", changed),
		UI.Check(db.map, "party", "Party members", changed),
		UI.Check(db.map, "fade", "Fade while moving", changed),
		UI.Check(db.map, "send", "Alt-click tells the party a location", changed),
		{
			text = "Opacity: " .. math.floor(db.map.alpha * 100 + 0.5) .. "%",
			func = function()
				local a = db.map.alpha - 0.2
				if a < 0.35 then a = 1 end
				db.map.alpha = a
				changed()
			end,
		},
		{ text = "Reset map position and size", func = function()
			db.map.pos = nil
			db.map.scale = nil
			ns:Fire("LAYOUT_RESET")
		end },
		{ text = "Minimap", title = true },
		UI.Check(db.minimap, "square", "Square shape", changed),
		UI.Check(db.minimap, "hideZoom", "Hide zoom buttons", changed),
		UI.Check(db.minimap, "hideMapButton", "Hide world map button", changed),
		UI.Check(db.minimap, "hideClock", "Hide clock and calendar", changed),
		UI.Check(db.minimap, "hideTracking", "Hide tracking button", changed),
		UI.Check(db.minimap, "wheel", "Mouse wheel zoom", changed),
		UI.Check(db.minimap, "coords", "Coordinates below", changed),
		UI.Check(db.minimap, "zone", "Zone name below", changed),
		UI.Check(db.minimap, "locked", "Lock position", changed),
		{
			text = "Size: " .. math.floor(db.minimap.scale * 100 + 0.5) .. "%",
			func = function()
				local s = db.minimap.scale + 0.1
				if s > 1.45 then s = 0.8 end
				db.minimap.scale = s
				changed()
			end,
		},
	}
	return entries
end

function ns.OpenOptions(anchor)
	ns.UI.Menu(anchor or UIParent, ns.Options())
end

ACore.Register({
	name = "AMap",
	options = function() return ns.Options() end,
	title = "AMap",
	slash = "/amap",
	desc = "map and minimap",
	toggle = function()
		if ACoreMinimapButton and ACoreMinimapButton:IsShown() then
			ns.OpenOptions(ACoreMinimapButton)
		else
			ns.OpenOptions(Minimap)
		end
	end,
})

SLASH_AMAP1 = "/amap"
SlashCmdList["AMAP"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "reset" then
		ns.db.map.pos = nil
		ns.db.map.scale = nil
		ns.db.minimap.pos = nil
		ns.db.minimap.scale = 1
		ns:Fire("LAYOUT_RESET")
		ns:Fire("OPTIONS")
	elseif cmd == "unlock" then
		ns.db.minimap.locked = false
		ns:Fire("OPTIONS")
		ns.Print("minimap unlocked, drag to move")
	elseif cmd == "lock" then
		ns.db.minimap.locked = true
		ns:Fire("OPTIONS")
	else
		ns.OpenOptions(Minimap)
	end
end

function AMap.SetWaypoint(map, x, y, title)
	if AWay and AWay.Add then return AWay.Add(map, x, y, title) and true or false end
	return false
end

function AMap.ClearWaypoint()
	if AWay and AWay.Clear then AWay.Clear() end
end

function AMap.GetWaypoint()
	if AWay and AWay.Get then return AWay.Get() end
	return nil
end
