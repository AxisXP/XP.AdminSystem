--!strict
-- Server/XP.EventSetup.lua
-- Centralized creator/getter for RemoteEvents, RemoteFunctions, BindableEvents, and BindableFunctions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventSetup = {}

export type Kind = "RemoteEvent" | "RemoteFunction" | "BindableEvent" | "BindableFunction"

export type Spec = {
	Name: string,
	Kind: Kind,
	Parent: Instance?,
	Strict: boolean?,
}

local DEFAULT_REMOTE_PARENT = ReplicatedStorage
local DEFAULT_BINDABLE_PARENT = ServerScriptService

local cache: {[string]: Instance} = {}

local function getDefaultParent(kind: Kind): Instance
	if kind == "RemoteEvent" or kind == "RemoteFunction" then
		return DEFAULT_REMOTE_PARENT
	end
	return DEFAULT_BINDABLE_PARENT
end

local function createInstance(name: string, kind: Kind, parent: Instance): Instance
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

local function findMatchingChild(parent: Instance, name: string): Instance?
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end

	-- Optional fallback if the object was placed somewhere under the folder
	return parent:FindFirstChild(name, true)
end

function EventSetup.Get(name: string): Instance?
	return cache[name]
end

function EventSetup.GetOrCreate(spec: Spec): Instance
	assert(type(spec) == "table", "EventSetup.GetOrCreate expects a spec table")
	assert(type(spec.Name) == "string" and spec.Name ~= "", "EventSetup: spec.Name must be a non-empty string")
	assert(type(spec.Kind) == "string", "EventSetup: spec.Kind must be a string")

	local name = spec.Name
	local kind = spec.Kind :: Kind
	local strict = spec.Strict == true
	local parent = spec.Parent or getDefaultParent(kind)

	-- Cache first
	local cached = cache[name]
	if cached and cached.Parent ~= nil then
		if cached.ClassName == kind then
			return cached
		end

		if strict then
			error(("[EventSetup] '%s' exists in cache as %s, expected %s"):format(name, cached.ClassName, kind))
		end
	end

	-- Direct child
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName == kind then
			cache[name] = existing
			return existing
		end

		if strict then
			error(("[EventSetup] '%s' exists under %s but is %s, expected %s"):format(
				name,
				parent:GetFullName(),
				existing.ClassName,
				kind
			))
		end

		warn(("[EventSetup] '%s' exists but is %s, expected %s. Reusing existing instance."):format(
			name,
			existing.ClassName,
			kind
		))
		cache[name] = existing
		return existing
	end

	-- Deep search fallback
	local deep = findMatchingChild(parent, name)
	if deep then
		if deep.ClassName == kind then
			cache[name] = deep
			return deep
		end

		if strict then
			error(("[EventSetup] '%s' found deeper under %s but is %s, expected %s"):format(
				name,
				parent:GetFullName(),
				deep.ClassName,
				kind
			))
		end

		warn(("[EventSetup] '%s' found deeper but class mismatch (%s vs %s). Reusing existing instance."):format(
			name,
			deep.ClassName,
			kind
		))
		cache[name] = deep
		return deep
	end

	-- Create new
	local created = createInstance(name, kind, parent)
	cache[name] = created
	return created
end

function EventSetup.Setup(specs: {Spec}): {[string]: Instance}
	assert(type(specs) == "table", "EventSetup.Setup expects an array of specs")

	local result: {[string]: Instance} = {}

	for _, spec in ipairs(specs) do
		local inst = EventSetup.GetOrCreate(spec)
		result[spec.Name] = inst
	end

	return result
end

function EventSetup.SetupRemote(name: string, parent: Instance?, kind: Kind?): Instance
	return EventSetup.GetOrCreate({
		Name = name,
		Kind = kind or "RemoteEvent",
		Parent = parent or DEFAULT_REMOTE_PARENT,
	})
end

function EventSetup.SetupBindable(name: string, parent: Instance?, kind: Kind?): Instance
	return EventSetup.GetOrCreate({
		Name = name,
		Kind = kind or "BindableEvent",
		Parent = parent or DEFAULT_BINDABLE_PARENT,
	})
end

function EventSetup.ClearCache()
	table.clear(cache)
end

return EventSetup
