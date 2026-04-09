local config = require("docker-containers.config")
local cache = require("docker-containers.cache")
local Job = require("plenary.job")
local async = require("vim._async")

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
	local project_cache = cache.get("projects")
	if project_cache ~= nil then
		callback(project_cache)
	else
		Job:new({
			command = "docker",
			args = { "ps", "-a", "--format", "{{.Names}}\t{{.Status}}\t{{.Image}}" },
			on_exit = function(j, return_val)
				if return_val ~= 0 then
					callback(nil, j:stderr_result())
					return
				end

				local result = table.concat(j:result(), "\n")
				local containers = {}
				for line in result:gmatch("[^\r\n]+") do
					local name, status, image = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
					if name then
						local label_handle =
							io.popen("docker inspect " .. name .. " --format='{{json .Config.Labels}}'")
						local labels_json = ""
						if label_handle then
							labels_json = label_handle:read("*a")
							label_handle:close()
						end

						local project = "standalone"
						if labels_json and labels_json ~= "" then
							local project_match =
								labels_json:match("\"com.docker.compose.project\":\"([^\"]+)\"")
							if project_match then
								project = project_match
							end
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

				callback(projects)
				cache.set("projects", projects)
			end,
		}):sync()
	end
end

---@param callback function(images: table?, error: string?)
function M.get_images(callback)
	local image_cache = cache.get("images")
	if image_cache ~= nil then
		callback(image_cache)
	else
		Job:new({
			command = "docker",
			args = { "images", "--format", "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}" },
			on_exit = function(j, return_val)
				if return_val ~= 0 then
					callback(nil, j:stderr_result())
					return
				end

				local result = table.concat(j:result(), "\n")
				local images = {}
				for line in result:gmatch("[^\r\n]+") do
					local name, id, size = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
					if name then
						table.insert(images, {
							name = name,
							id = id,
							size = size,
						})
					end
				end

				callback(images, nil)
				cache.set("images", images)
			end,
		}):sync()
	end
end

---@param callback function(volumes: table?, error: string?)
function M.get_volumes(callback)
	local volume_cache = cache.get("volumes")
	if volume_cache ~= nil then
		callback(volume_cache)
	else
		Job:new({
			command = "docker",
			args = { "volume", "ls", "--format", "{{.Name}}" },
			on_exit = function(j, return_val)
				if return_val ~= 0 then
					callback(nil, j:stderr_result())
					return
				end

				local result = table.concat(j:result(), "\n")
				local volumes = {}
				for line in result:gmatch("[^\r\n]+") do
					if line ~= "" then
						table.insert(volumes, { name = line })
					end
				end

				callback(volumes)
				cache.set("volumes", volumes)
			end,
		}):sync()
	end
end

---@param callback function(networks: table?, error: string?)
function M.get_networks(callback)
	local network_cache = cache.get("networks")
	if network_cache ~= nil then
		callback(network_cache)
	else
		Job:new({
			command = "docker",
			args = { "network", "ls", "--format", "{{.Name}}\t{{.Driver}}" },
			on_exit = function(j, return_val)
				if return_val ~= 0 then
					callback(nil, j:stderr_result())
					return
				end

				local result = table.concat(j:result(), "\n")
				local networks = {}
				for line in result:gmatch("[^\r\n]+") do
					local name, driver = line:match("([^\t]+)\t([^\t]+)")
					if name then
						table.insert(networks, {
							name = name,
							driver = driver,
						})
					end
				end

				callback(networks)
				cache.set("networks", networks)
			end,
		}):sync()
	end
end

---@param container_name string
---@param callback function(success: boolean, message: string)
function M.start_container(container_name, callback)
	async.run(function()
		local cmd = { "docker", "start", container_name }
		local sys_opts = { cwd = vim.fn.getcwd(), env = vim.fn.environ(), timeout = 20000 }
		local out = async.await(3, vim.system, cmd, sys_opts)
		local stderr = out.stderr or ""
		if out.code ~= 0 then
			callback(
				false,
				stderr ~= "" and stderr or ("docker stop failed with exit code " .. out.code)
			)
			return
		end

		if stderr ~= "" then
			callback(false, stderr)
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

--- @param container_name string
--- @param callback function(success: boolean, message: string)
function M.stop_container(container_name, callback)
	async.run(function()
		local cmd = { "docker", "stop", container_name }
		local sys_opts = { cwd = vim.fn.getcwd(), env = vim.fn.environ(), timeout = 20000 }
		local out = async.await(3, vim.system, cmd, sys_opts)
		local stderr = out.stderr or ""

		if out.code ~= 0 then
			callback(
				false,
				stderr ~= "" and stderr or ("docker stop failed with exit code " .. out.code)
			)
			return
		end

		if stderr ~= "" then
			callback(false, stderr)
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
		local sys_opts = { cwd = vim.fn.getcwd(), env = vim.fn.environ(), timeout = 20000 }
		local out = async.await(3, vim.system, cmd, sys_opts)
		local stderr = out.stderr or ""

		if out.code ~= 0 then
			callback(
				false,
				stderr ~= "" and stderr or ("docker stop failed with exit code " .. out.code)
			)
			return
		end

		if stderr ~= "" then
			callback(false, stderr)
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
