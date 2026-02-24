# Design Document: telescope-latex-labels.nvim

## 1. Overview
`telescope-latex-labels.nvim` is a high-performance Neovim plugin for navigating LaTeX labels. It mirrors the architecture of `telescope-cached-headings` but is specialized for recursive file scanning and "Implicit Label" transformation (e.g., `thm` $\to$ `th:`).

It uses a **Plaintext Cache** for maximum speed and compatibility with your existing tooling ecosystem.

## 2. Core Logic & Workflow

### 2.1 The "Picker" Workflow
Command: `:Telescope latex_labels`

1.  **Context**: Identify the Root LaTeX file.
2.  **Cache Resolution**:
    *   Calculate the cache path using the same logic as `cached_headings`, but with extension `.labels`.
    *   **Hit**: Read lines, split by `|`, display immediately.
    *   **Miss**: Trigger `scanner.scan_project()`, write to cache, then display.
3.  **Display**:
    *   Format: `[Prefix:Label] :: [Context]`
    *   *Note*: The recursive nature means we must also store the **File Path** in the cache, unlike the headings plugin which was single-file.

### 2.2 The "Update" Workflow
Command: `:LatexLabelsUpdate`

1.  Run the recursive scanner from the project root.
2.  Overwrite the `*.labels` cache file.
3.  Notify user.

## 3. Cache Format (Plaintext)

To match your existing plugin, we use a pipe-separated format.
Since this plugin supports recursive scanning, we **must** store the absolute path to the file where the label is defined.

**Format:**
`line_num|label_id|context|absolute_filepath`

**Example:**
```text
50|th:snakeLem|Snake Lemma|/Users/me/thesis/chapter1.tex
102|pr:bigProp|Main Proposition|/Users/me/thesis/chapter1.tex
15|df:myDef|Definition of X|/Users/me/thesis/chapter2.tex
```

## 4. Configuration

```lua
local DEFAULT_CONFIG = {
  -- "local"  -> hidden file: .filename.tex.labels
  -- "global" -> stdpath("data")/cached_headings/<sha256>.labels
  cache_strategy    = "global",

  -- Recursive Scanning
  recursive = true,

  -- Transformations: Map environment -> prefix
  transformations = {
    thm      = "th:",
    prop     = "pr:",
    defn     = "df:",
    lem      = "lm:",
    cor      = "co:",
    example  = "ex:",
    exercise = "x:",
  },

  -- Capture Patterns
  patterns = {
    -- Custom Envs: \begin{thm}{Title}{label}
    { pattern = "\\begin{(%w+)}{(.-)}{(.-)}", type = "environment" },
    -- Standard: \label{x}
    { pattern = "\\label{(.-)}", type = "standard" }
  }
}
```

## 5. Implementation Details

### 5.1 `cache.lua` (Adapted for Labels)

This is the exact counterpart to your provided code, adapted for the 4-column format.

```lua
local M = {}

---@param filepath string  Absolute path to the ROOT file.
---@param strategy string  "local" | "global"
---@return string
M.get_cache_path = function(filepath, strategy)
  -- EXACT SAME LOGIC as your existing plugin
  if strategy == "local" then
    local dir      = vim.fn.fnamemodify(filepath, ":h")
    local filename = vim.fn.fnamemodify(filepath, ":t")
    return dir .. "/." .. filename .. ".labels" -- <--- Different Extension
  else
    local cache_dir = vim.fn.stdpath("data") .. "/cached_labels" -- <--- Different Dir (optional, or keep same)
    vim.fn.mkdir(cache_dir, "p")
    local hash = vim.fn.sha256(filepath)
    return cache_dir .. "/" .. hash .. ".labels"
  end
end

---Read cache.
---Format: line|id|context|path
---@return table|nil
M.read_cache = function(cache_path)
  local file = io.open(cache_path, "r")
  if not file then return nil end

  local entries = {}
  for raw in file:lines() do
    if raw:sub(1, 1) ~= "#" then
      -- Match 4 columns
      local line, id, ctx, path = raw:match("^(%d+)|(.-)|(.-)|(.+)$")
      if line and id then
        table.insert(entries, {
          line = tonumber(line),
          id = id,
          context = ctx,
          filename = path -- Telescope expects 'filename' for jumping
        })
      end
    end
  end
  file:close()
  return entries
end

---Write cache.
---@param entries table List of { line, id, context, filename }
M.write_cache = function(cache_path, entries)
  local file = io.open(cache_path, "w")
  if not file then return false, "Error opening cache" end

  for _, e in ipairs(entries) do
    -- Ensure we don't write newlines inside the text fields to break format
    local clean_ctx = e.context:gsub("\n", " ")
    file:write(string.format("%d|%s|%s|%s\n", e.line, e.id, clean_ctx, e.filename))
  end
  file:close()
  return true
end
```

### 5.2 `scanner.lua` (The Recursive Logic)

```lua
local M = {}
local Path = require("plenary.path")

M.scan_project = function(root_file, config)
  local results = {}
  local visited = {}

  local function scan(filepath)
    local abs_path = Path:new(filepath):absolute()
    if visited[abs_path] then return end
    visited[abs_path] = true

    local f = io.open(abs_path, "r")
    if not f then return end

    local lnum = 0
    for line in f:lines() do
      lnum = lnum + 1

      -- 1. Recursion
      local inc = line:match("\\include{(.-)}") or line:match("\\input{(.-)}")
      if inc and config.recursive then
        -- Logic to resolve relative path from root directory
        local root_dir = vim.fn.fnamemodify(root_file, ":h")
        -- Simple join (might need robust path joining utils)
        local next_file = root_dir .. "/" .. inc
        if not next_file:match("%.tex$") then next_file = next_file .. ".tex" end
        scan(next_file)
      end

      -- 2. Parsing
      for _, p in ipairs(config.patterns) do
        if p.type == "environment" then
          local env, title, label = line:match(p.pattern)
          if env and label then
             local prefix = config.transformations[env]
             if prefix then
               table.insert(results, {
                 line = lnum,
                 id = prefix .. label,
                 context = title,
                 filename = abs_path
               })
               break -- Stop checking other patterns for this line
             end
          end
        elseif p.type == "standard" then
          local label = line:match(p.pattern)
          if label then
            table.insert(results, {
               line = lnum,
               id = label,
               context = "Label",
               filename = abs_path
            })
          end
        end
      end
    end
    f:close()
  end

  scan(root_file)
  return results
end
```

## 6. Integration & Independence

*   **Independence**: Since we use different file extensions (`.headings` vs `.labels`), this plugin works perfectly fine even if `telescope-cached-headings` is not installed.
*   **Cooperation**: If you set `cache_strategy = "global"` for both, all your metadata lives in `stdpath("data")` (though in separate folders or files).
*   **Code Sharing**: The `cache.lua` is nearly identical. If you combine these into a single "suite" later, you can refactor `cache.lua` to accept a `parser_func` and `serializer_func`, but keeping them copy-pasted for now ensures strict independence as requested.
