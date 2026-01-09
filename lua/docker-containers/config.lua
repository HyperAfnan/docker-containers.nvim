local M = {
	position = "right", -- or left
   term = {
      direction = "horizontal", -- float or horizontal
   },
	maps = {
		collapse = "<space>",
		restart = "r",
		down = "d",
		start = "s",
		close = "q",
      attach_terminal = "t",
      view_logs = "l"
	},
	icons = {
		container_running = "",
		container_stopped = "",
		project = "",
		expanded = "",
		collapsed = "",
	},
}

return M
