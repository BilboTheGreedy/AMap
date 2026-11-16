local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Way = {}
ns.Way = Way

local ARROW = "Interface\\Minimap\\MinimapArrow"
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local ARRIVE = 8
local current
local mapPin, miniPin, arrow
local lastDist, lastTime, speed

local RADIUS = {
	[0] = { 150, 120, 90, 60, 40, 25 },
	[1] = { 233.33, 200, 166.67, 133.33, 100, 66.67 },
}

function ns.ViewRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local ok, r = pcall(C_Minimap.GetViewRadius)
		r = ok and ns.Num(r)
		if r and r > 0 then return r end
	end
	local zoom = ns.Num(Minimap:GetZoom()) or 0
	local outdoors = 1
	if IsIndoors and IsIndoors() then outdoors = 0 end
	return RADIUS[outdoors][zoom + 1] or 150
end

function ns.WorldPos(map, x, y)
	if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not ok or not pos then return nil end
	local north, west = pos.x, pos.y
	if pos.GetXY then north, west = pos:GetXY() end
	north, west = ns.Num(north), ns.Num(west)
	if not north or not west then return nil end
	return north, west, ns.Num(continent)
end

function ns.PlayerWorld()
	if not UnitPosition then return nil end
	local ok, north, west, _, instance = pcall(UnitPosition, "player")
	if not ok then return nil end
	north, west = ns.Num(north), ns.Num(west)
	if not north or not west then return nil end
	return north, west, ns.Num(instance)
end

function Way.Vector()
	if not current or not current.north then return nil end
	local north, west, instance = ns.PlayerWorld()
	if not north then return nil end
	if current.continent and instance and current.continent ~= instance then return nil end
	local dn, dw = current.north - north, current.west - west
	local dist = math.sqrt(dn * dn + dw * dw)
	local bearing = math.atan2(dw, dn)
	return dist, bearing, dn, dw
end

function Way.Angle()
	local dist, bearing = Way.Vector()
	if not dist then return nil end
	local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())
	if not facing then return nil, dist end
	local angle = bearing - facing
	while angle > math.pi do angle = angle - 2 * math.pi end
	while angle < -math.pi do angle = angle + 2 * math.pi end
	return angle, dist
end

function Way.Eta(dist)
	local now = GetTime and GetTime() or 0
	if lastDist and lastTime and now > lastTime then
		local dt = now - lastTime
		if dt >= 0.5 then
			local v = (lastDist - dist) / dt
			speed = speed and (speed * 0.6 + v * 0.4) or v
			lastDist, lastTime = dist, now
		end
	else
		lastDist, lastTime = dist, now
	end
	if not speed or speed < 0.5 then return nil end
	return dist / speed
end

local function timeText(seconds)
	if not seconds then return "" end
	if seconds >= 3600 then return "" end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function pinTooltip(self)
	if not current then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(current.title, 1, 0.82, 0)
	GameTooltip:AddLine(ns.MapName(current.map) .. "  " .. ns.Coord(current.x) .. ", " .. ns.Coord(current.y), 0.9, 0.9, 0.92)
	local dist = Way.Vector()
	if dist then GameTooltip:AddLine(math.floor(dist + 0.5) .. " yards", 0.58, 0.6, 0.65) end
	GameTooltip:AddLine("Click to clear", 0.58, 0.6, 0.65)
	GameTooltip:Show()
end

local function makePin(parent, size)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(size, size)
	f:SetFrameStrata("HIGH")
	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.tex:SetAllPoints(f)
	f.tex:SetTexture(STAR)
	f:SetScript("OnEnter", pinTooltip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function() AMap.ClearWaypoint() end)
	f:Hide()
	return f
end

local function buildArrow()
	arrow = CreateFrame("Button", "AMapArrow", UIParent)
	arrow:SetSize(150, 74)
	arrow:SetFrameStrata("MEDIUM")
	UI.Movable(arrow, ns.db.way.arrowDb)
	arrow:RegisterForDrag("LeftButton")
	arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	arrow:SetScript("OnDragStart", function(self) self:StartDrag() end)
	arrow:SetScript("OnDragStop", function(self) self:StopDrag() end)
	arrow:SetScript("OnClick", function(self, button)
		if button ~= "RightButton" then return end
		UI.Menu(self, {
			{ text = current and current.title or "Waypoint", title = true },
			{ text = "Clear waypoint", func = function() AMap.ClearWaypoint() end },
			{ text = "Show on map", func = function()
				if current and ns.Map then
					if C_Map and C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap, current.map) else ns.Map.Go(current.map) end
				end
			end },
			UI.Check(ns.db.way.arrowDb, "locked", "Lock the arrow"),
			UI.Check(ns.db.way, "arrive", "Clear on arrival"),
		})
	end)
	arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
	arrow.tex:SetSize(44, 44)
	arrow.tex:SetPoint("TOP", 0, 0)
	arrow.tex:SetTexture(ARROW)
	arrow.title = UI.Text(arrow, "GameFontNormalSmall", "CENTER", C.accent)
	arrow.title:SetPoint("TOP", arrow.tex, "BOTTOM", 0, 0)
	arrow.title:SetWidth(150)
	arrow.dist = UI.Text(arrow, "GameFontHighlightSmall", "CENTER")
	arrow.dist:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
	arrow:Hide()
end

