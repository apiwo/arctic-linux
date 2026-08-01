-- Applied whether or not LazyVim managed to install, so nvim is usable
-- either way.
local o = vim.opt

o.number = true
o.relativenumber = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false
o.ignorecase = true
o.smartcase = true
o.termguicolors = true
o.signcolumn = "yes"
o.updatetime = 200
o.undofile = true
o.scrolloff = 4

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
