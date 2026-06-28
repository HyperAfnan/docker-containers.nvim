---@diagnostic disable: undefined-global

local Node = {}
Node.__index = Node

---@class docker.sidebar.Node
---@field id string
---@field kind "root"|"section"|"project"|"container"|"image"|"volume"|"network"
---@field parent? docker.sidebar.Node
---@field children docker.sidebar.Node[]
---@field collapsed boolean
---@field data table
function Node.new(opts)
	local self = setmetatable({}, Node)
	self.id = opts.id
	self.kind = opts.kind
	self.parent = opts.parent
	self.children = opts.children or {}
	self.collapsed = opts.collapsed or false
	if self.collapsed == nil then
		self.collapsed = false
	end
	self.data = opts.data or {}
	return self
end

function Node:add_child(child)
	table.insert(self.children, child)
	child.parent = self
end

function Node:remove_child(child_id)
	for i, child in ipairs(self.children) do
		if child.id == child_id then
			table.remove(self.children, i)
			child.parent = nil
			return child
		end
	end
	return nil
end

--------------------------------------------------------------

local Tree = {}
Tree.__index = Tree

---@class docker.sidebar.Tree
---@field root docker.sidebar.Node
---@field nodes_by_id table<string, docker.sidebar.Node>
function Tree.new()
	local self = setmetatable({}, Tree)
	self.root = Node.new({ id = "root", kind = "root" })
	self.nodes_by_id = { root = self.root }
	return self
end

function Tree:get_node(id)
	return self.nodes_by_id[id]
end

function Tree:add_node(node, parent_id)
	local parent = self:get_node(parent_id) or self.root
	parent:add_child(node)
	self.nodes_by_id[node.id] = node
	-- Recursively register children if any
	local function register(n)
		self.nodes_by_id[n.id] = n
		for _, child in ipairs(n.children) do
			register(child)
		end
	end
	for _, child in ipairs(node.children) do
		register(child)
	end
end

function Tree:remove_node(id)
	local node = self:get_node(id)
	if not node then
		return
	end

	if node.parent then
		node.parent:remove_child(id)
	end

	local function unregister(n)
		self.nodes_by_id[n.id] = nil
		for _, child in ipairs(n.children) do
			unregister(child)
		end
	end
	unregister(node)
end

function Tree:get_visible_nodes()
	local visible = {}
	local function dfs(node)
		if node.kind ~= "root" then
			table.insert(visible, node)
		end
		if node.kind == "root" or not node.collapsed then
			for _, child in ipairs(node.children) do
				dfs(child)
			end
		end
	end
	dfs(self.root)
	return visible
end

--------------------------------------------------------------

local M = {}

---@param docker_data table
---@param existing_tree? docker.sidebar.Tree
---@return docker.sidebar.Tree
function M.build_tree(docker_data, existing_tree)
	local tree = Tree.new()

	local function get_collapsed(node_id, default)
		if existing_tree then
			local old = existing_tree:get_node(node_id)
			if old ~= nil then
				return old.collapsed
			end
		end
		return default
	end

	-- 1. Containers Section
	local projects = docker_data.containers or {}
	local total_containers = 0
	for _, containers in pairs(projects) do
		total_containers = total_containers + #containers
	end

	local containers_section = Node.new({
		id = "section:containers",
		kind = "section",
		collapsed = get_collapsed("section:containers", false),
		data = {
			name = "Containers",
			count = total_containers,
		},
	})
	tree:add_node(containers_section, "root")

	local project_names = {}
	for project_name, _ in pairs(projects) do
		table.insert(project_names, project_name)
	end
	table.sort(project_names)

	for _, project_name in ipairs(project_names) do
		local containers = projects[project_name]
		local project_id = "project:" .. project_name
		local project_node = Node.new({
			id = project_id,
			kind = "project",
			collapsed = get_collapsed(project_id, false),
			data = {
				name = project_name,
			},
		})

		for _, container in ipairs(containers) do
			local container_node = Node.new({
				id = "container:" .. container.name,
				kind = "container",
				data = {
					name = container.name,
					status = container.status,
					state = container.state,
					image = container.image,
				},
			})
			project_node:add_child(container_node)
		end

		tree:add_node(project_node, "section:containers")
	end

	-- 2. Images Section
	local images_data = docker_data.images or {}
	local images_section = Node.new({
		id = "section:images",
		kind = "section",
		collapsed = get_collapsed("section:images", true),
		data = {
			name = "Images",
			count = #images_data,
		},
	})

	for _, image in ipairs(images_data) do
		local image_node = Node.new({
			id = "image:" .. image.name,
			kind = "image",
			data = {
				name = image.name,
				id = image.id,
				size = image.size,
			},
		})
		images_section:add_child(image_node)
	end
	-- Re-add to registry (since children were added directly)
	tree:add_node(images_section, "root")

	-- 3. Volumes Section
	local volumes_data = docker_data.volumes or {}
	local volumes_section = Node.new({
		id = "section:volumes",
		kind = "section",
		collapsed = get_collapsed("section:volumes", true),
		data = {
			name = "Volumes",
			count = #volumes_data,
		},
	})

	for _, volume in ipairs(volumes_data) do
		local volume_node = Node.new({
			id = "volume:" .. volume.name,
			kind = "volume",
			data = {
				name = volume.name,
			},
		})
		volumes_section:add_child(volume_node)
	end
	tree:add_node(volumes_section, "root")

	-- 4. Networks Section
	local networks_data = docker_data.networks or {}
	local networks_section = Node.new({
		id = "section:networks",
		kind = "section",
		collapsed = get_collapsed("section:networks", true),
		data = {
			name = "Networks",
			count = #networks_data,
		},
	})

	for _, network in ipairs(networks_data) do
		local network_node = Node.new({
			id = "network:" .. network.name,
			kind = "network",
			data = {
				name = network.name,
				driver = network.driver,
			},
		})
		networks_section:add_child(network_node)
	end
	tree:add_node(networks_section, "root")

	return tree
end

M.Node = Node
M.Tree = Tree

return M
