-- Thin compatibility wrapper.
--
-- The real implementations of verify_or_find_label, get_root_file, and
-- find_root_via_subfiles have moved to the shared module
-- `latex_nav_core.latex`. This file re-exports them so existing require()
-- call sites keep working while downstream code migrates.

local M = {}

M.verify_or_find_label = function(filepath, target_line, label_id, window_size)
  return require("latex_nav_core.latex").verify_or_find_label(
    filepath, target_line, label_id, window_size
  )
end

M.get_root_file = function()
  return require("latex_nav_core.latex").get_root_file()
end

M.find_root_via_subfiles = function(filepath)
  return require("latex_nav_core.latex").find_root_via_subfiles(filepath)
end

return M
