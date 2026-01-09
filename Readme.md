# docker-containers.nvim

A Neovim plugin for managing Docker containers, images, volumes, and networks directly from your editor.

## Features

- 🚀 **Container Management**: Start, stop, and restart Docker containers
- 📦 **Multi-Resource View**: Browse containers, images, volumes, and networks
- 🎯 **Docker Compose Support**: Automatically groups containers by compose project
- ⚡ **Async Operations**: Non-blocking container operations

## Requirements

- Neovim 0.9 or later
- [Docker](https://hub.docker.com/)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "HyperAfnan/docker-containers.nvim",
  dependencies = {
    "nvim-neotest/nvim-nio"
    "akinsho/toggleterm.nvim"
  },
  config = function()
    require("docker-containers").setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'HyperAfnan/docker-containers.nvim',
  requires = { 'nvim-neotest/nvim-nio' , 'akinsho/toggleterm.nvim' },
  config = function()
    require("docker-containers").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-neotest/nvim-nio'
Plug 'HyperAfnan/docker-containers.nvim'
Plug 'akinsho/toggleterm.nvim'

```

Then in your init.lua:

```lua
require("docker-containers").setup()
```

## Usage

```vim
:DockerContainers
```

## Configuration

```lua
require("docker-containers").setup({
  position = "right",  -- left | right
  term = {
      direction = "horizontal" -- tabs | horizontal | vertical | float
  },
  maps = {
    collapse = "<space>",
    restart = "r",
    down = "d",
    start = "s",
    close = "q"
  },
  icons = {
    container_running = "",
    container_stopped = "",
    project = "",
    expanded = "",
    collapsed = "",
  }
})
```

## Acknowledgments

- Built with [nvim-nio](https://github.com/nvim-neotest/nvim-nio) for async operations
- Terminal integration via [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
