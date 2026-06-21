--!strict
-- XP.Config.lua
-- Shared configuration for the admin system.

local HttpService = game:GetService("HttpService")

local Config = {}

Config.SystemName = "XP.AdminSystem"

Config.Version = "1.0.0"
Config.Prefix = "~"

Config.DataStores = {
	IntroSeen = "AdminIntroSeen_v1.03",
	AdminRegistry = "AdminRegistry_v1",
}

Config.RemoteNames = {
	CommandRequest = "Admin.XP_CMD.Request",
	CommandResponse = "Admin.XP_CMD.Response",
	ListRequest = "Admin.XP_List.Request",
	ListResponse = "Admin.XP_List.Response",
	RankRequest = "Admin.XP_Rank.Request",
	RankResponse = "Admin.XP_Rank.Response",

	IntroShow = "Admin.Intro.Show",
	IntroSeen = "Admin.Intro.Seen",
	AnonSync = "Admin.Anon.Sync",
}

Config.BindableNames = {
	AdminAdd = "AdminAdd",
	AdminRemove = "AdminRemove",
	GetAdmins = "GetAdmins",
}

Config.DefaultAdmins = {
	["andrijkoza"] = 64,
	["Agent_kot2329"] = 35,
	["7timeover"] = 35,
	["Player1"] = 60,
	["Player2"] = 35,
	["hazan81"] = 10,
	["Lexa323228"] = 19,
	["pottintt"] = 60,
	["zuiopler3"] = 30,
	["Michalmey1"] = 21,
	["dp224459"] = 19,
}

Config.CommandDataOnly = {
	time = true,
}

Config.Secrets = {
	Webhook1 = "AdminLogWebhook1",
	Webhook2 = "AdminLogWebhook2",
}

function Config.GetSecret(name: string): string?
	local ok, value = pcall(function()
		return HttpService:GetSecret(name)
	end)

	if ok and typeof(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

function Config.GetWebhookUrls(): {string}
	local urls = {}

	local w1 = Config.GetSecret(Config.Secrets.Webhook1)
	if w1 then
		table.insert(urls, w1)
	end

	local w2 = Config.GetSecret(Config.Secrets.Webhook2)
	if w2 then
		table.insert(urls, w2)
	end

	return urls
end

function Config.HasWebhooks(): boolean
	return #Config.GetWebhookUrls() > 0
end

return Config
