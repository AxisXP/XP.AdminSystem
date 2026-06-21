--!strict
-- XP.EventSetup.lua
-- Centralized creator/registry for Remotes and Bindables.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventSetup = {}

export type Kind = "RemoteEvent" | "RemoteFunction" | "BindableEvent" | "BindableFunction"

export type Spec = {
	Name: string,
	Kind: Kind,

	-- Optional parent override.
	-- Remotes usually go in ReplicatedStorage.
	-- Bindables usually go in ServerScriptService.
	Parent: Instance?,

	-- If true, returns existing instance only if it matches Kind.
	-- If false, it will still try to reuse by name but warn on mismatches.
	Strict: boolean?,
}

local DEFAULT_REMOTE_PARENT = ReplicatedStorage
local DEFAULT_BINDABLE_PARENT = ServerScriptService

local cache: {[string]: Instance} = {}

local function getDefaultParent(kind: Kind): Instance
	if kind == "RemoteEvent" or kind == "RemoteFunction" then
		return DEFAULT_REMOTE_PARENT
	end
 վերադարձ DEFAULT_BINDABLE_PARENT
end

local function createByKind(name: string, kind: Kind, parent: Instance): Instance
	local inst: Instance

	if kind == "RemoteEvent" then
		inst = Instance.new("RemoteEvent")
	elseif kind == "RemoteFunction" then
		inst = Instance.new("RemoteFunction")
	elseif kind == "BindableEvent" then
		inst = Instance.new("BindableEvent")
	elseif kind == "BindableFunction" then
		inst = Instance.new("BindableFunction")
	else
		error(("Unsupported event kind: %s"):format(tostring(kind)))
	end

	inst.Name = name
	inst.Parent = parent
	return inst
end

local function findChildDeep(parent: Instance, name: string): Instance?
	local direct = parent:FindFirstChild(name)
	if direct then
		return direct
	end
	return parent:FindFirstChild(name, true)
end

function EventSetup.Get(name: string): Instance?
	return cache[name]
end

function EventSetup.GetOrCreate(spec: Spec): Instance
	assert(type(spec) == "table", "EventSetup.GetOrCreate(spec) expects a table")
	assert(type(spec.Name) == "string" and spec.Name ~= "", "EventSetup: spec.Name must be a non-empty string")
	assert(type(spec.Kind) == "string", "EventSetup: spec.Kind must be a string")

	local name = spec.Name
	local kind = spec.Kind
	local strict = spec.Strict == true
	local parent = spec.Parent or getDefaultParent(kind)

	-- Cache hit
	local cached = cache[name]
	if cached and cached.Parent ~= nil then
		if cached.ClassName == kind then
			return cached
		end

		if strict then
			error(("[EventSetup] Cached instance '%s' exists but is '%s', expected '%s'"):format(
				name,
				cached.ClassName,
				kind
			))
		end
	end

	-- Direct child first
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName == kind then
			cache[name] = existing
			return existing
		end

		if strict then
			error(("[EventSetup] '%s' exists under %s but is '%s', expected '%s'"):format(
				name,
				parent:GetFullName(),
				existing.ClassName,
				kind
			))
		end

		warn(("[EventSetup] '%s' exists but is '%s', expected '%s'. Reusing the existing instance anyway."):format(
			name,
			existing.ClassName,
			kind
		))
		cache[name] = existing
		return existing
	end

	-- Fallback deep search
	local deep = findChildDeep(parent, name)
	if deep then
		if deep.ClassName == kind then
			cache[name] = deep
			return deep
		end

		if strict then
			error(("[EventSetup] Deep found '%s' but class mismatch: '%s' vs '%s'"):format(
				name,
				deep.ClassName,
				kind
			))
		end

		warn(("[EventSetup] Deep found '%s' but class mismatch. Reusing existing instance."):format(name))
		cache[name] = deep
		return deep
	end

	-- Create new
	local created = createByKind(name, kind, parent)
	cache[name] = created
	return created
end

function EventSetup.Setup(specs: {Spec}): {[string]: Instance}
	assert(type(specs) == "table", "EventSetup.Setup(specs) expects an array of specs")

	local result: {[string]: Instance} = {}

	for _, spec in ipairs(specs) do
		local inst = EventSetup.GetOrCreate(spec)
		result[spec.Name] = inst
	end

	return result
end

function EventSetup.SetupFolder(folderName: string, specs: {Spec}, parent: Instance?): Folder
	assert(type(folderName) == "string" and folderName ~= "", "EventSetup.SetupFolder(folderName, specs) requires a folder name")

	local rootParent = parent or ReplicatedStorage
	local folder = rootParent:FindFirstChild(folderName)

	if folder and not folder:IsA("Folder") then
		error(("[EventSetup] '%s' exists under %s but is not a Folder"):format(folderName, rootParent:GetFullName()))
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = rootParent
	end

	for _, spec in ipairs(specs) do
		spec.Parent = spec.Parent or folder
		local inst = EventSetup.GetOrCreate(spec)
		result[spec.Name] = inst
	end

	return folder
end

function EventSetup.ClearCache()
	table.clear(cache)
end

return EventSetup
