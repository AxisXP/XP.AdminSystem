local module = {}
local Workspace = game:GetService("Workspace")
module.Info = {
	Description = "Teleports the target player to some location in game.",
	Args = { "target", "pointName (string) OR x, y, z (coords, use ~ to keep current axis)" },
	Rank = 14,
}
local FRONT_ROOM_ALIASES = { "front room", "frontroom", "front" }
local function isFrontRoomQuery(query)
	local lower = query:lower()
	for _, alias in ipairs(FRONT_ROOM_ALIASES) do
		if lower == alias then return true end
	end
	return false
end
local function getFrontRoomCFrame()
	local roomsFolder = Workspace:FindFirstChild("Rooms")
	if not roomsFolder then return nil, "Rooms folder not found in Workspace." end
	local highestNum = -1
	local highestRoom = nil
	for _, model in ipairs(roomsFolder:GetChildren()) do
		if model:IsA("Model") then
			local num = tonumber(model.Name:match("^Room%-(%d+)$"))
			if num and num > highestNum then
				highestNum = num
				highestRoom = model
			end
		end
	end
	if not highestRoom then
		return nil, "No valid Room models found in Rooms folder."
	end
	if not highestRoom.PrimaryPart then
		return nil, ("Room-%d has no PrimaryPart set."):format(highestNum)
	end
	return highestRoom.PrimaryPart.CFrame, nil, highestNum
end
local function getTeleportPoints()
	local folder = Workspace:FindFirstChild("TeleportPoints")
	if not folder then return nil, "TeleportPoints folder not found in Workspace." end
	return folder, nil
end
local function findPoints(folder, query)
	local queryLower = query:lower()
	local exact = nil
	local prefixMatches = {}
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") then
			local nameLower = part.Name:lower()
			if nameLower == queryLower then
				exact = part
				break
			elseif nameLower:sub(1, #queryLower) == queryLower then
				table.insert(prefixMatches, part)
			end
		end
	end
	if exact then return { exact } end
	return prefixMatches
end

-- Parses coordinate input like "105, 63, 2673" or "~, 264, ~"
-- Returns a table: { x = value|nil, y = value|nil, z = value|nil }
-- nil means "keep current" (~), a number means set to that value
local function parseCoordinates(data)
	-- Rejoin and strip spaces around commas for flexible input
	local raw = table.concat(data, " ")

	-- Must contain at least one comma to be treated as coordinates
	if not raw:find(",") then return nil end

	local parts = {}
	for segment in raw:gmatch("[^,]+") do
		local trimmed = segment:match("^%s*(.-)%s*$")
		table.insert(parts, trimmed)
	end

	if #parts ~= 3 then return nil end

	local coords = {}
	local axes = { "x", "y", "z" }
	for i, segment in ipairs(parts) do
		if segment == "~" then
			coords[axes[i]] = nil -- keep current
		else
			local num = tonumber(segment)
			if num == nil then return nil end -- invalid, not coords
			coords[axes[i]] = num
		end
	end

	return coords
end

function module.Run(executor, targetPlayer, data, util)
	local pointName = #data > 0 and table.concat(data, " ") or ""
	if pointName == "" then
		util.respond(false, "Please provide a point name or coordinates. Usage: tp <target> <pointName|x, y, z>")
		return nil
	end
	local character = targetPlayer.Character
	if not character then
		util.respond(false, targetPlayer.Name .. " has no character loaded.")
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		util.respond(false, targetPlayer.Name .. " has no HumanoidRootPart.")
		return nil
	end

	-- Coordinate input check
	local coords = parseCoordinates(data)
	if coords then
		local current = rootPart.Position
		local newX = coords.x ~= nil and coords.x or current.X
		local newY = coords.y ~= nil and coords.y or current.Y
		local newZ = coords.z ~= nil and coords.z or current.Z

		-- Build a label for the response showing which axes were set vs kept
		local function axisLabel(val, cur, name)
			return val ~= nil and tostring(val) or ("~(" .. math.floor(cur) .. ")")
		end

		rootPart.CFrame = CFrame.new(newX, newY, newZ) * (rootPart.CFrame - rootPart.CFrame.Position)
		util.respond(true, ("Teleported %s to [%s, %s, %s]."):format(
			targetPlayer.Name,
			axisLabel(coords.x, current.X, "X"),
			axisLabel(coords.y, current.Y, "Y"),
			axisLabel(coords.z, current.Z, "Z")
			))
		return nil
	end

	-- Front Room shortcut
	if isFrontRoomQuery(pointName) then
		local cframe, err, roomNum = getFrontRoomCFrame()
		if not cframe then
			util.respond(false, err)
			return nil
		end
		rootPart.CFrame = cframe * CFrame.new(0, 5, 0)
		util.respond(true, ("Teleported %s to Front Room (Room-%d)."):format(targetPlayer.Name, roomNum))
		return nil
	end

	-- Normal TeleportPoints lookup
	local folder, folderErr = getTeleportPoints()
	if not folder then
		util.respond(false, folderErr)
		return nil
	end
	local matches = findPoints(folder, pointName)
	if #matches == 0 then
		util.respond(false, ("No teleport point found matching '%s'."):format(pointName))
		return nil
	end
	if #matches > 1 then
		local names = {}
		for _, p in ipairs(matches) do table.insert(names, p.Name) end
		util.respond(false, ("Ambiguous point name, %d matches: %s"):format(#matches, table.concat(names, ", ")))
		return nil
	end
	local point = matches[1]
	rootPart.CFrame = point.CFrame * CFrame.new(0, 5, 0)
	util.respond(true, ("Teleported %s to '%s'."):format(targetPlayer.Name, point.Name))
	return nil
end
return module
