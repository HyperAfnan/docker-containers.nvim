local docker = require("docker-containers.docker")
local config = require("docker-containers.config")
local highlights = require("docker-containers.highlights")
local tree = require("docker-containers.tree")
local cache = require("docker-containers.cache")

local M = {}

M.sidebar_buf = nil
M.sidebar_win = nil
M.help_win = nil
M.help_buf = nil
M.tree = nil
M.line_to_node = {}
M.rendered_lines = {}

-- Local function to render tree to buffer lines and generate the mapping
local function render_tree_to_buffer(root)
	local lines = {}
	local line_to_node = {}

	local function dfs(node, indent)
		if node.kind == "root" then
			for _, child in ipairs(node.children) do
				dfs(child, indent)
			end
		elseif node.kind == "section" then
			local icon = node.collapsed and config.icons.collapsed or config.icons.expanded
			local line = icon .. " " .. node.data.name .. " (" .. node.data.count .. ")"
			table.insert(lines, line)
			line_to_node[#lines] = node

			if not node.collapsed then
				for _, child in ipairs(node.children) do
					dfs(child, indent + 1)
				end
			end
			-- Append blank line after section for spacing
			table.insert(lines, "")
			line_to_node[#lines] = nil
		elseif node.kind == "project" then
			local icon = node.collapsed and config.icons.collapsed or config.icons.expanded
			local spaces = string.rep("  ", indent)
			local line = spaces
				.. icon
				.. " "
				.. config.icons.project
				.. " "
				.. node.data.name
				.. " ("
				.. #node.children
				.. ")"
			table.insert(lines, line)
			line_to_node[#lines] = node

			if not node.collapsed then
				for _, child in ipairs(node.children) do
					dfs(child, indent + 1)
				end
			end
		elseif node.kind == "container" then
			local spaces = string.rep("  ", indent)
			local status_icon = node.data.state == "running" and config.icons.container_running
				or config.icons.container_stopped
			local line = spaces .. status_icon .. " " .. node.data.name
			table.insert(lines, line)
			line_to_node[#lines] = node
		elseif node.kind == "image" or node.kind == "volume" or node.kind == "network" then
			local spaces = string.rep("  ", indent)
			local line = spaces .. "• " .. node.data.name
			table.insert(lines, line)
			line_to_node[#lines] = node
		end
	end

	dfs(root, 0)
	return lines, line_to_node
end

local function apply_highlights()
	if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
		return
	end

	vim.api.nvim_buf_clear_namespace(M.sidebar_buf, highlights.ns_id, 0, -1)

	for line_num, node in pairs(M.line_to_node) do
		local line_idx = line_num - 1
		local line = M.rendered_lines[line_num]

		if line and node.kind == "section" then
			local icon_len = line:find(" ") and (line:find(" ") - 1) or 3
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.ICON,
				line_idx,
				0,
				icon_len
			)

			local name_start = line:find(node.data.name, 1, true)
			if name_start then
				vim.api.nvim_buf_add_highlight(
					M.sidebar_buf,
					highlights.ns_id,
					highlights.SECTION,
					line_idx,
					name_start - 1,
					name_start - 1 + #node.data.name
				)
			end

			local count_start = line:find("%(")
			if count_start then
				vim.api.nvim_buf_add_highlight(
					M.sidebar_buf,
					highlights.ns_id,
					highlights.COUNT,
					line_idx,
					count_start - 1,
					#line
				)
			end
		elseif line and node.kind == "project" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.PROJECT,
				line_idx,
				0,
				#line
			)
			local leading_spaces = line:match("^(%s*)")
			local spaces_len = #leading_spaces
			local first_space = line:find(" ", spaces_len + 1)
			local icon_end = first_space and (first_space - 1) or (spaces_len + 3)
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.ICON,
				line_idx,
				spaces_len,
				icon_end
			)
		elseif line and node.kind == "container" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.CONTAINER,
				line_idx,
				0,
				#line
			)
			local leading_spaces = line:match("^(%s*)")
			local spaces_len = #leading_spaces
			local first_space = line:find(" ", spaces_len + 1)
			local status_icon_end = first_space and (first_space - 1) or (spaces_len + 3)

			local status_hl = node.data.state == "running" and highlights.STATUS_RUNNING
				or highlights.STATUS_STOPPED

			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				status_hl,
				line_idx,
				spaces_len,
				status_icon_end
			)
		elseif line and node.kind == "image" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.IMAGE,
				line_idx,
				0,
				#line
			)
		elseif line and node.kind == "volume" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.VOLUME,
				line_idx,
				0,
				#line
			)
		elseif line and node.kind == "network" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.NETWORK,
				line_idx,
				0,
				#line
			)
		end
	end
