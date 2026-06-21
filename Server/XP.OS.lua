--!strict
-- Server/XP.OS.lua
-- Main server runtime for XP.AdminSystem.
-- Intended to be loaded by the GitHub bootstrapper.
-- This file returns an Init function.

return function(context)
	local Players = game:GetService("Players")
	local DataStoreService = game:GetService("DataStoreService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local HttpService = game:GetService("HttpService")
	local TextChatService = game:GetService("TextChatService")

	local Config = assert(context and context.Config, "XP.OS requires context.Config")
	local Util = assert(context and context.Util, "XP.OS requires context.Util")
	local EventSetup = assert(context and context.EventSetup, "XP.OS requires context.EventSetup")

	local CommandsInput = context.Commands or {}
	local DiscordWebhook = context.DiscordWebhook
	local CommandModulesInput = context.CommandModules or {}

	local introStore = DataStoreService:GetDataStore(Config.DataStores.IntroSeen)
	local adminStore = DataStoreService:GetDataStore(Config.DataStores.AdminRegistry)

	local ADMIN_REGISTRY_KEY = "registry"
	local adminRegistry = { users = {} }

	-- Remotes / Bindables
	local Remotes = EventSetup.Setup({
		{Name = Config.RemoteNames.CommandRequest, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.CommandResponse, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.ListRequest, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.ListResponse, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.RankRequest, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.RankResponse, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.IntroShow, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.IntroSeen, Kind = "RemoteEvent"},
		{Name = Config.RemoteNames.AnonSync, Kind = "RemoteEvent"},
	})

	local Bindables = EventSetup.Setup({
		{Name = Config.BindableNames.AdminAdd, Kind = "BindableEvent", Parent = ServerScriptService},
		{Name = Config.BindableNames.AdminRemove, Kind = "BindableEvent", Parent = ServerScriptService},
		{Name = Config.BindableNames.GetAdmins, Kind = "BindableFunction", Parent = ServerScriptService},
	})

	local cmdRequest = Remotes[Config.RemoteNames.CommandRequest] :: RemoteEvent
	local cmdResponse = Remotes[Config.RemoteNames.CommandResponse] :: RemoteEvent
	local listRequest = Remotes[Config.RemoteNames.ListRequest] :: RemoteEvent
	local listResponse = Remotes[Config.RemoteNames.ListResponse] :: RemoteEvent
	local rankRequest = Remotes[Config.RemoteNames.RankRequest] :: RemoteEvent
	local rankResponse = Remotes[Config.RemoteNames.RankResponse] :: RemoteEvent
	local showIntroRemote = Remotes[Config.RemoteNames.IntroShow] :: RemoteEvent
	local introSeenRemote = Remotes[Config.RemoteNames.IntroSeen] :: RemoteEvent
	local anonSyncRemote = Remotes[Config.RemoteNames.AnonSync] :: RemoteEvent

	local adminAddBindable = Bindables[Config.BindableNames.AdminAdd] :: BindableEvent
	local adminRemoveBindable = Bindables[Config.BindableNames.AdminRemove] :: BindableEvent
	local getAdminsBindable = Bindables[Config.BindableNames.GetAdmins] :: BindableFunction

	local function resolveUserIdFromUsername(username: string): number?
		local ok, result = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)

		if ok and typeof(result) == "number" and result > 0 then
			return result
		end

		return nil
	end

	local function loadAdminRegistry()
		local ok, result = pcall(function()
			return adminStore:GetAsync(ADMIN_REGISTRY_KEY)
		end)

		if ok and type(result) == "table" and type(result.users) == "table" then
			adminRegistry = result
			adminRegistry.users = adminRegistry.users or {}
		else
			adminRegistry = { users = {} }
		end
	end

	local function saveAdminRegistry()
		pcall(function()
			adminStore:SetAsync(ADMIN_REGISTRY_KEY, adminRegistry)
		end)
	end

	local function setAdminEntry(userId: number, username: string?, rank: number?, source: string?)
		if not userId or userId <= 0 then
			return
		end

		adminRegistry.users[tostring(userId)] = {
			rank = tonumber(rank) or 0,
			source = source or "custom",
			username = username or "",
		}
	end

	local function removeAdminEntry(userId: number)
		if not userId or userId <= 0 then
			return
		end

		adminRegistry.users[tostring(userId)] = nil
	end

	local function syncDefaultAdmins()
		local defaultUserIds = {}

		for username, rank in pairs(Config.DefaultAdmins) do
			local userId = resolveUserIdFromUsername(username)
			if userId then
				defaultUserIds[tostring(userId)] = true
				setAdminEntry(userId, username, rank, "default")
			else
				warn("[Admin] Could not resolve default admin:", username)
			end
		end

		for userId, entry in pairs(adminRegistry.users) do
			if type(entry) == "table" and entry.source == "default" and not defaultUserIds[tostring(userId)] then
				adminRegistry.users[userId] = nil
			end
		end

		saveAdminRegistry()
	end

	local function resolveAdminIdentity(value: any): (number?, string?)
		if typeof(value) == "Instance" and value:IsA("Player") then
			return value.UserId, value.Name
		end

		if typeof(value) == "number" then
			return value, nil
		end

		if typeof(value) == "string" then
			local userId = resolveUserIdFromUsername(value)
			return userId, value
		end

		return nil, nil
	end

	local function getAdminsList()
		local result = {}

		for userId, entry in pairs(adminRegistry.users) do
			if type(entry) == "table" then
				table.insert(result, {
					UserId = tonumber(userId),
					Username = entry.username or "Unknown",
					Rank = entry.rank or 0,
					Source = entry.source or "custom",
				})
			end
		end

		table.sort(result, function(a, b)
			return (a.Rank or 0) > (b.Rank or 0)
		end)

		return result
	end

	adminAddBindable.Event:Connect(function(value, rank, source)
		local userId, username = resolveAdminIdentity(value)
		if not userId then
			warn("[Admin] AdminAdd failed: could not resolve user")
			return
		end

		setAdminEntry(userId, username, rank or 1, source or "custom")
		saveAdminRegistry()
	end)

	adminRemoveBindable.Event:Connect(function(value)
		local userId = resolveAdminIdentity(value)
		if not userId then
			warn("[Admin] AdminRemove failed: could not resolve user")
			return
		end

		removeAdminEntry(userId)
		saveAdminRegistry()
	end)

	getAdminsBindable.OnInvoke = function()
		return getAdminsList()
	end

	local function datastoreKey(userId: number)
		return "seen_" .. tostring(userId)
	end

	local function hasAlreadySeen(userId: number): boolean
		local ok, result = pcall(function()
			return introStore:GetAsync(datastoreKey(userId))
		end)

		if not ok then
			warn("[AdminIntro] DataStore read failed for", userId, ":", result)
		end

		return ok and result == true
	end

	local function markAsSeen(userId: number)
		local ok, err = pcall(function()
			introStore:SetAsync(datastoreKey(userId), true)
		end)

		if not ok then
			warn("[AdminIntro] DataStore write failed for", userId, ":", err)
		end
	end

	local function getAdminRank(player: Player?): number
		if not player then
			return 0
		end

		local entry = adminRegistry.users[tostring(player.UserId)]
		if type(entry) == "table" and entry.rank then
			return tonumber(entry.rank) or 0
		end

		return Config.DefaultAdmins[player.Name] or Config.DefaultAdmins[player.Name:lower()] or 0
	end

	local function resolvePlayerFromString(requester: Player, identifier: any)
		if not identifier or identifier == "" then
			return { requester }
		end

		local idLower = tostring(identifier):lower()

		if idLower == "me" then
			return { requester }
		end

		if idLower == "all" then
			return Players:GetPlayers()
		end

		if idLower == "others" then
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= requester then
					table.insert(list, p)
				end
			end
			return list
		end

		for _, p in ipairs(Players:GetPlayers()) do
			if p.Name:lower() == idLower then
				return { p }
			end
		end

		for _, p in ipairs(Players:GetPlayers()) do
			if p.DisplayName:lower() == idLower then
				return { p }
			end
		end

		local matches = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local un, dn = p.Name:lower(), p.DisplayName:lower()
			if un:sub(1, #idLower) == idLower or dn:sub(1, #idLower) == idLower then
				table.insert(matches, p)
			end
		end

		if #matches == 1 then
			return { matches[1] }
		end

		return nil
	end

	local function sendCmdResultToClient(requester: Player, success: boolean, message: string?, extra: any?)
		cmdResponse:FireClient(requester, {
			success = success,
			message = message or "",
			extra = extra,
		})
	end

	local function formatDataTable(data: any): string
		if type(data) ~= "table" or not next(data) then
			return "{}"
		end

		local parts = {}
		for k, v in pairs(data) do
			table.insert(parts, tostring(k) .. " = " .. tostring(v))
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end

	local function logCommandToDiscord(player: Player, commandName: string, targetPlayers: {Player}, data: any)
		if not DiscordWebhook then
			return
		end

		local webhookUrls = {}
		if Config.HasWebhooks then
			webhookUrls = Config.GetWebhookUrls()
		end

		if #webhookUrls == 0 then
			return
		end

		local timeStamp = os.date("!%Y-%m-%d %H:%M:%S")
		local targetNames = {}

		for _, p in ipairs(targetPlayers or {}) do
			table.insert(targetNames, p.Name .. " [" .. tostring(p.UserId) .. "]")
		end

		local targetsStr = #targetNames > 0 and table.concat(targetNames, ", ") or "none"

		local lines = {
			"Admin Command Executed",
			"",
			"Executor: [" .. tostring(player.UserId) .. "] / [" .. player.Name .. "]",
			"Command: [" .. commandName .. "]",
			"Target(s): [" .. targetsStr .. "]",
			"Data: " .. formatDataTable(data),
			"UTC Time: " .. timeStamp,
		}

		for _, url in ipairs(webhookUrls) do
			pcall(function()
				DiscordWebhook.send(url, lines)
			end)
		end
	end

	local commands = {} :: {[string]: {module: any, source: Instance}}

	local function registerCommandModule(mod: Instance)
		if not mod:IsA("ModuleScript") then
			return
		end

		local ok, result = pcall(require, mod)
		if not ok or type(result) ~= "table" then
			warn("Failed to require command module:", mod:GetFullName(), result)
			return
		end

		local key = mod.Name:lower()
		commands[key] = { module = result, source = mod }

		if type(result.Aliases) == "table" then
			for _, alias in ipairs(result.Aliases) do
				if type(alias) == "string" then
					commands[alias:lower()] = commands[key]
				end
			end
		end
	end

	if type(CommandsInput) == "table" then
		for _, mod in ipairs(CommandsInput) do
			if typeof(mod) == "Instance" then
				registerCommandModule(mod)
			elseif type(mod) == "table" and mod.Source and mod.Module then
				commands[tostring(mod.Source.Name):lower()] = {
					module = mod.Module,
					source = mod.Source,
				}
			end
		end
	end

	if type(CommandModulesInput) == "table" then
		for _, child in ipairs(CommandModulesInput) do
			if typeof(child) == "Instance" then
				registerCommandModule(child)
			end
		end
	end

	local function findCommandModuleByName(name: string)
		if not name or name == "" then
			return nil, "no command name provided"
		end

		name = name:lower()

		if commands[name] then
			return commands[name].module
		end

		local candidates = {}
		for _, v in pairs(commands) do
			local srcName = v.source and v.source.Name:lower() or ""
			if srcName:sub(1, #name) == name then
				candidates[srcName] = v
			end
		end

		local count = 0
		local chosen = nil
		for _, v in pairs(candidates) do
			count += 1
			chosen = v
		end

		if count == 1 and chosen then
			return chosen.module
		elseif count > 1 then
			return nil, ("ambiguous command name; %d matches"):format(count)
		end

		return nil, "command not found"
	end

	local lastSentRankByPlayer = {} :: {[Player]: number}

	local function sendRankIfChanged(player: Player)
		if not player or player.Parent ~= Players then
			return
		end

		local rank = getAdminRank(player)
		local lastRank = lastSentRankByPlayer[player]

		if lastRank ~= rank then
			lastSentRankByPlayer[player] = rank
			rankResponse:FireClient(player, rank)
		end
	end

	local function runCommand(player: Player, commandName: string, possibleTarget: any, data: any)
		commandName = Util.Trim(commandName)
		if commandName == "" then
			sendCmdResultToClient(player, false, "No command name provided.")
			return
		end

		local playerRank = getAdminRank(player)
		if playerRank == 0 then
			sendCmdResultToClient(player, false, "You are not authorised to use admin commands.")
			return
		end

		local commandModule, err = findCommandModuleByName(commandName)
		if not commandModule then
			sendCmdResultToClient(player, false, ("Command '%s' not valid: %s"):format(commandName, err))
			return
		end

		local requiredRank = (commandModule.Info and commandModule.Info.Rank) or 0
		if playerRank < requiredRank then
			sendCmdResultToClient(player, false, ("You need rank %d to use '%s'. Your rank: %d."):format(requiredRank, commandName, playerRank))
			return
		end

		local targetPlayers = {}
		if possibleTarget ~= nil then
			local allowOfflineTarget = commandModule.Info and commandModule.Info.AllowOfflineTarget == true

			if allowOfflineTarget then
				targetPlayers = { possibleTarget }
			else
				local resolved = resolvePlayerFromString(player, possibleTarget)
				if not resolved or #resolved == 0 then
					sendCmdResultToClient(player, false, ("Target '%s' not found."):format(tostring(possibleTarget)))
					return
				end
				targetPlayers = resolved
			end
		else
			targetPlayers = { player }
		end

		local runner = commandModule.Run or commandModule.Execute or commandModule.run or commandModule.execute
		if not runner or type(runner) ~= "function" then
			sendCmdResultToClient(player, false, ("Command module '%s' does not expose a Run/Execute function."):format(commandName))
			return
		end

		local util = {
			respond = function(success, message, extra)
				sendCmdResultToClient(player, success, message, extra)
			end,
			resolvePlayer = resolvePlayerFromString,
			playersService = Players,
			adminsTable = adminRegistry.users,
			defaultAdmins = Config.DefaultAdmins,
		}

		local ok, resultOrErr
		for _, targetPlayer in ipairs(targetPlayers) do
			ok, resultOrErr = pcall(function()
				return runner(player, targetPlayer, data or {}, util)
			end)

			if not ok then
				warn(("Admin command '%s' errored on target %s: %s"):format(commandName, targetPlayer.Name, resultOrErr))
				sendCmdResultToClient(player, false, ("Command crashed on target %s."):format(targetPlayer.Name))
				return
			end
		end

		logCommandToDiscord(player, commandName, targetPlayers, data)

		if resultOrErr ~= nil then
			if type(resultOrErr) == "table" then
				sendCmdResultToClient(player, resultOrErr.success == true, resultOrErr.message or "", resultOrErr.extra)
			else
				sendCmdResultToClient(player, (resultOrErr == true), tostring(resultOrErr))
			end
		else
			sendCmdResultToClient(player, true, ("Command '%s' executed."):format(commandName))
		end
	end

	cmdRequest.OnServerEvent:Connect(function(player, ...)
		local args = { ... }
		local commandName = args[1]
		local possibleTarget = args[2]
		local data = args[3]

		if type(possibleTarget) == "table" and data == nil then
			data = possibleTarget
			possibleTarget = nil
		end

		runCommand(player, tostring(commandName or ""), possibleTarget, data)
	end)

	listRequest.OnServerEvent:Connect(function(player)
		if getAdminRank(player) <= 0 then
			listResponse:FireClient(player, {
				success = false,
				message = "You are not authorised to request the admin command list.",
			})
			return
		end

		local list = {}
		local seenSources = {}

		for _, entry in pairs(commands) do
			local src = entry.source
			if src and not seenSources[src] then
				local module = entry.module
				local info = module.Info or {}
				table.insert(list, {
					command = src.Name,
					description = info.Description or "No description provided.",
					args = info.Args or {},
					notes = info.Notes or nil,
					rank = info.Rank or 0,
				})
				seenSources[src] = true
			end
		end

		listResponse:FireClient(player, {
			success = true,
			message = "Command list sent.",
			commands = list,
		})
	end)

	rankRequest.OnServerEvent:Connect(function(player)
		local rank = getAdminRank(player)
		rankResponse:FireClient(player, rank)
		lastSentRankByPlayer[player] = rank
	end)

	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		rankResponse:FireClient(player, getAdminRank(player))
	end)

	Players.PlayerAdded:Connect(function(player)
		local rank = getAdminRank(player)
		if rank <= 0 then
			return
		end

		if hasAlreadySeen(player.UserId) then
			return
		end

		task.wait(3)

		if not Players:FindFirstChild(player.Name) then
			return
		end

		showIntroRemote:FireClient(player, rank)
	end)

	introSeenRemote.OnServerEvent:Connect(function(player)
		local rank = getAdminRank(player)
		if rank <= 0 then
			return
		end

		markAsSeen(player.UserId)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			while player.Parent == Players do
				task.wait(2)
				sendRankIfChanged(player)
				task.wait(2)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSentRankByPlayer[player] = nil
	end)

	-- Optional: sync anon state remotely later if you want it to be driven from commands/modules.
	anonSyncRemote.OnServerEvent:Connect(function(player, userId, isAnon)
		if getAdminRank(player) <= 0 then
			return
		end

		-- This remote is intentionally left as a hook for future modules.
		-- You can extend this with server-side validation when you add anon commands.
	end)

	loadAdminRegistry()
	syncDefaultAdmins()

	print("AdminCommandServer initialized. Commands loaded:", (function()
		local n = 0
		for _ in pairs(commands) do
			n += 1
		end
		return n
	end)())
end
