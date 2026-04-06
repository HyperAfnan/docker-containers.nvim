local M = {}

---@class Cache
Cache = {}

---@param key string
---@param value table|string
---@return nil
function M.set(key, value)
	Cache[key] = value
end

---@param key string
---@return table|nil
function M.get(key)
	return Cache[key]
end

return M
