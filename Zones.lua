local _, ns = ...

ns.ZONES = {
	[1411] = { 1, 10, "Horde" },
	[1412] = { 1, 10, "Horde" },
	[1413] = { 10, 25, "Horde" },
	[1416] = { 30, 40 },
	[1417] = { 30, 40 },
	[1418] = { 35, 45 },
	[1419] = { 45, 55 },
	[1420] = { 1, 10, "Horde" },
	[1421] = { 10, 20, "Horde" },
	[1422] = { 51, 58 },
	[1423] = { 53, 60 },
	[1424] = { 20, 30 },
	[1425] = { 40, 50 },
	[1426] = { 1, 10, "Alliance" },
	[1427] = { 43, 50 },
	[1428] = { 50, 58 },
	[1429] = { 1, 10, "Alliance" },
	[1430] = { 55, 60 },
	[1431] = { 18, 30, "Alliance" },
	[1432] = { 10, 20, "Alliance" },
	[1433] = { 15, 25, "Alliance" },
	[1434] = { 30, 45 },
	[1435] = { 35, 45 },
	[1436] = { 10, 20, "Alliance" },
	[1437] = { 20, 30, "Alliance" },
	[1438] = { 1, 10, "Alliance" },
	[1439] = { 10, 20, "Alliance" },
	[1440] = { 18, 30 },
	[1441] = { 25, 35 },
	[1442] = { 15, 27 },
	[1443] = { 30, 40 },
	[1444] = { 40, 50 },
	[1445] = { 35, 45 },
	[1446] = { 40, 50 },
	[1447] = { 45, 55 },
	[1448] = { 48, 55 },
	[1449] = { 48, 55 },
	[1450] = { 55, 60 },
	[1451] = { 55, 60 },
	[1452] = { 53, 60 },
	[1453] = { nil, nil, "Alliance" },
	[1454] = { nil, nil, "Horde" },
	[1455] = { nil, nil, "Alliance" },
	[1456] = { nil, nil, "Horde" },
	[1457] = { nil, nil, "Alliance" },
	[1458] = { nil, nil, "Horde" },
}

function ns.ZoneInfo(map)
	local z = ns.ZONES[map]
	if not z then return nil end
	local parts = {}
	local r, g, b = 0.9, 0.9, 0.92
	if z[1] then
		parts[#parts + 1] = z[1] .. "-" .. z[2]
		local level = ns.Num(UnitLevel and UnitLevel("player")) or 60
		if level < z[1] - 2 then
			r, g, b = 1, 0.25, 0.2
		elseif level < z[1] then
			r, g, b = 1, 0.55, 0.25
		elseif level <= z[2] then
			r, g, b = 1, 0.82, 0
		elseif level <= z[2] + 5 then
			r, g, b = 0.3, 0.8, 0.3
		else
			r, g, b = 0.6, 0.6, 0.6
		end
	end
	if z[3] then
		local label = z[3] == "Horde" and FACTION_HORDE or z[3] == "Alliance" and FACTION_ALLIANCE
		parts[#parts + 1] = type(label) == "string" and label or z[3]
	end
	return table.concat(parts, "  "), r, g, b
end

function ns.MapInfo(map)
	if type(map) ~= "number" or not C_Map or not C_Map.GetMapInfo then return nil end
	local ok, info = pcall(C_Map.GetMapInfo, map)
	if not ok or type(info) ~= "table" then return nil end
	return info
end

function ns.MapName(map)
	local info = ns.MapInfo(map)
	local name = info and info.name
	if ns.IsSecret(name) or type(name) ~= "string" then return "" end
	return name
end
