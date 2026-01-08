local M = {}

-- Parse container status to determine if running
local function parse_status(status_string)
  if status_string:match("^Up ") then
    return "running"
  else
    return "stopped"
  end
end

function M.get_containers()
  local handle = io.popen('docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Image}}"')
  if not handle then
    return {}
  end
  
  local result = handle:read("*a")
  handle:close()
  
  local containers = {}
  for line in result:gmatch("[^\r\n]+") do
    local name, status, image = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
    if name then
      -- Get labels for compose project
      local label_handle = io.popen('docker inspect ' .. name .. " --format='{{json .Config.Labels}}'")
      local labels_json = ""
      if label_handle then
        labels_json = label_handle:read("*a")
        label_handle:close()
      end
      
      -- Extract compose project name from labels
      local project = "standalone"
      if labels_json and labels_json ~= "" then
        local project_match = labels_json:match('"com.docker.compose.project":"([^"]+)"')
        if project_match then
          project = project_match
        end
      end
      
      table.insert(containers, {
        name = name,
        status = status,
        state = parse_status(status),
        image = image,
        project = project
      })
    end
  end
  
  -- Group containers by project
  local projects = {}
  for _, container in ipairs(containers) do
    if not projects[container.project] then
      projects[container.project] = {}
    end
    table.insert(projects[container.project], container)
  end
  
  return projects
end

function M.get_images()
  local handle = io.popen('docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"')
  if not handle then
    return {}
  end
  
  local result = handle:read("*a")
  handle:close()
  
  local images = {}
  for line in result:gmatch("[^\r\n]+") do
    local name, id, size = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
    if name then
      table.insert(images, {
        name = name,
        id = id,
        size = size
      })
    end
  end
  
  return images
end

function M.get_volumes()
  local handle = io.popen('docker volume ls --format "{{.Name}}"')
  if not handle then
    return {}
  end
  
  local result = handle:read("*a")
  handle:close()
  
  local volumes = {}
  for line in result:gmatch("[^\r\n]+") do
    if line ~= '' then
      table.insert(volumes, { name = line })
    end
  end
  
  return volumes
end

function M.get_networks()
  local handle = io.popen('docker network ls --format "{{.Name}}\t{{.Driver}}"')
  if not handle then
    return {}
  end
  
  local result = handle:read("*a")
  handle:close()
  
  local networks = {}
  for line in result:gmatch("[^\r\n]+") do
    local name, driver = line:match("([^\t]+)\t([^\t]+)")
    if name then
      table.insert(networks, {
        name = name,
        driver = driver
      })
    end
  end
  
  return networks
end

-- Start a container
function M.start_container(container_name)
  local handle = io.popen('docker start ' .. container_name .. ' 2>&1')
  if not handle then
    return false, "Failed to execute docker start command"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success then
    return true, "Container started successfully"
  else
    return false, result
  end
end

-- Start a container (async version)
function M.start_container_async(container_name, callback)
  vim.system(
    { 'docker', 'start', container_name },
    { text = true },
    function(obj)
      if obj.code == 0 then
        callback(true, "Container started successfully")
      else
        callback(false, obj.stderr or "Unknown error")
      end
    end
  )
end

-- Stop a container
function M.stop_container(container_name)
  local handle = io.popen('docker stop ' .. container_name .. ' 2>&1')
  if not handle then
    return false, "Failed to execute docker stop command"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success then
    return true, "Container stopped successfully"
  else
    return false, result
  end
end

-- Stop a container (async version)
function M.stop_container_async(container_name, callback)
  vim.system(
    { 'docker', 'stop', container_name },
    { text = true },
    function(obj)
      if obj.code == 0 then
        callback(true, "Container stopped successfully")
      else
        callback(false, obj.stderr or "Unknown error")
      end
    end
  )
end

-- Restart a container
function M.restart_container(container_name)
  local handle = io.popen('docker restart ' .. container_name .. ' 2>&1')
  if not handle then
    return false, "Failed to execute docker restart command"
  end
  
  local result = handle:read("*a")
  local success = handle:close()
  
  if success then
    return true, "Container restarted successfully"
  else
    return false, result
  end
end

-- Restart a container (async version)
function M.restart_container_async(container_name, callback)
  vim.system(
    { 'docker', 'restart', container_name },
    { text = true },
    function(obj)
      if obj.code == 0 then
        callback(true, "Container restarted successfully")
      else
        callback(false, obj.stderr or "Unknown error")
      end
    end
  )
end

return M
