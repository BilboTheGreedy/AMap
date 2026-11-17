local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Map = {}
ns.Map = Map

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMaskSmall"
local bar, grip, arrow
local dots = {}
local following
local extended = setmetatable({}, { __mode = "k" })
local windowed

local function scroll()
	return WorldMapFrame and WorldMapFrame.ScrollContainer
end

function ns.Canvas()
	if not WorldMapFrame then return nil end
	if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
	local s = scroll()
	return s and s.Child
end

function ns.MapID()
	if WorldMapFrame and WorldMapFrame.GetMapID then
		local ok, map = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
		return ok and ns.Num(map) or nil
	end
end

function ns.PlayerMap()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and ns.Num(map) or nil
end

function ns.UnitPos(map, unit)
	if not map or not C_Map or not C_Map.GetPlayerMapPosition then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, unit)
	if not ok or ns.IsSecret(pos) or type(pos) ~= "table" then return nil end
	local x, y = pos.x, pos.y
	if pos.GetXY then x, y = pos:GetXY() end
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	return x, y
end

function ns.Place(frame, x, y, mult)
	local c = ns.Canvas()
	if not c then return end
	local scale = ns.Num(c:GetEffectiveScale()) or 1
	if scale <= 0 then scale = 1 end
	local pinScale = (ns.Num(UIParent:GetEffectiveScale()) or 1) * (mult or 1) / scale
	frame:SetScale(pinScale)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", c, "TOPLEFT", x * c:GetWidth() / pinScale, -y * c:GetHeight() / pinScale)
end

function ns.Coord(v)
	return string.format("%.1f", v * 100)
end

function Map.CursorPos()
	local s = scroll()
	if not s or not s.GetNormalizedCursorPosition then return nil end
	if s.IsMouseOver and not s:IsMouseOver() then return nil end
	local ok, x, y = pcall(s.GetNormalizedCursorPosition, s)
	if not ok then return nil end
	x, y = ns.Num(x), ns.Num(y)
	if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

