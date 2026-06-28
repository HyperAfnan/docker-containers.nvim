# docker-containers.nvim

A Neovim plugin for managing Docker containers, images, volumes, and networks directly from your editor.

## Features

- **Container Management**: Start, stop, and restart Docker containers
- **Multi-Resource View**: Browse containers, images, volumes, and networks
- **Docker Compose Support**: Automatically groups containers by compose project
- **Async Operations**: Non-blocking container operations

## Requirements

- Neovim 0.12 or higher
- [Docker](https://hub.docker.com/)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "HyperAfnan/docker-containers.nvim",
  dependencies = {
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
  requires = { 'akinsho/toggleterm.nvim' },
  config = function()
    require("docker-containers").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
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
    close = "q",
    help = "?",
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

- Terminal integration via [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
