local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
  if vim.v.shell_error ~= 0 then
    -- Offline, or no git. Say so once and carry on as ordinary neovim
    -- rather than throwing a wall of Lua at someone who is mid-install.
    vim.schedule(function()
      vim.notify(
        "LazyVim not installed yet (" .. vim.trim(out or "") .. ")\n"
          .. "Connect to a network and restart nvim to finish setup.",
        vim.log.levels.WARN
      )
    end)
    require("config.options")
    return
  end
end
vim.opt.rtp:prepend(lazypath)

local ok, lazy = pcall(require, "lazy")
if not ok then
  require("config.options")
  return
end

lazy.setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = true, notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
})

require("config.options")
