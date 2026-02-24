local M = {}

local actions      = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders      = require("telescope.finders")
local pickers      = require("telescope.pickers")
local conf         = require("telescope.config").values

local cache   = require("telescope._extensions.latex_labels.cache")
local scanner = require("telescope._extensions.latex_labels.scanner")
local utils   = require("telescope._extensions.latex_labels.utils")

---Build the display string shown in the Telescope prompt.
---Format: "[label_id] :: context  (filename:line)"
---@param entry table  { id, context, filename, line }
---@return string
local function make_display(entry)
  local short = vim.fn.fnamemodify(entry.filename, ":t:r")
  return string.format("[%s] :: %s  (%s:%d)", entry.id, entry.context, short, entry.line)
end

---Open the latex-labels Telescope picker for the current LaTeX project.
---@param opts   table  Passed through to pickers.new().
---@param config table  Plugin configuration (merged defaults + user overrides).
M.open = function(opts, config)
  local root_file = utils.get_root_file()
  if not root_file then
    vim.notify("[latex_labels] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  local cache_path = cache.get_cache_path(root_file, config.cache_strategy)
  local entries    = cache.read_cache(cache_path)

  if not entries then
    -- Cache miss: scan the project now and persist the result
    entries = scanner.scan_project(root_file, config)
    cache.write_cache(cache_path, entries)
  end

  if #entries == 0 then
    vim.notify("[latex_labels] No labels found in this project.", vim.log.levels.INFO)
    return
  end

  pickers.new(opts, {
    prompt_title = "LaTeX Labels",

    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value    = entry,
          display  = make_display(entry),
          -- Ordinal includes both id and context so users can filter by either
          ordinal  = entry.id .. " " .. entry.context,
          filename = entry.filename,
          lnum     = entry.line,
        }
      end,
    }),

    sorter    = conf.generic_sorter(opts),
    previewer = conf.grep_previewer(opts),

    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if not selection then return end

        local entry = selection.value

        -- Open the target file when it differs from the current buffer
        local current = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
        if current ~= entry.filename then
          vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
        end

        vim.api.nvim_win_set_cursor(0, { entry.line, 0 })
        vim.cmd("normal! zz")
      end)

      return true
    end,
  }):find()
end

return M
