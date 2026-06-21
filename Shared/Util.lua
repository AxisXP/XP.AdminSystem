--!strict
-- Shared/Util.lua
-- Small helpers used by both server and client code.

local Util = {}

function Util.Trim(value: any): string
	return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

function Util.IsBlank(value: any): boolean
	return Util.Trim(value) == ""
end

function Util.Lower(value: any): string
	return string.lower(tostring(value or ""))
end

function Util.StartsWith(value: any, prefix: any): boolean
	local s = tostring(value or "")
	local p = tostring(prefix or "")
	if p == "" then
		return true
	end
	return s:sub(1, #p) == p
end

function Util.Split(value: any, separator: string?): {string}
	local text = tostring(value or "")
	local sep = separator or "%s+"
	local result = {}

	if sep == "%s+" then
		for token in text:gmatch("%S+") do
			table.insert(result, token)
		end
		return result
	end

	for part in string.gmatch(text, "([^" .. sep .. "]+)") do
		table.insert(result, part)
	end

	return result
end

function Util.TableContains<T>(array: {T}, item: T): boolean
	for _, value in ipairs(array) do
		if value == item then
			return true
		end
	end
	return false
end

function Util.ShallowCopy<T>(source: { [any]: T }): { [any]: T }
	local copy = {}
	for k, v in pairs(source) do
		copy[k] = v
	end
	return copy
end

function Util.DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for k, v in pairs(value) do
		copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
	end
	return copy
end

function Util.SafeCall<T>(fn: () -> T): (boolean, T?)
	local ok, result = pcall(fn)
	if ok then
		return true, result
	end
	return false, nil
end

function Util.SafeCallWithError<T>(fn: () -> T): (boolean, T?, any)
	local ok, result = pcall(fn)
	if ok then
		return true, result, nil
	end
	return false, nil, result
end

function Util.CountKeys(tbl: {[any]: any}): number
	local count = 0
	for _ in pairs(tbl) do
		count += 1
	end
	return count
end

function Util.Merge(a: {[any]: any}, b: {[any]: any}): {[any]: any}
	local out = Util.ShallowCopy(a)
	for k, v in pairs(b) do
		out[k] = v
	end
	return out
end

function Util.NormalizeName(value: any): string
	return Util.Lower(Util.Trim(value))
end

function Util.SanitizeCommandName(value: any): string
	local name = Util.NormalizeName(value)
	name = name:gsub("%s+", "")
	return name
end

function Util.Quote(value: any): string
	return '"' .. tostring(value or "") .. '"'
end

return Util