end

-- Core draw function to update UI locally and restore cursor focus
function M.draw()
	if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
		return
	end

	-- Save cursor info to restore later
	local cursor_node_id = nil
	local cursor_col = 0
	if M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
		local cursor = vim.api.nvim_win_get_cursor(M.sidebar_win)
		local cursor_line = cursor[1]
		cursor_col = cursor[2]
		local old_node = M.line_to_node[cursor_line]
		if old_node then
			cursor_node_id = old_node.id
		end
	end

	local lines, line_mapping = {}, {}
	if M.tree and M.tree.root then
		lines, line_mapping = render_tree_to_buffer(M.tree.root)
	end

	if #lines == 0 then
		lines = { "No Docker resources found" }
		line_mapping = {}
	end

	M.rendered_lines = lines
	M.line_to_node = line_mapping

	vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(M.sidebar_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", false)

	apply_highlights()

	-- Restore cursor
	if M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
		local target_line = 1
		if cursor_node_id then
			for idx, node in pairs(line_mapping) do
				if node and node.id == cursor_node_id then
					target_line = idx
					break
				end
			end
		end

		local max_line = vim.api.nvim_buf_line_count(M.sidebar_buf)
		if target_line > max_line then
			target_line = max_line
		end
		if target_line < 1 then
			target_line = 1
		end

		local current_cursor = vim.api.nvim_win_get_cursor(M.sidebar_win)
		if current_cursor[1] ~= target_line then
			pcall(vim.api.nvim_win_set_cursor, M.sidebar_win, { target_line, cursor_col })
		end
	end
end

function M.refresh(force_clean_cache)
	if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
		return
	end

	if force_clean_cache then
		cache.clean()
	end

	-- Only display full screen loader on initial open
	if not M.tree then
		M.line_to_node = {}
		M.rendered_lines = {}
		vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.sidebar_buf, 0, -1, false, { "Loading Docker resources..." })
		vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", false)
	end

	local docker_data = {
		containers = {},
		images = {},
		volumes = {},
		networks = {},
	}
	local errors = {}
	local pending = 4
	local rendered = false

	local function finalize()
		if rendered or pending > 0 then
			return
		end
		rendered = true

		M.tree = tree.build_tree(docker_data, M.tree)

		vim.schedule(function()
			if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
				return
			end

			M.draw()

			if #errors > 0 then
				vim.notify(
					"Docker refresh completed with errors:\n" .. table.concat(errors, "\n"),
					vim.log.levels.WARN
				)
			end
		end)
	end

	local function complete_with(field, fallback)
		return function(data, err)
			if data ~= nil then
				docker_data[field] = data
			else
				docker_data[field] = fallback
				errors[#errors + 1] = err or ("Failed to fetch " .. field)
			end
			pending = pending - 1
			finalize()
		end
	end

	docker.get_containers(complete_with("containers", {}))
	docker.get_images(complete_with("images", {}))
	docker.get_volumes(complete_with("volumes", {}))
	docker.get_networks(complete_with("networks", {}))
end

local function toggle_section()
	if not M.sidebar_win or not vim.api.nvim_win_is_valid(M.sidebar_win) then
		return
	end
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if node and (node.kind == "section" or node.kind == "project") then
		node.collapsed = not node.collapsed
		M.draw()
	end
end

function M.get_selected_nodes()
	local start_line = vim.fn.line("v")
	local end_line = vim.fn.line(".")

	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end

	local nodes = {}

	for l = start_line, end_line do
		local node = M.line_to_node[l]
		if node and node.kind == "container" then
			table.insert(nodes, node)
		end
	end

	return nodes
end

local function start_container()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if not node or node.kind ~= "container" then
		return
	end

	local container_name = node.data.name
	docker.start_container(container_name, function(success, message)
		vim.schedule(function()
			if success then
				vim.notify("Container '" .. container_name .. "' started", vim.log.levels.INFO, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			else
				vim.notify("Failed to start container: " .. message, vim.log.levels.ERROR, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			end

			M.refresh()
		end)
	end)
end

local function start_selected_containers()
	local nodes = M.get_selected_nodes()

	if #nodes == 0 then
		vim.notify("No containers selected", vim.log.levels.WARN)
		return
	end

	local containers
	for _, node in ipairs(nodes) do
		if not containers then
			containers = node.data.name
		else
			containers = containers .. " " .. node.data.name
		end
	end
	vim.notify("Taking down selected containers...", vim.log.levels.INFO)
	docker.start_container(containers)

	vim.notify("Selected containers started", vim.log.levels.INFO)

	vim.defer_fn(M.refresh, 500)
end

local function stop_container()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if not node or node.kind ~= "container" then
		return
	end

	vim.notify("Stopping container '" .. node.data.name .. "'...", vim.log.levels.INFO, {
		title = "  docker-containers.nvim",
		timeout = 2000,
	})

	local container_name = node.data.name

	docker.stop_container(container_name, function(success, message)
		vim.schedule(function()
			if success then
				vim.notify("Container '" .. container_name .. "' stopped", vim.log.levels.INFO, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			else
				vim.notify("Failed to stop container: " .. message, vim.log.levels.ERROR, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			end

			M.refresh()
		end)
	end)
end

local function restart_container()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if not node or node.kind ~= "container" then
		return
	end

	vim.notify("Restarting container '" .. node.data.name .. "'...", vim.log.levels.INFO, {
		title = "  docker-containers.nvim",
		timeout = 2000,
	})

	local container_name = node.data.name

	docker.restart_container(container_name, function(success, message)
		vim.schedule(function()
			if success then
				vim.notify("Container '" .. container_name .. "' restarted", vim.log.levels.INFO, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			else
				vim.notify("Failed to restart container: " .. message, vim.log.levels.ERROR, {
					title = "  docker-containers.nvim",
					timeout = 3000,
				})
			end

			M.refresh()
		end)
	end)
end

local function attach_terminal()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]
	local container_name = node.data.name

	if not node or node.kind ~= "container" then
		return
	end

	if node.data.state == "stopped" then
		vim.notify(
			"Unable to attach to " .. container_name .. " (Container not running)",
			vim.log.levels.ERROR,
			{
				title = "  docker-containers.nvim",
				timeout = 2000,
			}
		)
		return
	else
		docker.attach_container(container_name)
	end
end

local function view_logs()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]
	local container_name = node.data.name

	if not node or node.kind ~= "container" then
		return
	end

	docker.view_logs(container_name)
end

function M.show_help()
	if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
		vim.api.nvim_win_close(M.help_win, true)
		M.help_win = nil
		M.help_buf = nil
		return
	end

	if not M.sidebar_win or not vim.api.nvim_win_is_valid(M.sidebar_win) then
		return
	end

	local groups = {
		{
			title = "Commands",
			maps = {
				{ key = config.maps.start or "s", desc = "Start" },
				{ key = config.maps.down or "d", desc = "Stop" },
				{ key = config.maps.restart or "r", desc = "Restart" },
				{ key = config.maps.attach_terminal or "t", desc = "Attach" },
				{ key = config.maps.view_logs or "l", desc = "Logs" },
			},
		},
		{
			title = "Navigation",
			maps = {
				{ key = config.maps.collapse or "<CR>", desc = "Toggle" },
				{ key = config.maps.refresh or "R", desc = "Refresh" },
				{ key = config.maps.close or "q", desc = "Close" },
				{ key = config.maps.help or "?", desc = "Help" },
			},
		},
	}

	local help_content = {}
	local highlights_to_apply = {}

	for _, group in ipairs(groups) do
		table.insert(help_content, group.title)
		local title_line_idx = #help_content - 1
		table.insert(highlights_to_apply, { title_line_idx, "Title", 0, -1 })

		for i = 1, #group.maps, 2 do
			local map1 = group.maps[i]
			local map2 = group.maps[i + 1]

			local col1_key = string.format(" %s", map1.key)
			local col1_desc = map1.desc
			local col1_str = string.format("%-6s %-12s", col1_key, col1_desc)

			local line_str = col1_str
			local col2_start_idx = #line_str
			local cur_line_idx = #help_content

			table.insert(highlights_to_apply, { cur_line_idx, "Special", 1, 1 + #map1.key })
			table.insert(
				highlights_to_apply,
				{ cur_line_idx, "Comment", 1 + #map1.key + 1, col2_start_idx }
			)

			if map2 then
				local col2_key = string.format(" %s", map2.key)
				local col2_desc = map2.desc
				line_str = line_str .. string.format("%-6s %s", col2_key, col2_desc)

				table.insert(
					highlights_to_apply,
					{ cur_line_idx, "Special", col2_start_idx + 1, col2_start_idx + 1 + #map2.key }
				)
				table.insert(
					highlights_to_apply,
					{ cur_line_idx, "Comment", col2_start_idx + 1 + #map2.key + 1, -1 }
				)
			end

			table.insert(help_content, line_str)
		end

		table.insert(help_content, "")
	end

	if help_content[#help_content] == "" then
		table.remove(help_content, #help_content)
	end

	M.help_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(M.help_buf, 0, -1, false, help_content)

	local win_opts = {
		split = "below",
		win = -1,
		height = #help_content,
	}

	M.help_win = vim.api.nvim_open_win(M.help_buf, true, win_opts)

	vim.api.nvim_win_set_option(M.help_win, "number", false)
	vim.api.nvim_win_set_option(M.help_win, "relativenumber", false)
	vim.api.nvim_win_set_option(M.help_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(M.help_win, "winfixheight", true)

	vim.api.nvim_buf_set_option(M.help_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.help_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(M.help_buf, "swapfile", false)
	vim.api.nvim_buf_set_option(M.help_buf, "filetype", "docker-containers-help")

	local close_keys = { "q", "<Esc>", config.maps.help or "?" }
	for _, key in ipairs(close_keys) do
		vim.keymap.set("n", key, function()
			if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
				vim.api.nvim_win_close(M.help_win, true)
			end
			M.help_win = nil
			M.help_buf = nil
			if M.sidebar_win and vim.api.nvim_win_is_valid(M.sidebar_win) then
				vim.api.nvim_set_current_win(M.sidebar_win)
			end
		end, { buffer = M.help_buf, silent = true, noremap = true })
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = M.help_buf,
		once = true,
		callback = function()
			if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
				vim.api.nvim_win_close(M.help_win, true)
			end
			M.help_win = nil
			M.help_buf = nil
		end,
	})

	local ns = vim.api.nvim_create_namespace("DockerHelp")
	for _, hl in ipairs(highlights_to_apply) do
		vim.api.nvim_buf_add_highlight(M.help_buf, ns, hl[2], hl[1], hl[3], hl[4])
	end

	vim.api.nvim_buf_set_option(M.help_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(M.help_buf, "readonly", true)
end

local function setup_keymaps()
	local keymaps = {
		{ mode = "n", key = config.maps.collapse or "<CR>", action = toggle_section },
		{
			mode = "n",
			key = config.maps.close or "q",
			action = function()
				vim.api.nvim_win_close(M.sidebar_win, false)
			end,
		},
		{ mode = "n", key = config.maps.start or "s", action = start_container },
		{ mode = "v", key = config.maps.start or "s", action = start_selected_containers },
		{ mode = "n", key = config.maps.down or "d", action = stop_container },
		{ mode = "n", key = config.maps.restart or "r", action = restart_container },
		{ mode = "n", key = config.maps.attach_terminal or "t", action = attach_terminal },
		{ mode = "n", key = config.maps.view_logs or "l", action = view_logs },
		{
			mode = "n",
			key = config.maps.refresh or "R",
			action = function()
				M.refresh(true)
			end,
		},
		{ mode = "n", key = config.maps.help or "?", action = M.show_help },
		{ mode = "n", key = "<Tab>", action = toggle_section },
	}
	for _, map in ipairs(keymaps) do
		vim.api.nvim_buf_set_keymap(
			M.sidebar_buf,
			map.mode,
			map.key,
			"",
			{ nowait = true, noremap = true, silent = true, callback = map.action }
		)
	end
end

function M.open()
	highlights.setup()

	M.sidebar_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_option(M.sidebar_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.sidebar_buf, "filetype", "docker-containers")

	if config.position == "left" then
		vim.cmd("topleft vsplit")
	else
		vim.cmd("botright vsplit")
	end
	M.sidebar_win = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(M.sidebar_win, M.sidebar_buf)

	vim.api.nvim_win_set_width(M.sidebar_win, 40)
	vim.api.nvim_win_set_option(M.sidebar_win, "number", false)
	vim.api.nvim_win_set_option(M.sidebar_win, "relativenumber", false)
	vim.api.nvim_win_set_option(M.sidebar_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(M.sidebar_win, "winfixwidth", true)

	setup_keymaps()

	M.refresh()
end

return M
