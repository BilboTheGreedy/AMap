local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Mini = {}
ns.Mini = Mini

local info, border, handle
local hooked = {}
local hiddenSet = {}

local GROUPS = {
	hideZoom = { "MinimapZoomIn", "MinimapZoomOut", "Minimap.ZoomIn", "Minimap.ZoomOut" },
	hideMapButton = { "MiniMapWorldMapButton" },
	hideClock = { "TimeManagerClockButton", "GameTimeFrame" },
	hideTracking = { "MiniMapTracking", "MiniMapTrackingFrame", "MinimapCluster.Tracking" },
}

local ROUND_ART = { "MinimapBorder", "MinimapBorderTop", "MinimapCompassTexture", "MinimapNorthTag", "MinimapCluster.BorderTop" }

local function resolve(path)
	local obj = _G
	for part in path:gmatch("[^.]+") do
		if type(obj) ~= "table" then return nil end
		obj = obj[part]
	end
	if type(obj) ~= "table" or obj == _G then return nil end
	return obj
end

local function setHidden(path, hide)
	local f = resolve(path)
	if not f or not f.Hide then return false end
	if hide then
		hiddenSet[f] = true
		f:Hide()
		if not hooked[f] and f.HookScript then
			hooked[f] = true
			pcall(f.HookScript, f, "OnShow", function(self)
				if hiddenSet[self] then self:Hide() end
			end)
		end
	elseif hiddenSet[f] then
		hiddenSet[f] = nil
		f:Show()
	end
	return true
end

function Mini.Zoom(delta)
	local zoom = ns.Num(Minimap:GetZoom()) or 0
	local levels = ns.Num(Minimap.GetZoomLevels and Minimap:GetZoomLevels()) or 6
	local target = math.max(0, math.min(levels - 1, zoom + (delta > 0 and 1 or -1)))
	if target ~= zoom then Minimap:SetZoom(target) end
	return target
end

local function cluster()
	return MinimapCluster or Minimap
end

local function applyPlacement()
	local db = ns.db.minimap
	return ns.Safe(function()
		local c = cluster()
		c:SetScale(db.scale or 1)
		if db.pos and db.pos[1] then
			c:SetMovable(true)
			c:ClearAllPoints()
			c:SetPoint(db.pos[1], UIParent, db.pos[2] or db.pos[1], db.pos[3] or 0, db.pos[4] or 0)
		end
	end)
end

local function build()
	info = CreateFrame("Frame", "AMapMinimapInfo", Minimap)
	info:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
	info:SetSize(140, 28)
	info.coords = UI.Text(info, "GameFontHighlightSmall", "CENTER")
	info.coords:SetPoint("TOP", 0, 0)
	info.zone = UI.Text(info, "GameFontNormalSmall", "CENTER", C.accent)
	info.zone:SetPoint("TOP", info.coords, "BOTTOM", 0, -1)

	border = CreateFrame("Frame", nil, Minimap)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	UI.Border(border, { 0.35, 0.36, 0.42, 1 })
	border:Hide()

	handle = CreateFrame("Button", nil, Minimap)
	handle:SetAllPoints(Minimap)
	handle:SetFrameStrata("HIGH")
	UI.Fill(handle, { 1, 0.82, 0, 0.18 })
	handle.label = UI.Text(handle, "GameFontNormalSmall", "CENTER", C.accent)
	handle.label:SetPoint("CENTER")
	handle.label:SetText("drag")
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function(self)
		if InCombatLockdown and InCombatLockdown() then return end
		local c = cluster()
		c:SetMovable(true)
		c:StartMoving()
		self.moving = true
	end)
	handle:SetScript("OnDragStop", function(self)
		if not self.moving then return end
		self.moving = nil
		local c = cluster()
		c:StopMovingOrSizing()
		local point, _, rel, x, y = c:GetPoint(1)
		if point then ns.db.minimap.pos = { point, rel or point, x or 0, y or 0 } end
	end)
	handle:Hide()

	Minimap:EnableMouseWheel(true)
	local function wheel(_, delta)
		if ns.db.minimap.wheel then Mini.Zoom(delta) end
	end
	if Minimap:GetScript("OnMouseWheel") and Minimap.HookScript then
		Minimap:HookScript("OnMouseWheel", wheel)
	else
		Minimap:SetScript("OnMouseWheel", wheel)
	end
end

function Mini.Shape()
	return ns.db and ns.db.minimap.square and "SQUARE" or "ROUND"
end

function Mini.Apply()
	if not Minimap then return end
	if not info then build() end
	local db = ns.db.minimap
	for key, paths in pairs(GROUPS) do
		for _, path in ipairs(paths) do setHidden(path, db[key]) end
	end
	if db.square then
		if Minimap.SetMaskTexture then Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8") end
		for _, path in ipairs(ROUND_ART) do setHidden(path, true) end
		border:Show()
		Mini.squared = true
	elseif Mini.squared then
		if Minimap.SetMaskTexture then Minimap:SetMaskTexture("Textures\\MinimapMask") end
		for _, path in ipairs(ROUND_ART) do setHidden(path, false) end
		border:Hide()
		Mini.squared = nil
	end
	if db.square or not GetMinimapShape or Mini.ownShape then
		Mini.ownShape = true
		GetMinimapShape = Mini.Shape
	end
	info:SetShown(db.coords or db.zone)
	info.coords:SetShown(db.coords)
	info.zone:SetShown(db.zone)
	handle:SetShown(not db.locked)
	applyPlacement()
	Mini.Update()
end

function Mini.Update()
	if not info or not info:IsShown() then return end
	local db = ns.db.minimap
	if db.coords then
		local x, y = ns.UnitPos(ns.PlayerMap(), "player")
		info.coords:SetText(x and (ns.Coord(x) .. ", " .. ns.Coord(y)) or "")
	end
	if db.zone then
		local text = GetMinimapZoneText and GetMinimapZoneText() or ""
		if ns.IsSecret(text) then text = "" end
		info.zone:SetText(text or "")
	end
end

ns:Listen("LOGIN", function()
	Mini.Apply()
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.2 then return end
		elapsed = 0
		Mini.Update()
	end)
end)

ns:On("PLAYER_ENTERING_WORLD", function()
	if ns.db and info then applyPlacement() end
end)

ns:Listen("OPTIONS", Mini.Apply)

ns:Listen("LAYOUT_RESET", function()
	ns.Safe(function()
		local c = cluster()
		c:SetScale(1)
		if c ~= Minimap then
			c:ClearAllPoints()
			c:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
		end
	end)
end)
