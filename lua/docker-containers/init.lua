local ui = require("docker-containers.ui")
local config = require("docker-containers.config")

local M = {}

---@param opts? table
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})

	vim.api.nvim_create_user_command("DockerContainers", function()
		ui.open()
	end, {})
end

return M
