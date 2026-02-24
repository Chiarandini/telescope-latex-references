local M = {}

---Return the path where the cache file for `filepath` should be stored.
---
---  "local"  -> same directory as the file, hidden: .filename.tex.labels
---  "global" -> stdpath("data")/cached_labels/<sha256>.labels
---
---@param filepath string  Absolute path to the ROOT .tex file.
---@param strategy string  "local" | "global"
---@return string
M.get_cache_path = function(filepath, strategy)
  if strategy == "local" then
    local dir      = vim.fn.fnamemodify(filepath, ":h")
    local filename = vim.fn.fnamemodify(filepath, ":t")
    return dir .. "/." .. filename .. ".labels"
  else
    local cache_dir = vim.fn.stdpath("data") .. "/cached_labels"
    vim.fn.mkdir(cache_dir, "p")
    local hash = vim.fn.sha256(filepath)
    return cache_dir .. "/" .. hash .. ".labels"
  end
end

---Read a cache file and return a list of label entries.
---Each non-comment line must have the format: line_num|label_id|context|filepath
---
---@param cache_path string
---@return table|nil  List of { line, id, context, filename } or nil if file does not exist.
M.read_cache = function(cache_path)
  local file = io.open(cache_path, "r")
  if not file then return nil end

  local entries = {}
  for raw in file:lines() do
    if raw:sub(1, 1) ~= "#" then
      local line, id, ctx, path = raw:match("^(%d+)|(.-)|(.-)|(.+)$")
      if line and id and id ~= "" then
        table.insert(entries, {
          line     = tonumber(line),
          id       = id,
          context  = ctx or "",
          filename = path,
        })
      end
    end
  end

  file:close()
  return entries
end

---Write a list of label entries to a cache file.
---
---@param cache_path string
---@param entries table  List of { line, id, context, filename }
---@return boolean, string|nil  success, error_message
M.write_cache = function(cache_path, entries)
  local file = io.open(cache_path, "w")
  if not file then
    return false, "Could not open cache file for writing: " .. cache_path
  end

  for _, e in ipairs(entries) do
    -- Sanitise fields: strip newlines and pipes to preserve format integrity
    local clean_id  = e.id:gsub("[|\n]", " ")
    local clean_ctx = e.context:gsub("[|\n]", " ")
    file:write(string.format("%d|%s|%s|%s\n", e.line, clean_id, clean_ctx, e.filename))
  end

  file:close()
  return true, nil
end

---Delete all cache files managed by this plugin.
---Only supported for the "global" strategy.
---
---@param strategy string  "local" | "global"
---@return integer, string|nil  number of files deleted, error message or nil
M.wipe_all_caches = function(strategy)
  if strategy ~= "global" then
    return 0, "wipe_all is only supported for the 'global' cache strategy. "
      .. "Delete *.labels files manually from your project directories."
  end

  local cache_dir = vim.fn.stdpath("data") .. "/cached_labels"
  local files     = vim.fn.glob(cache_dir .. "/*.labels", false, true)
  local count     = 0
  for _, f in ipairs(files) do
    if vim.fn.delete(f) == 0 then
      count = count + 1
    end
  end
  return count, nil
end

return M
