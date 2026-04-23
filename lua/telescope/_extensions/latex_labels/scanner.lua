-- Thin compatibility wrapper.
--
-- The real implementation now lives in `latex_nav_core.latex_labels.scanner`.
-- Re-exported so existing
-- `require("telescope._extensions.latex_labels.scanner")` call sites keep
-- working.

return require("latex_nav_core.latex_labels.scanner")
