local M = {}

---@class Cache
Cache = {}

--- Sets a value in the cache for a given key
---@param key string
---@param value function|table|string
---@return nil
function M.set(key, value)
	if type(value) == "function" then
		value = value()
	end
	if Cache[key] ~= nil then
		Cache[key] = nil
		Cache[key] = value
	else
		Cache[key] = value
	end
end

--- Gets a value from the cache for a given key
---@param key string
---@return table|nil
function M.get(key)
	return Cache[key]
end

--- Clears the entire cache
---@return nil
function M.clean()
	Cache = {}
end

return M
