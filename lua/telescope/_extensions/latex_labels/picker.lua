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

        local entry       = selection.value
        local target_line = entry.line

        if config.enable_smart_jump then
          -- Run the search BEFORE opening the file: verify_or_find_label handles
          -- unloaded files via disk I/O so we don't have to open it first.
          local found = utils.verify_or_find_label(
            entry.filename, entry.line, entry.id, config.smart_jump_window
          )

          if found and found ~= entry.line then
            -- Label has shifted — jump to new position and patch the cache
            target_line = found
            vim.notify("[latex_labels] Label shifted. Cache auto-updated.", vim.log.levels.INFO)

            local all = cache.read_cache(cache_path)
            if all then
              for _, e in ipairs(all) do
                if e.line == entry.line and e.id == entry.id and e.filename == entry.filename then
                  e.line = found
                  break
                end
              end
              cache.write_cache(cache_path, all)
            end

          elseif not found then
            -- Label not found anywhere in the search window
            vim.notify(
              "[latex_labels] [Warning] Label not found at cached location. "
                .. "Please run :LatexLabelsUpdate.",
              vim.log.levels.WARN
            )
            -- target_line stays as entry.line (best-effort jump)
          end
          -- found == entry.line: exact match, silent jump
        end

        -- Open the target file when it differs from the current buffer
        local current = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
        if current ~= entry.filename then
          vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
        end

        vim.api.nvim_win_set_cursor(0, { target_line, 0 })
        vim.cmd("normal! zz")
      end)

      return true
    end,
  }):find()
end

return M
