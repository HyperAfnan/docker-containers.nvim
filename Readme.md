# docker-containers.nvim

A Neovim plugin for managing Docker containers, images, volumes, and networks directly from your editor.

## Features

- 🚀 **Container Management**: Start, stop, and restart Docker containers
- 📦 **Multi-Resource View**: Browse containers, images, volumes, and networks
- 🎯 **Docker Compose Support**: Automatically groups containers by compose project
- 🎨 **Syntax Highlighting**: Color-coded interface with status indicators
- ⚡ **Async Operations**: Non-blocking container operations
- 🔧 **Customizable**: Configure keybindings, icons, and UI position

## Requirements

- Neovim 0.5+
- Docker installed and accessible via command line
- `nvim-nio`

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/docker-containers.nvim",
  dependencies = {
    "nvim-neotest/nvim-nio"
  },
  config = function()
    require("docker-containers").setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'yourusername/docker-containers.nvim',
  requires = { 'nvim-neotest/nvim-nio' },
  config = function()
    require("docker-containers").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-neotest/nvim-nio'
Plug 'yourusername/docker-containers.nvim'
```

Then in your init.lua:

```lua
require("docker-containers").setup()
```

## Usage

### Opening the Sidebar

Run the command:

```vim
:DockerContainers
```

This will open the Docker sidebar showing all your containers, images, volumes, and networks.

### Keybindings

Default keybindings (customizable):

| Key | Action |
|-----|--------|
| `<Space>` | Collapse/expand sections and projects |
| `s` | Start a container |
| `d` | Stop a container |
| `r` | Restart a container |
| `q` | Close the sidebar |

## Configuration

```lua
require("docker-containers").setup({
  position = "right",  -- "left" or "right"
  maps = {
    collapse = "<space>",
    restart = "r",
    down = "d",
    start = "s",
    close = "q"
  },
  icons = {
    container_running = "",
    container_stopped = "",
    project = "",
    image = "📦",
    volume = "🗄️",
    network = "🌐",
    expanded = "",
    collapsed = "",
  }
})
```

## Acknowledgments

- Built with [nvim-nio](https://github.com/nvim-neotest/nvim-nio) for async operations