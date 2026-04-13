---@diagnostic disable: undefined-global
---@class docker.sidebar.Tree
---@field id string
---@field name string
---@field kind "root"|"section"|"project"|"container"|"image"|"volume"|"network"
---@field parent? docker.sidebar.Tree
---@field children table<string, docker.sidebar.Tree>
---@field open? boolean
---@field expanded? boolean
---@field data table
---@field hidden? boolean
---@field ignored? boolean
---@field node docker.sidebar.Tree
local Tree = {}

function Tree.create_node(kind, data, collapsed)
	return {
		kind = kind,
		collapsed = collapsed or false,
		children = {},
		data = data or {},
		parent = nil,
	}
end

function Tree.add_child(parent, child)
	table.insert(parent.children, child)
	child.parent = parent
end

function Tree.build_tree(docker_data, state)
	local root = Tree.create_node("root", {})

	local containers_section = Tree.create_node("section", {
		name = "Containers",
	}, state.collapsed.containers or false)

	local projects = docker_data.containers
	local total_containers = 0
	for _, containers in pairs(projects) do
		total_containers = total_containers + #containers
	end
	containers_section.data.count = total_containers

	local project_names = {}
	for project_name, _ in pairs(projects) do
		table.insert(project_names, project_name)
	end
	table.sort(project_names)

	for _, project_name in ipairs(project_names) do
		local containers = projects[project_name]
		local project_key = "project_" .. project_name
		local project_node = Tree.create_node("project", {
			name = project_name,
		}, state.collapsed[project_key] or false)

		for _, container in ipairs(containers) do
			local container_node = Tree.create_node("container", {
				name = container.name,
				status = container.status,
				state = container.state,
				image = container.image,
			})
			Tree.add_child(project_node, container_node)
		end

		Tree.add_child(containers_section, project_node)
	end

	Tree.add_child(root, containers_section)

	local images_section = Tree.create_node("section", {
		name = "Images",
		count = #docker_data.images,
	}, state.collapsed.images or false)

	for _, image in ipairs(docker_data.images) do
		local image_node = Tree.create_node("image", {
			name = image.name,
			id = image.id,
			size = image.size,
		})
		Tree.add_child(images_section, image_node)
	end

	Tree.add_child(root, images_section)

	local volumes_section = Tree.create_node("section", {
		name = "Volumes",
		count = #docker_data.volumes,
	}, state.collapsed.volumes or false)

	for _, volume in ipairs(docker_data.volumes) do
		local volume_node = Tree.create_node("volume", {
			name = volume.name,
		})
		Tree.add_child(volumes_section, volume_node)
	end

	Tree.add_child(root, volumes_section)

	local networks_section = Tree.create_node("section", {
		name = "Networks",
		count = #docker_data.networks,
	}, state.collapsed.networks or false)

	for _, network in ipairs(docker_data.networks) do
		local network_node = Tree.create_node("network", {
			name = network.name,
			driver = network.driver,
		})
		Tree.add_child(networks_section, network_node)
	end

	Tree.add_child(root, networks_section)

	return root
end

--------------------------------------------------------------

Tree.__index = Tree

function Tree.new()
	local self = setmetatable({}, Tree)
	self.id = vim.fn.uuid()
	self.name = "root"
	self.kind = "root"
	self.children = {}
	self.data = {}
	self.node = nil
	self.open = false
	return self
end

return Tree
