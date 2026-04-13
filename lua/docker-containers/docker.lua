local cache = require("docker-containers.cache")
local async = require("vim._async")
local docker_async = require("docker-containers.async")

local M = {}

local function trim(s)
	if not s then
		return ""
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

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
				local name, status, image, project = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)")
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

---@param container_name string
---@param callback function(success: boolean, message: string)
function M.start_container(container_name, callback)
	async.run(function()
		local cmd = { "docker", "start", container_name }
		if not docker_async.run_command(cmd) then
			callback(false, "Failed to start container")
			return
		end

		cache.set("projects", function(projects)
			if not projects then
				return nil
			end
			for _, project_containers in pairs(projects) do
				for _, container in ipairs(project_containers) do
					if container.name == container_name then
						container.state = "running"
						container.status = "Up"
					end
				end
			end
			return projects
		end)
		callback(true, "Container started successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

---@param container_name string
---@param callback function(success: boolean, message: string)
function M.stop_container(container_name, callback)
	async.run(function()
		local cmd = { "docker", "stop", container_name }
		if not docker_async.run_command(cmd) then
			callback(false, "Failed to stop container")
			return
		end

		cache.set("projects", function(projects)
			if not projects then
				return nil
			end
			for _, project_containers in pairs(projects) do
				for _, container in ipairs(project_containers) do
					if container.name == container_name then
						container.state = "stopped"
						container.status = "Exited"
					end
				end
			end
			return projects
		end)

		callback(true, "Container stopped successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

---@param container_name string
---@param callback function(success: boolean, message: string)
function M.restart_container(container_name, callback)
	async.run(function()
		local cmd = { "docker", "restart", container_name }
		if not docker_async.run_command(cmd) then
			callback(false, "Failed to restart container")
			return
		end

		cache.set("projects", function(projects)
			if not projects then
				return nil
			end
			for _, project_containers in pairs(projects) do
				for _, container in ipairs(project_containers) do
					if container.name == container_name then
						container.state = "running"
						container.status = "Up"
					end
				end
			end
			return projects
		end)
		callback(true, "Container stopped successfully")
	end, function(err)
		if err then
			callback(false, err)
		end
	end)
end

-- ---@param container_name string
-- function M.attach_container(container_name)
-- 	Terminal:new({
-- 		cmd = "docker exec -it " .. container_name .. " /bin/sh",
-- 		direction = config.term.direction,
-- 		display_name = container_name .. "_term",
-- 		hidden = true,
-- 	}):toggle()
-- end
--
-- ---@param container_name string
-- function M.view_logs(container_name)
-- 	Terminal:new({
-- 		cmd = " /usr/bin/bash -c docker logs -f " .. container_name,
-- 		direction = config.term.direction,
-- 		display_name = container_name .. "_logs",
-- 		hidden = true,
-- 	}):toggle()
-- end

return M
