local M = {}

-- How many preceding lines to inspect when inferring context for a bare \label{}
local LOOKBACK_SIZE = 8

---Extract a human-readable context string from a single line of LaTeX source.
---Priority order:
---  1. First brace group content  : \cmd{context}  or  \begin{env}{context}
---  2. First bracket group content: \cmd[context]
---  3. Command name alone         : \cmd
---  4. Raw text (truncated to 80 chars)
---@param line string
---@return string
local function extract_line_context(line)
  local trimmed = vim.trim(line)

  -- 1. First non-empty brace group
  local brace = trimmed:match("{(.-)}")
  if brace and vim.trim(brace) ~= "" then return vim.trim(brace) end

  -- 2. First bracket group (optional arguments like \Question[Short title])
  local bracket = trimmed:match("%[(.-)%]")
  if bracket and vim.trim(bracket) ~= "" then return vim.trim(bracket) end

  -- 3. Command name
  local cmd = trimmed:match("^\\(%a+)")
  if cmd then return "\\" .. cmd end

  -- 4. Raw text
  return trimmed:sub(1, 80)
end

---Walk a rolling lookback buffer (oldest-first) in reverse and return the
---context string from the first non-blank, non-comment line found.
---Returns "Label" if no useful line is found.
---@param buf table  List of lines, oldest at index 1.
---@return string
local function lookback_context(buf)
  for i = #buf, 1, -1 do
    local trimmed = vim.trim(buf[i])
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "%" then
      return extract_line_context(trimmed)
    end
  end
  return "Label"
end

---Resolve an \include / \input argument to an absolute path.
---Appends ".tex" when no extension is present (standard LaTeX behaviour).
---@param root_dir string  Directory of the project root file.
---@param inc string       Raw argument from \include or \input.
---@return string
local function resolve_inc(root_dir, inc)
  local path = root_dir .. "/" .. vim.trim(inc)
  if not path:match("%.%w+$") then
    path = path .. ".tex"
  end
  return path
end

---Recursively scan one file, appending label entries to `results`.
---@param filepath string   Absolute path to the file to scan.
---@param root_dir string   Directory of the project root (for resolving includes).
---@param config   table    Plugin configuration.
---@param results  table    Accumulator list.
---@param visited  table    Set of already-visited absolute paths (cycle guard).
local function scan(filepath, root_dir, config, results, visited)
  local abs_path = vim.fn.fnamemodify(filepath, ":p")

  if visited[abs_path] then return end
  visited[abs_path] = true

  local f = io.open(abs_path, "r")
  if not f then return end

  local lnum   = 0
  local recent = {}  -- Rolling lookback buffer (oldest at index 1)

  for line in f:lines() do
    lnum = lnum + 1

    -- Maintain rolling buffer (trim to LOOKBACK_SIZE)
    table.insert(recent, line)
    if #recent > LOOKBACK_SIZE then
      table.remove(recent, 1)
    end

    -- ── 1. Recursion via \include / \input ────────────────────────────────
    if config.recursive then
      local inc = line:match("\\include%s*{(.-)}")
               or line:match("\\input%s*{(.-)}")
      if inc and vim.trim(inc) ~= "" then
        local next_file = resolve_inc(root_dir, inc)
        scan(next_file, root_dir, config, results, visited)
      end
    end

    -- ── 2. Pattern matching ───────────────────────────────────────────────
    for _, p in ipairs(config.patterns) do

      if p.type == "environment" then
        -- Expected format on one line: \begin{env}{Title}{label}
        local env, title, label = line:match(p.pattern)
        if env and label and vim.trim(label) ~= "" then
          local prefix = config.transformations[env]
          if prefix then
            table.insert(results, {
              line     = lnum,
              id       = prefix .. vim.trim(label),
              context  = (vim.trim(title) ~= "" and vim.trim(title)) or env,
              filename = abs_path,
            })
            break  -- Stop checking further patterns for this line
          end
        end

      elseif p.type == "standard" then
        -- \label{id}  — context derived by looking back through recent lines
        local label = line:match(p.pattern)
        if label and vim.trim(label) ~= "" then
          -- Build lookback buffer excluding the current line
          local buf = {}
          for i = 1, #recent - 1 do
            buf[i] = recent[i]
          end
          table.insert(results, {
            line     = lnum,
            id       = vim.trim(label),
            context  = lookback_context(buf),
            filename = abs_path,
          })
        end
      end

    end
  end

  f:close()
end

---Scan a LaTeX project starting from `root_file`, recursively following
---\include and \input directives (when config.recursive is true).
---
---@param root_file string  Absolute path to the root .tex file.
---@param config    table   Plugin configuration.
---@return table  List of { line, id, context, filename }.
M.scan_project = function(root_file, config)
  local results  = {}
  local visited  = {}
  local root_dir = vim.fn.fnamemodify(root_file, ":h")
  scan(root_file, root_dir, config, results, visited)
  return results
end

return M
