-- XP.AdminSystem - AdminList Client Renderer
-- Rewritten for XP modular system

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- XP-style remote (matches your system naming)
local Remote = ReplicatedStorage:WaitForChild("Admin.Anon.Sync") 
-- NOTE: you should ideally rename this to "Admin.XP_List.Push"
-- but I’m adapting to your current structure

local adminGui = playerGui:WaitForChild("AdminGUI")
local listTemplate = adminGui:WaitForChild("ModularListFrame.Temp")

listTemplate.Visible = false

local activeLists = {}

local ROW_SIZE = UDim2.new(0, 363, 0, 30)
local ROW_X = 0.02
local ROW_START_Y = 15
local ROW_STEP_Y = 45

-------------------------------------------------------
-- helpers
-------------------------------------------------------

local function getListCount()
	local count = 0
	for _, frame in pairs(activeLists) do
		if frame and frame.Parent then
			count += 1
		end
	end
	return count
end

local function clearRows(scrollingFrame)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			if child.Name ~= "Tittle.Temp"
				and child.Name ~= "Tittle+Info.Temp" then
				child:Destroy()
			end
		end
	end
end

local function setText(root, name, value)
	local obj = root:FindFirstChild(name, true)
	if obj and obj:IsA("TextLabel") then
		obj.Text = tostring(value or "")
	end
end

local function normalize(entry)
	if type(entry) ~= "table" then
		return tostring(entry), ""
	end

	return tostring(entry[1] or entry.Title or ""), tostring(entry[2] or entry.Info or "")
end

-------------------------------------------------------
-- row creation
-------------------------------------------------------

local function makeRow(scrollingFrame, entry, mode, index)
	local templateName = (mode == "Tittle+Info") and "Tittle+Info.Temp" or "Tittle.Temp"
	local template = scrollingFrame:FindFirstChild(templateName)

	if not template then return end

	local row = template:Clone()
	row.Visible = true
	row.Parent = scrollingFrame
	row.Size = ROW_SIZE
	row.Position = UDim2.new(ROW_X, 0, 0, ROW_START_Y + ((index - 1) * ROW_STEP_Y))

	if mode == "Tittle+Info" then
		local title, info = normalize(entry)
		setText(row, "TittleTL", title)
		setText(row, "InfoTL", info)
	else
		setText(row, "TittleTL", entry)
	end

	return row
end

local function updateCanvas(scrollingFrame, count)
	local extra = math.max(0, count - 3)
	scrollingFrame.CanvasSize = UDim2.new(0, 0, extra * 0.275, 0)
end

-------------------------------------------------------
-- list management
-------------------------------------------------------

local function closeList(name, notifyServer)
	local frame = activeLists[name]
	if not frame then return end

	activeLists[name] = nil

	if notifyServer then
		-- optional hook for server cleanup
	end

	frame:Destroy()
end

local function createOrUpdate(payload)
	if type(payload) ~= "table" then return end

	local name = tostring(payload.Name or "DataList")
	local mode = tostring(payload.Mode or "Tittle")
	local data = payload.Data or {}

	local frame = activeLists[name]

	if not frame then
		frame = listTemplate:Clone()
		frame.Name = name
		frame.Visible = true
		frame.Parent = listTemplate.Parent
		activeLists[name] = frame

		local closeBtn = frame:FindFirstChild("CloseIB", true)
		if closeBtn then
			closeBtn.MouseButton1Click:Connect(function()
				closeList(name, true)
			end)
		end
	end

	local title = frame:FindFirstChild("Task.Name", true)
	if title and title:IsA("TextLabel") then
		title.Text = "System." .. name
	end

	local main = frame:FindFirstChild("MainFrame", true)
	local scroll = main and main:FindFirstChild("ScrollingFrame", true)
	if not scroll then return end

	clearRows(scroll)

	for i, entry in ipairs(data) do
		makeRow(scroll, entry, mode, i)
	end

	updateCanvas(scroll, #data)
end

-------------------------------------------------------
-- remote handler
-------------------------------------------------------

Remote.OnClientEvent:Connect(function(action, payload)
	if action == "UpsertList" or action == "UpdateList" then
		createOrUpdate(payload)

	elseif action == "CloseList" then
		closeList(tostring(payload), false)
	end
end)
