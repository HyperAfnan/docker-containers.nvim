local Terminal = require("toggleterm.terminal").Terminal
local config = require("docker-containers.config")
local nio = require("nio")
local Job = require("plenary.job")
local M = {}

local function parse_status(status_string)
   if status_string:match("^Up ") then
      return "running"
   else
      return "stopped"
   end
end

function M.get_containers(callback)
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
                  local project_match = labels_json:match("\"com.docker.compose.project\":\"([^\"]+)\"")
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
      end,
   }):sync()
end

function M.get_images(callback)
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
      end,
   }):sync()
end

function M.get_volumes(callback)
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
      end,
   }):sync()
end

function M.get_networks(callback)
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
      end,
   }):sync()
end

function M.start_container(container_name, callback)
   Job:new({
      command = "docker",
      args = { "start", container_name },
      on_exit = function(j, return_val)
         if return_val == 0 then
            callback(true, "Container started successfully")
         else
            callback(false, table.concat(j:result(), "\n"))
         end
      end,
   }):sync()
end

function M.stop_container(container_name, callback)
   Job:new({
      command = "docker",
      args = { "stop", container_name },
      on_exit = function(j, return_val)
         if return_val == 0 then
            callback(true, "Container stopped successfully")
         else
            callback(false, table.concat(j:result(), "\n"))
         end
      end,
   }):sync(20000, 5)
end

function M.restart_container(container_name, callback)
   Job:new({
      command = "docker",
      args = { "restart", container_name },
      on_exit = function(j, return_val)
         if return_val == 0 then
            callback(true, "Container restarted successfully")
         else
            callback(false, table.concat(j:result(), "\n"))
         end
      end,
   }):sync()
end

function M.attach_container(container_name)
   Terminal:new({
      cmd = "docker exec -it " .. container_name .. " /bin/bash",
      direction = config.term.direction,
      display_name = container_name .. "_term",
      hidden = true,

   }):toggle()
end

function M.view_logs(container_name)
   Terminal:new({
      cmd = "docker logs -f " .. container_name,
      direction = config.term.direction,
      display_name = container_name .. "_logs",
      hidden = true,
   }):toggle()
end

return M
