--!strict
-- Client/XP.ClientOS.lua
-- Main client controller for XP.AdminSystem.
-- Intended to be loaded by the GitHub bootstrapper.
-- Returns an Init function.

return function(context)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UserInputService = game:GetService("UserInputService")
	local TextChatService = game:GetService("TextChatService")

	local LocalPlayer = Players.LocalPlayer

	local Config = assert(context and context.Config, "XP.ClientOS requires context.Config")
	local Util = assert(context and context.Util, "XP.ClientOS requires context.Util")
	local Remotes = assert(context and context.Remotes, "XP.ClientOS requires context.Remotes")

	local gui = context.Gui or script.Parent
	assert(gui, "XP.ClientOS requires a GUI instance")

	local CMD_REQUEST = Remotes[Config.RemoteNames.CommandRequest]
	local CMD_RESPONSE = Remotes[Config.RemoteNames.CommandResponse]
	local LIST_REQUEST = Remotes[Config.RemoteNames.ListRequest]
	local LIST_RESPONSE = Remotes[Config.RemoteNames.ListResponse]
	local RANK_REQUEST = Remotes[Config.RemoteNames.RankRequest]
	local RANK_RESPONSE = Remotes[Config.RemoteNames.RankResponse]
	local ANON_REMOTE = Remotes[Config.RemoteNames.AnonSync]

	assert(CMD_REQUEST and CMD_RESPONSE and LIST_REQUEST and LIST_RESPONSE and RANK_REQUEST and RANK_RESPONSE, "XP.ClientOS: missing one or more remotes")

	-- GUI refs
	local backFrame = gui:WaitForChild("BackFrame")
	local mainFrame = backFrame:WaitForChild("MainFrame")

	local commandBox = mainFrame:WaitForChild("CommandBox") :: TextBox
	local hideBtn = mainFrame:WaitForChild("HideGuiTB") :: TextButton
	local runBtn = mainFrame:WaitForChild("RunTB") :: TextButton
	local clearBtn = mainFrame:WaitForChild("ClearCmdBoxTB") :: TextButton
	local errorLabel = mainFrame:WaitForChild("ErrorLabel") :: TextLabel

	local suggestionFrame = backFrame:WaitForChild("SuggestionList")
	local promptTemplate = suggestionFrame:WaitForChild("Prompt.Temp") :: TextButton

	local function parseUDim2(str: any): UDim2
		local text = tostring(str or "")
		local xs, xo, ys, yo = text:match("{([%d%-%.]+),%s*([%d%-%.]+)},%s*{([%d%-%.]+),%s*([%d%-%.]+)}")
		if not xs then
			warn("Failed to parse UDim2 string: " .. text)
			return UDim2.new(0, 0, 0, 0)
		end
		return UDim2.new(tonumber(xs) or 0, tonumber(xo) or 0, tonumber(ys) or 0, tonumber(yo) or 0)
	end

	local shownPos = parseUDim2(backFrame:WaitForChild("ShownPos").Value)
	local hiddenPos = parseUDim2(backFrame:WaitForChild("HiddenPos").Value)

	local COLOR_SUCCESS = Color3.fromRGB(124, 255, 101)
	local COLOR_ERROR = Color3.fromRGB(255, 107, 96)

	local guiHidden = true
	local hasInitializedRank = false
	local currentRank = 0

	local commandList = {}
	local commandMap = {}
	local currentSuggestions = {}

	local DATA_ONLY_COMMANDS = {
		time = true,
	}

	local function isDataToken(token)
		if token == nil then
			return false
		end

		local s = tostring(token):lower()
		return tonumber(token) ~= nil or s == "true" or s == "false" or s == "on" or s == "off"
	end

	local function shouldSendAsDataOnly(commandName, parsed)
		local name = tostring(commandName or ""):lower()

		if DATA_ONLY_COMMANDS[name] then
			return true
		end

		local info = commandMap[name]
		if info and info.args and #info.args > 0 and #parsed == 2 then
			local firstArg = info.args[1]
			local firstType = tostring(firstArg.Type or firstArg.type or ""):lower()

			if firstType:find("number", 1, true) or firstType:find("boolean", 1, true) then
				return isDataToken(parsed[2])
			end
		end

		return false
	end

	local function clearSuggestions()
		for _, v in ipairs(currentSuggestions) do
			if v and v.Parent then
				v:Destroy()
			end
		end
		currentSuggestions = {}
	end

	local function createSuggestion(text, insertText)
		local clone = promptTemplate:Clone()
		clone.Visible = true
		clone.Text = text
		clone.Parent = suggestionFrame

		clone.MouseButton1Click:Connect(function()
			commandBox.Text = insertText
			commandBox.CursorPosition = #insertText + 1
			clearSuggestions()
		end)

		table.insert(currentSuggestions, clone)
	end

	local function updateSuggestions(text)
		clearSuggestions()

		if text == "" then
			return
		end

		local parts = string.split(text, " ")
		local cmdPart = (parts[1] or ""):lower()

		for _, info in ipairs(commandList) do
			local cmdName = tostring(info.command or ""):lower()
			if cmdName:sub(1, #cmdPart) == cmdPart then
				createSuggestion(
					"[" .. tostring(info.command) .. "]  " .. tostring(info.description or "No description provided.") .. "  (rank " .. tostring(info.rank or 0) .. "+)",
					tostring(info.command) .. " "
				)

				if info.args and #info.args > 0 then
					createSuggestion(
						"[Args]  " .. table.concat(info.args, ",  "),
						tostring(info.command) .. " "
					)
				end
			end
		end
	end

	local function parseCommand(text)
		local args = {}
		local current = ""
		local inQuotes = false

		for i = 1, #text do
			local char = text:sub(i, i)

			if char == '"' then
				inQuotes = not inQuotes
			elseif char == " " and not inQuotes then
				if current ~= "" then
					table.insert(args, current)
					current = ""
				end
			else
				current ..= char
			end
		end

		if current ~= "" then
			table.insert(args, current)
		end

		return args
	end

	local function tweenBackFrame(targetPos)
		TweenService:Create(
			backFrame,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPos }
		):Play()
	end

	local function showGui()
		guiHidden = false
		hideBtn.Text = "-"
		tweenBackFrame(shownPos)

		task.delay(0.25, function()
			if commandBox and commandBox.Parent then
				commandBox:CaptureFocus()
			end
		end)
	end

	local function hideGui()
		guiHidden = true
		hideBtn.Text = "+"
		tweenBackFrame(hiddenPos)
	end

	local function toggleGui()
		if guiHidden then
			showGui()
		else
			hideGui()
		end
	end

	local function fireParsedCommand(parsed)
		local commandName = parsed[1]
		if not commandName then
			return
		end

		local target = parsed[2]
		local data = {}

		for i = 3, #parsed do
			table.insert(data, parsed[i])
		end

		if shouldSendAsDataOnly(commandName, parsed) then
			data = { parsed[2] }
			target = nil
		end

		if target ~= nil then
			CMD_REQUEST:FireServer(commandName, target, data)
		else
			CMD_REQUEST:FireServer(commandName, data)
		end
	end

	local colonHeld = false
	local rightShiftHeld = false

	gui.Enabled = false
	backFrame.Position = hiddenPos
	hideBtn.Text = "+"

	hideBtn.MouseButton1Click:Connect(toggleGui)

	clearBtn.MouseButton1Click:Connect(function()
		commandBox.Text = ""
		errorLabel.Text = ""
	end)

	CMD_RESPONSE.OnClientEvent:Connect(function(result)
		if result and result.success then
			errorLabel.TextColor3 = COLOR_SUCCESS
			errorLabel.Text = result.message or "Command executed successfully."
		else
			errorLabel.TextColor3 = COLOR_ERROR
			errorLabel.Text = (result and result.message) or "Command failed."
		end
	end)

	LIST_RESPONSE.OnClientEvent:Connect(function(data)
		if data and data.success then
			commandList = data.commands or {}
			commandMap = {}

			for _, info in ipairs(commandList) do
				if info and info.command then
					commandMap[tostring(info.command):lower()] = info
				end
			end
		end
	end)

	RANK_RESPONSE.OnClientEvent:Connect(function(rank)
		currentRank = tonumber(rank) or 0

		if currentRank > 0 then
			gui.Enabled = true

			if not hasInitializedRank then
				hasInitializedRank = true
				hideGui()
			end
		else
			hideGui()
			gui.Enabled = false
		end
	end)

	commandBox:GetPropertyChangedSignal("Text"):Connect(function()
		updateSuggestions(commandBox.Text)
	end)

	runBtn.MouseButton1Click:Connect(function()
		local text = commandBox.Text
		if text == "" then
			return
		end

		errorLabel.Text = "Running..."
		errorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

		local parsed = parseCommand(text)
		fireParsedCommand(parsed)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == Enum.KeyCode.Semicolon then
			colonHeld = true
		end

		if input.KeyCode == Enum.KeyCode.RightShift then
			rightShiftHeld = true
		end

		local isColonCombo = (input.KeyCode == Enum.KeyCode.RightShift and colonHeld)
			or (input.KeyCode == Enum.KeyCode.Semicolon and rightShiftHeld)

		if isColonCombo and gui.Enabled then
			toggleGui()
		end

		if not guiHidden and gui.Enabled then
			if input.KeyCode == Enum.KeyCode.Return and rightShiftHeld then
				local text = commandBox.Text
				if text ~= "" then
					errorLabel.Text = "Running..."
					errorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

					local parsed = parseCommand(text)
					fireParsedCommand(parsed)
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Semicolon then
			colonHeld = false
		end

		if input.KeyCode == Enum.KeyCode.RightShift then
			rightShiftHeld = false
		end
	end)

	local anonUsers = {} -- [userId] = true

	if ANON_REMOTE then
		ANON_REMOTE.OnClientEvent:Connect(function(userId, isAnon)
			anonUsers[userId] = isAnon or nil
		end)
	end

	TextChatService.OnIncomingMessage = function(message)
		if message.TextSource then
			local senderId = message.TextSource.UserId
			if anonUsers[senderId] then
				local props = Instance.new("TextChatMessageProperties")
				props.Text = ""
				return props
			end
		end
	end

	TextChatService.SendingMessage:Connect(function(message)
		local text = message.Text or ""
		if text:sub(1, 1) ~= (Config.Prefix or "~") then
			return
		end

		local commandText = text:sub(2):match("^%s*(.-)%s*$")
		if commandText == "" then
			return
		end

		local parsed = parseCommand(commandText)
		if parsed[1] then
			fireParsedCommand(parsed)
			errorLabel.Text = "Running: " .. commandText
			errorLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
		end
	end)

	-- Ask server for rank and list after listeners are connected
	if LIST_REQUEST then
		LIST_REQUEST:FireServer()
	end

	if RANK_REQUEST then
		RANK_REQUEST:FireServer()
	end

	errorLabel.Text = ""
	promptTemplate.Visible = false

	return {
		Show = showGui,
		Hide = hideGui,
		Toggle = toggleGui,
		RefreshSuggestions = updateSuggestions,
	}
end
