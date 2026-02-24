local M = {}

---Determine the LaTeX project root file.
---
---Resolution order:
---  1. vimtex: vim.b.vimtex.tex  (the main file vimtex has identified)
---  2. Current buffer's file     (fallback when vimtex is absent / not active)
---
---@return string|nil  Absolute path to the root file, or nil if nothing is open.
M.get_root_file = function()
  -- vimtex stores project info in the buffer-local variable b:vimtex.
  -- We pcall to avoid errors when vimtex is not installed or the variable is
  -- unset (e.g. in a non-tex buffer).
  local ok, vimtex = pcall(function() return vim.b.vimtex end)
  if ok and type(vimtex) == "table" then
    local tex = vimtex.tex
    if type(tex) == "string" and tex ~= "" then
      return vim.fn.fnamemodify(tex, ":p")
    end
  end

  -- Fallback: treat the current buffer's file as the root
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then return nil end
  return vim.fn.fnamemodify(filepath, ":p")
end

return M
