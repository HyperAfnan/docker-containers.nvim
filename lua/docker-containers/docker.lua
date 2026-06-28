local cache = require("docker-containers.cache")
local async = require("vim._async")
local docker_async = require("docker-containers.async")
local config = require("docker-containers.config")
local Terminal = require("toggleterm.terminal").Terminal

local M = {}

---@param status_string string
local function parse_status(status_string)
	if status_string:match("^Up ") then
		return "running"
	else
		return "stopped"
	end
end

---@param callback function(projects: table?, error: string?)
---@return nil
function M.get_containers(callback)
	callback = callback or function() end
	local project_cache = cache.get("projects")
	if project_cache ~= nil then
		callback(project_cache, nil)
	else
		async.run(function()
			local success, output = docker_async.run_command({
				"docker",
				"ps",
				"-a",
				"--format",
				"{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Label \"com.docker.compose.project\"}}",
			})
			if not success then
				callback(nil, output)
				return
			end

			local containers = {}
			for line in output:gmatch("[^\r\n]+") do
				local name, status, image, project =
					line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)")
				if name then
					if not project or project == "<no value>" then
						project = "standalone"
					end
					table.insert(containers, {
						name = name,
						status = status,
						state = parse_status(status),
						image = image,
						project = project,
					})
				end
			end

			local projects = {}
			for _, container in ipairs(containers) do
				if not projects[container.project] then
					projects[container.project] = {}
				end
				table.insert(projects[container.project], container)
			end

			cache.set("projects", projects)
			callback(projects, nil)
		end, function(err)
			if err then
				callback(nil, err)
			end
		end)
	end
end

---@param callback function(images: table?, error: string?)
function M.get_images(callback)
	callback = callback or function() end
	local image_cache = cache.get("images")
	if image_cache ~= nil then
		callback(image_cache, nil)
	else
		async.run(function()
			local success, output = docker_async.run_command({
				"docker",
				"images",
				"--format",
				"{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}",
			})
			if not success then
				callback(nil, output)
				return
			end

			local images = {}
			for line in output:gmatch("[^\r\n]+") do
				local name, id, size = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
				if name then
					table.insert(images, {
						name = name,
						id = id,
						size = size,
					})
				end
			end

			cache.set("images", images)
			callback(images, nil)
		end, function(err)
			if err then
				callback(nil, err)
			end
		end)
	end
end

---@param callback function(volumes: table?, error: string?)
function M.get_volumes(callback)
	callback = callback or function() end
	local volume_cache = cache.get("volumes")
	if volume_cache ~= nil then
		callback(volume_cache, nil)
	else
		async.run(function()
			local success, output =
				docker_async.run_command({ "docker", "volume", "ls", "--format", "{{.Name}}" })
			if not success then
				callback(nil, output)
				return
			end

			local volumes = {}
			for line in output:gmatch("[^\r\n]+") do
				if line ~= "" then
					table.insert(volumes, { name = line })
				end
			end

			cache.set("volumes", volumes)
			callback(volumes, nil)
		end, function(err)
			if err then
				callback(nil, err)
			end
		end)
	end
end

---@param callback function(networks: table?, error: string?)
function M.get_networks(callback)
	callback = callback or function() end
	local network_cache = cache.get("networks")
	if network_cache ~= nil then
		callback(network_cache, nil)
	else
		async.run(function()
			local cmd = { "docker", "network", "ls", "--format", "{{.Name}}\t{{.Driver}}" }
			local success, output = docker_async.run_command(cmd)
			if not success then
				callback(nil, output)
				return
			end
			local networks = {}
			for line in output:gmatch("[^\r\n]+") do
				local name, driver = line:match("([^\t]+)\t([^\t]+)")
				if name then
					table.insert(networks, {
						name = name,
						driver = driver,
					})
				end
			end
			cache.set("networks", networks)
			callback(networks, nil)
		end, function(err)
			if err then
				callback(nil, err)
			end
		end)
	end
end

--- Helper to update container state inside the projects cache in-place
---@param names string[]
---@param state string
---@param status string
---@return nil
local function update_container_cache(names, state, status)
	cache.set("projects", function(projects)
		if not projects then
			return nil
		end
		local name_set = {}
		for _, name in ipairs(names) do
			name_set[name] = true
		end
		for _, project_containers in pairs(projects) do
			for _, container in ipairs(project_containers) do
				if name_set[container.name] then
					container.state = state
					container.status = status
				end
			end
		end
		return projects
	end)
end

---@param container_names string|string[]
---@param callback? function(success: boolean, message: string)
---@return nil
function M.start_container(container_names, callback)
	callback = callback or function() end
	local names = type(container_names) == "table" and container_names or { container_names }
	async.run(function()
		local cmd = { "docker", "start" }
		for _, name in ipairs(names) do
			table.insert(cmd, name)
		end
		local ok, out = docker_async.run_command(cmd)
		if not ok then
			callback(false, out)
			return
		end

		update_container_cache(names, "running", "Up")
		callback(true, "Containers started successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

---@param container_names string|string[]
---@param callback? function(success: boolean, message: string)
---@return nil
function M.stop_container(container_names, callback)
	callback = callback or function() end
	local names = type(container_names) == "table" and container_names or { container_names }
	async.run(function()
		local cmd = { "docker", "stop" }
		for _, name in ipairs(names) do
			table.insert(cmd, name)
		end
		local ok, out = docker_async.run_command(cmd)
		if not ok then
			callback(false, out)
			return
		end

		update_container_cache(names, "stopped", "Exited")
		callback(true, "Containers stopped successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

---@param container_names string|string[]
---@param callback? function(success: boolean, message: string)
---@return nil
function M.restart_container(container_names, callback)
	callback = callback or function() end
	local names = type(container_names) == "table" and container_names or { container_names }
	async.run(function()
		local cmd = { "docker", "restart" }
		for _, name in ipairs(names) do
			table.insert(cmd, name)
		end
		local ok, out = docker_async.run_command(cmd)
		if not ok then
			callback(false, out)
			return
		end

		update_container_cache(names, "running", "Up")
		callback(true, "Containers restarted successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

---@param container_name string
function M.attach_container(container_name)
	Terminal:new({
		cmd = "docker exec -it " .. container_name .. " /bin/sh",
		direction = config.term.direction,
		display_name = container_name .. "_term",
		hidden = true,
	}):toggle()
end

---@param container_name string
function M.view_logs(container_name)
	Terminal:new({
		cmd = "docker logs -f " .. container_name,
		direction = config.term.direction,
		display_name = container_name .. "_logs",
		hidden = true,
		on_open = function(term)
			vim.cmd("stopinsert")
			vim.api.nvim_buf_set_option(term.bufnr, "readonly", true)
			vim.api.nvim_buf_set_option(term.bufnr, "modifiable", false)
		end,
	}):toggle()
end

return M
