local async = require("vim._async")

local M = {}

local sys_opts = { cwd = vim.fn.getcwd(), env = vim.fn.environ(), timeout = 20000 }

function M.run_command(cmd)
	local out = async.await(3, vim.system, cmd, sys_opts)
	local stderr = out.stderr or ""

	if out.code ~= 0 then
		return false, stderr ~= "" and stderr or ("Command failed with exit code " .. out.code)
	end

	if stderr ~= "" then
		return false, stderr
	end

	return true, out.stdout or ""
end

return M