function Way.UpdateMapPin()
	if not ns.Canvas() then return end
	if not current or not WorldMapFrame or not WorldMapFrame:IsShown() or ns.MapID() ~= current.map then
		if mapPin then mapPin:Hide() end
		return
	end
	if not mapPin then mapPin = makePin(ns.Canvas(), 20) end
	ns.Place(mapPin, current.x, current.y, 1)
	mapPin:Show()
end

function Way.Update()
	if not current then return end
	Way.UpdateMapPin()
	local dist, bearing, dn, dw = Way.Vector()
	if not dist then
		if arrow then arrow:Hide() end
		if miniPin then miniPin:Hide() end
		return
	end
	if ns.db.way.arrive and dist <= ARRIVE then
		ns.Print("arrived at " .. current.title)
		if PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then pcall(PlaySound, SOUNDKIT.MAP_PING) end
		AMap.ClearWaypoint()
		return
	end

	local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())

	if Minimap and Minimap:IsShown() then
		if not miniPin then miniPin = makePin(Minimap, 14) end
		local radius = ns.ViewRadius()
		local half = (Minimap:GetWidth() or 140) / 2
		local dx, dy = -dw, -dn
		if facing and GetCVar and GetCVar("rotateMinimap") == "1" then
			local sin, cos = math.sin(facing), math.cos(facing)
			dx, dy = dx * cos - dy * sin, dx * sin + dy * cos
		end
		local len = math.sqrt(dx * dx + dy * dy) / radius
		if len > 0.92 then
			local k = 0.92 / len
			dx, dy = dx * k, dy * k
			miniPin:SetAlpha(0.65)
		else
			miniPin:SetAlpha(1)
		end
		miniPin:ClearAllPoints()
		miniPin:SetPoint("CENTER", Minimap, "CENTER", dx / radius * half, -dy / radius * half)
		miniPin:Show()
	end

	if not ns.db.way.arrow or not facing then
		if arrow then arrow:Hide() end
		return
	end
	if not arrow then buildArrow() end
	local angle = bearing - facing
	if arrow.tex.SetRotation then arrow.tex:SetRotation(angle) end
	local off = math.abs(math.atan2(math.sin(angle), math.cos(angle))) / math.pi
	arrow.tex:SetVertexColor(math.min(1, off * 2), math.min(1, (1 - off) * 2), 0.1)
	arrow.title:SetText(current.title)
	local eta = timeText(Way.Eta(dist))
	arrow.dist:SetText(math.floor(dist + 0.5) .. " yd" .. (eta ~= "" and ("   " .. eta) or ""))
	arrow:Show()
end

function AMap.SetWaypoint(map, x, y, title)
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not map or not x or not y then return false end
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	if x < 0 or x > 1 or y < 0 or y > 1 then return false end
	local name = ns.MapName(map)
	if not title or title == "" then
		title = (name ~= "" and (name .. " ") or "") .. ns.Coord(x) .. ", " .. ns.Coord(y)
	end
	current = { map = map, x = x, y = y, title = title }
	current.north, current.west, current.continent = ns.WorldPos(map, x, y)
	lastDist, lastTime, speed = nil, nil, nil
	ns.db.way.saved = { map, x, y, title }
	Way.Update()
	ns:Fire("WAYPOINT", current)
	return true
end

function AMap.ClearWaypoint()
	current = nil
	if ns.db then ns.db.way.saved = nil end
	if mapPin then mapPin:Hide() end
	if miniPin then miniPin:Hide() end
	if arrow then arrow:Hide() end
	ns:Fire("WAYPOINT", nil)
end

function AMap.GetWaypoint()
	if not current then return nil end
	return current.map, current.x, current.y, current.title
end

function Way.Parse(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then return nil end
	local lower = msg:lower()
	if lower == "clear" or lower == "reset" then return "clear" end
	local zone, xs, ys, rest = msg:match("^(.-)%s*(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*(.*)$")
	if not xs then return nil end
	local x, y = tonumber(xs), tonumber(ys)
	if not x or not y or x > 100 or y > 100 then return nil end
	local map
	if zone and zone ~= "" then
		map = ns.FindZone(zone)
		if not map then return nil, "unknown zone: " .. zone end
	else
		map = ns.MapID()
		if not map or not WorldMapFrame or not WorldMapFrame:IsShown() then map = ns.PlayerMap() or map end
	end
	if not map then return nil, "no map to place it on" end
	return map, x / 100, y / 100, rest ~= "" and rest or nil
end

SLASH_AMAPWAY1 = "/way"
SLASH_AMAPWAY2 = "/waypoint"
SlashCmdList["AMAPWAY"] = function(msg)
	local map, x, y, title = Way.Parse(msg)
	if map == "clear" then
		AMap.ClearWaypoint()
	elseif map then
		AMap.SetWaypoint(map, x, y, title)
		ns.Print("waypoint: " .. (AMap.GetWaypoint() and select(4, AMap.GetWaypoint()) or ""))
	else
		ns.Print(x or "usage: /way [zone] x y [name], /way clear")
	end
end

ns:Listen("LOGIN", function()
	local saved = ns.db.way.saved
	if saved and saved[1] then AMap.SetWaypoint(saved[1], saved[2], saved[3], saved[4]) end
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.04 then return end
		elapsed = 0
		if current then Way.Update() end
	end)
end)

ns:Listen("OPTIONS", function()
	if arrow and not ns.db.way.arrow then arrow:Hide() end
	if current then Way.Update() end
end)

ns:Listen("LAYOUT_RESET", function()
	if arrow then arrow:Restore() end
end)
