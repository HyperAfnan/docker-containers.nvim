local docker = require("docker-containers.docker")
local config = require("docker-containers.config")
local highlights = require("docker-containers.highlights")

local M = {}

M.sidebar_buf = nil
M.sidebar_win = nil
M.tree = nil
M.line_to_node = {}
M.state = {
	collapsed = {
		containers = false,
		images = true,
		volumes = true,
		networks = true,
	},
}

-- Create a new node
local function create_node(kind, data, collapsed)
	return {
		kind = kind,
		collapsed = collapsed or false,
		children = {},
		data = data or {},
		parent = nil,
	}
end

-- Add a child node to a parent
local function add_child(parent, child)
	table.insert(parent.children, child)
	child.parent = parent
end

-- Build the tree from docker data
local function build_tree(docker_data, state)
	local root = create_node("root", {})

	-- Containers section
	local containers_section = create_node("section", {
		name = "Containers",
	}, state.collapsed.containers or false)

	local projects = docker_data.containers
	local total_containers = 0
	for _, containers in pairs(projects) do
		total_containers = total_containers + #containers
	end
	containers_section.data.count = total_containers

	-- Sort projects by name
	local project_names = {}
	for project_name, _ in pairs(projects) do
		table.insert(project_names, project_name)
	end
	table.sort(project_names)

	-- Build project nodes
	for _, project_name in ipairs(project_names) do
		local containers = projects[project_name]
		local project_key = "project_" .. project_name
		local project_node = create_node("project", {
			name = project_name,
		}, state.collapsed[project_key] or false)

		for _, container in ipairs(containers) do
			local container_node = create_node("container", {
				name = container.name,
				status = container.status,
				state = container.state,
				image = container.image,
			})
			add_child(project_node, container_node)
		end

		add_child(containers_section, project_node)
	end

	add_child(root, containers_section)

	-- Images section
	local images_section = create_node("section", {
		name = "Images",
		count = #docker_data.images,
	}, state.collapsed.images or false)

	for _, image in ipairs(docker_data.images) do
		local image_node = create_node("image", {
			name = image.name,
			id = image.id,
			size = image.size,
		})
		add_child(images_section, image_node)
	end

	add_child(root, images_section)

	-- Volumes section
	local volumes_section = create_node("section", {
		name = "Volumes",
		count = #docker_data.volumes,
	}, state.collapsed.volumes or false)

	for _, volume in ipairs(docker_data.volumes) do
		local volume_node = create_node("volume", {
			name = volume.name,
		})
		add_child(volumes_section, volume_node)
	end

	add_child(root, volumes_section)

	-- Networks section
	local networks_section = create_node("section", {
		name = "Networks",
		count = #docker_data.networks,
	}, state.collapsed.networks or false)

	for _, network in ipairs(docker_data.networks) do
		local network_node = create_node("network", {
			name = network.name,
			driver = network.driver,
		})
		add_child(networks_section, network_node)
	end

	add_child(root, networks_section)

	return root
end

-- Render the tree to lines
local function render_tree(root)
	local lines = {}
	local line_to_node = {}

	local function render_node(node, indent)
		if node.kind == "root" then
			-- Root doesn't render, just its children
			for _, child in ipairs(node.children) do
				render_node(child, indent)
			end
		elseif node.kind == "section" then
			local icon = node.collapsed and config.icons.collapsed or config.icons.expanded
			local line = icon .. " " .. node.data.name .. " (" .. node.data.count .. ")"

			table.insert(lines, line)
			line_to_node[#lines] = node

			if not node.collapsed then
				for _, child in ipairs(node.children) do
					render_node(child, indent + 1)
				end
			end

			-- Add spacing after section
			table.insert(lines, "")
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
					render_node(child, indent + 1)
				end
			end
		elseif node.kind == "container" then
			local spaces = string.rep("  ", indent)
			-- Status indicator based on state
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

	render_node(root, 0)

	return lines, line_to_node
end

-- Toggle a node's collapsed state
local function toggle_node(node, state)
	if not node then
		return false
	end

	-- Only collapsible nodes can toggle
	if node.kind == "section" or node.kind == "project" then
		node.collapsed = not node.collapsed

		if node.kind == "section" then
			state.collapsed[node.data.name:lower()] = node.collapsed
		elseif node.kind == "project" then
			state.collapsed["project_" .. node.data.name] = node.collapsed
		end

		return true
	end

	return false
end

-- Apply highlights to the buffer
local function apply_highlights()
	if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
		return
	end

	vim.api.nvim_buf_clear_namespace(M.sidebar_buf, highlights.ns_id, 0, -1)

	for line_num, node in pairs(M.line_to_node) do
		local line_idx = line_num - 1
		local line = vim.api.nvim_buf_get_lines(M.sidebar_buf, line_idx, line_idx + 1, false)[1]

		if not line then
			goto continue
		end

		if node.kind == "section" then
			-- Highlight icon
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.ICON,
				line_idx,
				0,
				1
			)
			-- Highlight section name
			local name_start = line:find(node.data.name)
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
			-- Highlight count
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
		elseif node.kind == "project" then
			-- Apply project highlight to entire line first (as base)
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.PROJECT,
				line_idx,
				0,
				#line
			)
			-- Find icon position (after leading spaces)
			local leading_spaces = line:match("^(%s*)")
			local spaces_len = #leading_spaces
			-- Icon is right after the spaces (▶ or ▼ are 3 bytes each in UTF-8)
			local icon_end = spaces_len + 3
			-- Apply icon highlight on top with higher priority
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.ICON,
				line_idx,
				spaces_len,
				icon_end
			)
		elseif node.kind == "container" then
			-- Highlight container name
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.CONTAINER,
				line_idx,
				0,
				#line
			)
			-- Highlight status indicator
			local leading_spaces = line:match("^(%s*)")
			local spaces_len = #leading_spaces
			local status_icon_end = spaces_len + 3

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
		elseif node.kind == "image" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.IMAGE,
				line_idx,
				0,
				#line
			)
		elseif node.kind == "volume" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.VOLUME,
				line_idx,
				0,
				#line
			)
		elseif node.kind == "network" then
			vim.api.nvim_buf_add_highlight(
				M.sidebar_buf,
				highlights.ns_id,
				highlights.NETWORK,
				line_idx,
				0,
				#line
			)
		end

		::continue::
	end
