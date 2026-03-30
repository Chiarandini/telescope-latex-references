-- Minimal Neovim init for running tests headlessly.
-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"
--
-- The script searches the most common lazy.nvim and packer paths for plenary.
-- Adjust the paths below if your plugin manager stores plugins elsewhere.

local function add_if_dir(p)
  if vim.fn.isdirectory(p) == 1 then
    vim.opt.rtp:prepend(p)
    return true
  end
  return false
end

-- Try common locations for plenary.nvim
local data = vim.fn.stdpath("data")
local plenary_candidates = {
  data .. "/lazy/plenary.nvim",
  data .. "/site/pack/packer/start/plenary.nvim",
  data .. "/plugged/plenary.nvim",
}

local found = false
for _, p in ipairs(plenary_candidates) do
  if add_if_dir(p) then
    found = true
    break
  end
end

if not found then
  error("plenary.nvim not found. Add its path to tests/minimal_init.lua")
end

-- Add the plugin itself
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Add latex-nav-core.nvim (sibling directory) so tests can require its modules
local core_dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":h") .. "/latex-nav-core.nvim"
add_if_dir(core_dir)
