local M = {}

---@type integer
M.ns_id = vim.api.nvim_create_namespace("docker-containers.nvim")

M.SECTION = "DockerSection"
M.PROJECT = "DockerProject"
M.CONTAINER = "DockerContainer"
M.IMAGE = "DockerImage"
M.VOLUME = "DockerVolume"
M.NETWORK = "DockerNetwork"
M.ICON = "DockerIcon"
M.COUNT = "DockerCount"
M.STATUS_RUNNING = "DockerStatusRunning"
M.STATUS_STOPPED = "DockerStatusStopped"

---@param n integer
---@param chars integer?
local function dec_to_hex(n, chars)
	chars = chars or 6
	local hex = string.format("%0" .. chars .. "x", n)
	while #hex < chars do
		hex = "0" .. hex
	end
	return hex
end

---@param name string
local get_hl_by_name = function(name)
	if vim.api.nvim_get_hl then
		local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
		---@diagnostic disable-next-line: inject-field
		hl.foreground = hl.fg
		---@diagnostic disable-next-line: inject-field
		hl.background = hl.bg
		return hl
	end
	---@diagnostic disable-next-line: deprecated
	return vim.api.nvim_get_hl_by_name(name, true)
end

---If the given highlight group is not defined, define it.
---@param hl_group_name string The name of the highlight group.
---@param link_to_if_exists string[] A list of highlight groups to link to, in order of priority. The first one that exists will be used.
---@param background string? The background color to use, in hex, if the highlight group is not defined and it is not linked to another group.
---@param foreground string? The foreground color to use, in hex, if the highlight group is not defined and it is not linked to another group.
---@param gui string? The gui to use, if the highlight group is not defined and it is not linked to another group.
---@return table hlgroups The highlight group values.
M.create_highlight_group = function(hl_group_name, link_to_if_exists, background, foreground, gui)
	local success, hl_group = pcall(get_hl_by_name, hl_group_name)
	if not success or not hl_group.foreground or not hl_group.background then
		for _, link_to in ipairs(link_to_if_exists) do
			success, hl_group = pcall(get_hl_by_name, link_to)
			if success then
				local new_group_has_settings = background or foreground or gui
				local link_to_has_settings = hl_group.foreground or hl_group.background
				if link_to_has_settings or not new_group_has_settings then
					vim.cmd("highlight default link " .. hl_group_name .. " " .. link_to)
					return hl_group
				end
			end
		end

		if type(background) == "number" then
			background = dec_to_hex(background)
		end
		if type(foreground) == "number" then
			foreground = dec_to_hex(foreground)
		end

		local cmd = "highlight default " .. hl_group_name
		if background then
			cmd = cmd .. " guibg=#" .. background
		end
		if foreground then
			cmd = cmd .. " guifg=#" .. foreground
		else
			cmd = cmd .. " guifg=NONE"
		end
		if gui then
			cmd = cmd .. " gui=" .. gui
		end
		vim.cmd(cmd)

		return {
			background = background and tonumber(background, 16) or nil,
			foreground = foreground and tonumber(foreground, 16) or nil,
		}
	end
	return hl_group
end

M.setup = function()
	M.create_highlight_group(M.SECTION, { "Directory", "Title" }, nil, "61afef", "bold")
	M.create_highlight_group(M.PROJECT, { "Function", "String" }, nil, "98c379")
	M.create_highlight_group(M.CONTAINER, { "Normal" }, nil, "abb2bf")
	M.create_highlight_group(M.IMAGE, { "Normal" }, nil, "abb2bf")
	M.create_highlight_group(M.VOLUME, { "Normal" }, nil, "abb2bf")
	M.create_highlight_group(M.NETWORK, { "Normal" }, nil, "abb2bf")
	M.create_highlight_group(M.ICON, { "Comment", "NonText" }, nil, "5c6370")
	M.create_highlight_group(M.COUNT, { "Number", "Constant" }, nil, "56b6c2")
	M.create_highlight_group(M.STATUS_RUNNING, { "String", "DiffAdd" }, nil, "98c379", "bold")
	M.create_highlight_group(M.STATUS_STOPPED, { "Number" }, nil, "5c6370", "bold")
end

return M