end

-- Refresh the entire UI
function M.refresh()
	if not M.sidebar_buf or not vim.api.nvim_buf_is_valid(M.sidebar_buf) then
		return
	end

	-- Fetch docker data
	local docker_data = {
		containers = docker.get_containers(),
		images = docker.get_images(),
		volumes = docker.get_volumes(),
		networks = docker.get_networks(),
	}

	-- Build tree with current state
	M.tree = build_tree(docker_data, M.state)

	-- Render tree to lines
	local lines, line_mapping = render_tree(M.tree)
	M.line_to_node = line_mapping

	-- Update buffer
	vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(M.sidebar_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(M.sidebar_buf, "modifiable", false)

	-- Apply highlights
	apply_highlights()
end

-- Handle toggle action
local function toggle_section()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if toggle_node(node, M.state) then
		M.refresh()
	end
end

-- Start container
local function start_container()
	local line = vim.api.nvim_win_get_cursor(M.sidebar_win)[1]
	local node = M.line_to_node[line]

	if not node or node.kind ~= "container" then
		return
	end

	local container_name = node.data.name
	local success, message = docker.start_container(container_name)

	if success then
		vim.notify("Container '" .. container_name .. "' started", vim.log.levels.INFO)
	else
		vim.notify("Failed to start container: " .. message, vim.log.levels.ERROR)
	end

	-- Refresh UI after a short delay to let docker update
	vim.defer_fn(function()
		M.refresh()
	end, 500)
end

-- Stop container
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

-- Restart container
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

			-- Refresh UI after command completes
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
      vim.notify("Unable to attach to " .. container_name .. " (Container not running)", vim.log.levels.ERROR, {
         title = "  docker-containers.nvim",
         timeout = 2000,
      })
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

local function setup_keymaps()
	vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.collapse, "", {
		noremap = true,
		silent = true,
		callback = toggle_section,
	})
	vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.close or "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			vim.api.nvim_win_close(M.sidebar_win, false)
		end,
	})
	-- Start container
	vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.start or "s", "", {
		noremap = true,
		silent = true,
		callback = start_container,
	})
	-- Stop container
	vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.down or "d", "", {
		noremap = true,
		silent = true,
		callback = stop_container,
	})
	-- Restart container
	vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.restart or "r", "", {
		noremap = true,
		silent = true,
		callback = restart_container,
	})

   vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.attach_terminal, "", {
		noremap = true,
		silent = true,
		callback = attach_terminal,
   })
   vim.api.nvim_buf_set_keymap(M.sidebar_buf, "n", config.maps.view_logs, "", {
		noremap = true,
		silent = true,
		callback = view_logs,
   })
end

function M.open()
	-- Setup highlights
	highlights.setup()

	-- Create a new buffer
	M.sidebar_buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options
	vim.api.nvim_buf_set_option(M.sidebar_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(M.sidebar_buf, "filetype", "docker-containers")

	-- Create a vertical split on the configured side
	if config.position == "left" then
		vim.cmd("topleft vsplit")
	else
		vim.cmd("botright vsplit")
	end
	M.sidebar_win = vim.api.nvim_get_current_win()

	-- Set the buffer in the window
	vim.api.nvim_win_set_buf(M.sidebar_win, M.sidebar_buf)

	-- Set window options
	vim.api.nvim_win_set_width(M.sidebar_win, 40)
	vim.api.nvim_win_set_option(M.sidebar_win, "number", false)
	vim.api.nvim_win_set_option(M.sidebar_win, "relativenumber", false)
	vim.api.nvim_win_set_option(M.sidebar_win, "signcolumn", "no")
	vim.api.nvim_win_set_option(M.sidebar_win, "winfixwidth", true)

	-- Set up keymaps
	setup_keymaps()

	-- Initial render
	M.refresh()
end

return M