function Map.ExtendZoom()
	local s = scroll()
	if not s or not ns.db.map.zoom then return false end
	local levels = s.zoomLevels
	if type(levels) ~= "table" or #levels == 0 or extended[levels] then return false end
	local last = levels[#levels]
	if type(last) ~= "table" or type(last.scale) ~= "number" then return false end
	local scale = last.scale
	for _ = 1, 3 do
		scale = scale * 1.6
		levels[#levels + 1] = { scale = scale, layerIndex = last.layerIndex }
	end
	extended[levels] = true
	return true
end

local function applyWindow()
	local db = ns.db.map
	if not WorldMapFrame then return end
	if not db.window then
		if grip then grip:Hide() end
		if windowed then
			windowed = nil
			ns.Safe(function()
				local black = WorldMapFrame.BlackoutFrame
				if black then
					black:SetAlpha(1)
					black:EnableMouse(true)
				end
				WorldMapFrame:SetScale(1)
			end, "window")
		end
		return
	end
	windowed = true
	ns.Safe(function()
		local black = WorldMapFrame.BlackoutFrame
		if black then
			black:SetAlpha(0)
			black:EnableMouse(false)
			if not db.scale then db.scale = 0.75 end
		end
		WorldMapFrame:SetMovable(true)
		WorldMapFrame:SetClampedToScreen(true)
		if db.scale then WorldMapFrame:SetScale(db.scale) end
		if db.pos and db.pos[1] then
			WorldMapFrame:ClearAllPoints()
			WorldMapFrame:SetPoint(db.pos[1], UIParent, db.pos[2] or db.pos[1], db.pos[3] or 0, db.pos[4] or 0)
		end
		if grip then grip:Show() end
	end, "window")
end

local function savePos()
	local point, _, rel, x, y = WorldMapFrame:GetPoint(1)
	if point then ns.db.map.pos = { point, rel or point, x or 0, y or 0 } end
end

function Map.SetScale(scale)
	scale = math.max(0.4, math.min(1.5, scale))
	ns.db.map.scale = scale
	ns.Safe(function() WorldMapFrame:SetScale(scale) end, "scale")
	return scale
end

local function byName(a, b)
	return tostring(a.name) < tostring(b.name)
end

function Map.Continents()
	if not C_Map or not C_Map.GetMapChildrenInfo then return nil end
	local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local top = ns.PlayerMap() or ns.MapID()
	for _ = 1, 12 do
		local info = ns.MapInfo(top)
		local parent = info and ns.Num(info.parentMapID)
		if not parent or parent <= 0 then break end
		top = parent
	end
	local seen = {}
	for _, id in ipairs({ top or false, 947, 946 }) do
		if id and not seen[id] then
			seen[id] = true
			local ok, list = pcall(C_Map.GetMapChildrenInfo, id, continentType, true)
			if ok and type(list) == "table" and #list > 0 then
				table.sort(list, byName)
				return list
			end
		end
	end
	return nil
end

local function jumpMenu(anchor)
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local continents = Map.Continents()
	if not continents then return end
	local entries = { { text = "Jump to", title = true } }
	local pm = ns.PlayerMap()
	if pm then
		entries[#entries + 1] = { text = "Where I am", func = function() Map.Go(pm) end }
	end
	for _, cont in ipairs(continents) do
		entries[#entries + 1] = {
			text = cont.name .. " >",
			func = function()
				local ok2, zones = pcall(C_Map.GetMapChildrenInfo, cont.mapID, zoneType, false)
				local list = { { text = cont.name, title = true }, { text = "Whole continent", func = function() Map.Go(cont.mapID) end } }
				if ok2 and type(zones) == "table" then
					table.sort(zones, byName)
					for _, z in ipairs(zones) do
						local info = ns.ZoneInfo(z.mapID)
						list[#list + 1] = {
							text = z.name .. (info and ("  " .. info) or ""),
							checked = z.mapID == ns.MapID(),
							func = function() Map.Go(z.mapID) end,
						}
					end
				end
				UI.Menu(anchor, list)
			end,
		}
	end
	UI.Menu(anchor, entries)
end

function Map.Go(map)
	if not map or not WorldMapFrame or not WorldMapFrame.SetMapID then return end
	following = false
	ns.db.map.follow = false
	pcall(WorldMapFrame.SetMapID, WorldMapFrame, map)
	Map.Refresh()
end

function Map.Follow()
	local pm = ns.PlayerMap()
	if not pm or not WorldMapFrame then return false end
	if ns.MapID() ~= pm and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, pm) end
	local x, y = ns.UnitPos(pm, "player")
	local s = scroll()
	if x and s and s.SetPanTarget then pcall(s.SetPanTarget, s, x, y) end
	return true
end

local function build()
	local s = scroll()
	local parent = s or WorldMapFrame
	bar = CreateFrame("Frame", "AMapBar", WorldMapFrame)
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	bar:SetHeight(22)
	bar:SetFrameStrata("HIGH")
	ns.Level(bar, WorldMapFrame, 3000)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	UI.Fill(bar, { 0.06, 0.065, 0.08, 0.8 })
	bar:SetScript("OnDragStart", function()
		if not ns.db.map.window or (InCombatLockdown and InCombatLockdown()) then return end
		WorldMapFrame:StartMoving()
		bar.moving = true
	end)
	bar:SetScript("OnDragStop", function()
		if not bar.moving then return end
		bar.moving = nil
		WorldMapFrame:StopMovingOrSizing()
		savePos()
	end)

	bar.title = UI.Text(bar, "GameFontNormalSmall", "LEFT", C.accent)
	bar.title:SetPoint("LEFT", 8, 0)
	bar.info = UI.Text(bar, "GameFontHighlightSmall", "LEFT")
	bar.info:SetPoint("LEFT", bar.title, "RIGHT", 8, 0)

	bar.options = UI.Button(bar, "Options", function(self) ns.OpenOptions(self) end)
	bar.options:SetPoint("RIGHT", -4, 0)
	bar.options:SetHeight(18)
	bar.zones = UI.Button(bar, "Zones", function(self) jumpMenu(self) end)
	bar.zones:SetPoint("RIGHT", bar.options, "LEFT", -4, 0)
	bar.zones:SetHeight(18)
	bar.follow = UI.Button(bar, "Follow", function()
		following = not following
		ns.db.map.follow = following
		if following then Map.Follow() end
		Map.Refresh()
	end)
	bar.follow:SetPoint("RIGHT", bar.zones, "LEFT", -4, 0)
	bar.follow:SetHeight(18)
	bar.coords = UI.Text(bar, "GameFontHighlightSmall", "RIGHT")
	bar.coords:SetPoint("RIGHT", bar.follow, "LEFT", -10, 0)

	grip = CreateFrame("Button", nil, WorldMapFrame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	grip:SetFrameStrata("HIGH")
	ns.Level(grip, WorldMapFrame, 3000)
	grip.tex = grip:CreateTexture(nil, "OVERLAY")
	grip.tex:SetAllPoints(grip)
	grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Drag to resize the map", 1, 1, 1)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
	grip:SetScript("OnMouseDown", function(self)
		if InCombatLockdown and InCombatLockdown() then return end
		local x = GetCursorPosition()
		self.startX = x
		self.startScale = WorldMapFrame:GetScale() or 1
		self.width = math.max(200, (WorldMapFrame:GetWidth() or 800) * (WorldMapFrame:GetEffectiveScale() or 1))
		self:SetScript("OnUpdate", function(g)
			if InCombatLockdown and InCombatLockdown() then
				g:SetScript("OnUpdate", nil)
				return
			end
			local cx = GetCursorPosition()
			Map.SetScale(g.startScale * (1 + (cx - g.startX) / g.width))
		end)
	end)
	grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	local c = ns.Canvas()
	arrow = CreateFrame("Frame", nil, c or WorldMapFrame)
	arrow:SetSize(32, 32)
	arrow:SetFrameStrata("HIGH")
	ns.Level(arrow, c or WorldMapFrame, 2400)
	arrow.tex = arrow:CreateTexture(nil, "OVERLAY")
	arrow.tex:SetAllPoints(arrow)
	arrow.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
	arrow:Hide()
end

local function dot(i)
	local d = dots[i]
	if d then return d end
	local parent = ns.Canvas() or WorldMapFrame
	d = CreateFrame("Frame", nil, parent)
	d:SetSize(10, 10)
	d:SetFrameStrata("HIGH")
	ns.Level(d, parent, 2300)
	d.back = d:CreateTexture(nil, "BACKGROUND")
	d.back:SetTexture(CIRCLE)
	d.back:SetVertexColor(0, 0, 0, 0.9)
	d.back:SetPoint("TOPLEFT", -1.5, 1.5)
	d.back:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	d.tex = d:CreateTexture(nil, "ARTWORK")
	d.tex:SetAllPoints(d)
	d.tex:SetTexture(CIRCLE)
	d.name = UI.Text(d, "GameFontHighlightSmall", "LEFT")
	d.name:SetPoint("LEFT", d, "RIGHT", 3, 0)
	dots[i] = d
	return d
end

function Map.GroupUnits()
	local units = {}
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if type(n) ~= "number" or n == 0 then return units end
	if IsInRaid and IsInRaid() then
		for i = 1, math.min(n, 40) do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then units[#units + 1] = unit end
		end
	else
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then units[#units + 1] = unit end
		end
	end
	return units
end

local function updateParty(map)
	local shown = 0
	if ns.db.map.party and map then
		for _, unit in ipairs(Map.GroupUnits()) do
			local x, y = ns.UnitPos(map, unit)
			if x then
				shown = shown + 1
				local d = dot(shown)
				local _, class = UnitClass(unit)
				if ns.IsSecret(class) then class = nil end
				local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				if col then
					d.tex:SetVertexColor(col.r, col.g, col.b)
					d.name:SetTextColor(col.r, col.g, col.b)
				else
					d.tex:SetVertexColor(1, 1, 1)
					d.name:SetTextColor(1, 1, 1)
				end
				local name = UnitName(unit)
				if ns.IsSecret(name) or type(name) ~= "string" then name = nil end
				d.name:SetText(name or "")
				ns.Place(d, x, y, 1)
				d:Show()
			end
		end
	end
	for i = shown + 1, #dots do dots[i]:Hide() end
	return shown
end

function Map.Update()
	if not bar then return end
	local db = ns.db.map
	local map = ns.MapID()
	local px, py = ns.UnitPos(map, "player")

	if db.coords then
		local parts = {}
		if px then parts[#parts + 1] = "Player " .. ns.Coord(px) .. ", " .. ns.Coord(py) end
		local cx, cy = Map.CursorPos()
		if cx then parts[#parts + 1] = "Cursor " .. ns.Coord(cx) .. ", " .. ns.Coord(cy) end
		bar.coords:SetText(table.concat(parts, "     "))
	else
		bar.coords:SetText("")
	end

	if db.arrow and px then
		local facing = GetPlayerFacing and ns.Num(GetPlayerFacing())
		if facing and arrow.tex.SetRotation then arrow.tex:SetRotation(facing) end
		ns.Place(arrow, px, py, db.arrowSize or 1.4)
		arrow:Show()
	else
		arrow:Hide()
	end

	updateParty(map)

	local alpha = db.alpha or 1
	if db.fade and GetUnitSpeed then
		local speed = ns.Num(GetUnitSpeed("player"))
		local over = WorldMapFrame.IsMouseOver and WorldMapFrame:IsMouseOver()
		if speed and speed > 0 and not over then alpha = math.min(alpha, db.fadeAlpha or 0.45) end
	end
	if alpha ~= Map.alpha then
		Map.alpha = alpha
		WorldMapFrame:SetAlpha(alpha)
	end

	if following then
		local pm = ns.PlayerMap()
		if pm and (pm ~= Map.followMap or map ~= pm) then
			Map.followMap = pm
			Map.Follow()
		elseif px then
			local s = scroll()
			if s and s.SetPanTarget then pcall(s.SetPanTarget, s, px, py) end
		end
	end
end

function Map.Refresh()
	if not bar then return end
	local db = ns.db.map
	local map = ns.MapID()
	bar.title:SetText(ns.MapName(map))
	local info, r, g, b
	if db.title and map then info, r, g, b = ns.ZoneInfo(map) end
	bar.info:SetText(info or "")
	bar.info:SetTextColor(r or 1, g or 1, b or 1)
	bar.follow:SetActive(following and true or false)
	Map.ExtendZoom()
	Map.alpha = nil
	Map.Update()
end

function Map.Click(button)
	local x, y = Map.CursorPos()
	local map = ns.MapID()
	if not x or not map then return false end
	if button == "LeftButton" and IsControlKeyDown() then
		return AMap.SetWaypoint(map, x, y)
	end
	if button == "LeftButton" and IsAltKeyDown() and ns.db.map.send then
		local text = ns.MapName(map) .. " " .. ns.Coord(x) .. ", " .. ns.Coord(y)
		local channel
		if IsInRaid and IsInRaid() then
			channel = "RAID"
		elseif IsInGroup and IsInGroup() then
			channel = "PARTY"
		end
		if channel and SendChatMessage then
			pcall(SendChatMessage, text, channel)
		else
			ns.Print(text)
		end
		return true
	end
	return false
end

ns:Listen("LOGIN", function()
	if not WorldMapFrame then return end
	build()
	following = ns.db.map.follow
	local elapsed = 0
	bar:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.05 then return end
		elapsed = 0
		Map.Update()
	end)
	if WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function()
			applyWindow()
			Map.followMap = nil
			Map.Refresh()
		end)
	end
	if hooksecurefunc and WorldMapFrame.OnMapChanged then
		pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() Map.Refresh() end)
	end
	if hooksecurefunc and WorldMapFrame.SynchronizeDisplayState then
		pcall(hooksecurefunc, WorldMapFrame, "SynchronizeDisplayState", function() applyWindow() end)
	end
	if hooksecurefunc and UpdateUIPanelPositions then
		pcall(hooksecurefunc, "UpdateUIPanelPositions", function()
			if ns.db.map.pos and WorldMapFrame:IsShown() then applyWindow() end
		end)
	end
	local s = scroll()
	if s then
		if hooksecurefunc and s.CreateZoomLevels then
			pcall(hooksecurefunc, s, "CreateZoomLevels", function() Map.ExtendZoom() end)
		end
		if s.HookScript then
			s:HookScript("OnMouseUp", function(_, button) Map.Click(button) end)
		end
	end
	Map.ExtendZoom()
	applyWindow()
end)

ns:Listen("OPTIONS", function()
	applyWindow()
	Map.Refresh()
end)

ns:Listen("LAYOUT_RESET", function()
	if not WorldMapFrame then return end
	ns.Safe(function()
		WorldMapFrame:SetScale(ns.db.map.scale or 1)
		WorldMapFrame:ClearAllPoints()
		WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end, "reset")
	applyWindow()
end)
