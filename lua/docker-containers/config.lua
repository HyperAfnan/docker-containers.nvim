local M = {
	position = "right", --- left | right
   term = {
      direction = "horizontal", --- tabs | horizontal | vertical | float
   },
	maps = {
		collapse = "<space>",
		restart = "r",
		down = "d",
		start = "s",
		close = "q",
      attach_terminal = "t",
      view_logs = "l",
      refresh = "R",
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
