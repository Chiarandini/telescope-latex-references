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

--- Return the 1-based index of the first entry in `entries` whose absolute
--- filename matches `current_filepath`. Falls back to 1 if none found.
---@param entries          table   List of label entries.
---@param current_filepath string  Normalised absolute path of the current subfile.
---@return integer
local function find_default_selection(entries, current_filepath)
  for i, e in ipairs(entries) do
    if e.filename == current_filepath then return i end
  end
  return 1
end

---Open the latex-labels Telescope picker for the current LaTeX project.
---@param opts      table      Passed through to pickers.new().
---@param config    table      Plugin configuration (merged defaults + user overrides).
---@param overrides table|nil  Internal overrides for toggle: { mode, origin_filepath, root_filepath }
M.open = function(opts, config, overrides)
  overrides = overrides or {}
  local mode = overrides.mode or "global"

  -- The file the user was actually editing (constant across toggles)
  local origin_filepath = overrides.origin_filepath
    or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")

  if not origin_filepath or origin_filepath == "" then
    vim.notify("[latex_labels] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  -- ── Subfile / root detection (only on the initial call) ──────────────────
  local root_filepath = overrides.root_filepath
  if root_filepath == nil then
    root_filepath = utils.get_root_file()

    -- get_root_file() falls back to the current file when vimtex is absent.
    -- In that case, try \documentclass[...]{subfiles} to detect the root.
    if root_filepath == origin_filepath then
      local sub_root = utils.find_root_via_subfiles(origin_filepath)
      if sub_root then root_filepath = sub_root end
    end

    -- config.root_file as manual fallback
    if root_filepath == origin_filepath
        and config.root_file and config.root_file ~= "" then
      local abs = vim.fn.fnamemodify(config.root_file, ":p")
      if vim.fn.filereadable(abs) == 1 then root_filepath = abs end
    end
  end

  local is_subfile = root_filepath ~= nil and root_filepath ~= origin_filepath

  -- ── Choose scan entry point and cache key ─────────────────────────────────
  local scan_from, cache_from
  if mode == "local" then
    scan_from  = origin_filepath
    cache_from = origin_filepath
  else
    scan_from  = root_filepath or origin_filepath
    cache_from = root_filepath or origin_filepath
  end

  local cache_path = cache.get_cache_path(cache_from, config.cache_strategy)
  local entries    = cache.read_cache(cache_path)

  if not entries then
    -- Cache miss: scan and persist
    local scan_config = mode == "local"
      and vim.tbl_extend("force", config, { recursive = false })
      or config
    entries = scanner.scan_project(scan_from, scan_config)
    cache.write_cache(cache_path, entries)
  end

  if #entries == 0 then
    vim.notify("[latex_labels] No labels found.", vim.log.levels.INFO)
    return
  end

  -- Smart scroll: in global mode when editing a subfile, pre-position on the
  -- first label that belongs to the current file
  local default_idx = 1
  if mode == "global" and is_subfile then
    default_idx = find_default_selection(entries, origin_filepath)
  end

  -- Prompt title shows current mode and toggle hint
  local toggle_key = config.subfile_toggle_key or "<C-g>"
  local prompt_title
  if is_subfile or mode == "local" then
    if mode == "global" then
      prompt_title = "LaTeX Labels (full project) [" .. toggle_key .. ": this file]"
    else
      prompt_title = "LaTeX Labels (this file) [" .. toggle_key .. ": full project]"
    end
  else
    prompt_title = "LaTeX Labels"
  end

  pickers.new(opts, {
    prompt_title            = prompt_title,
    default_selection_index = default_idx,

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

    attach_mappings = function(prompt_bufnr, map)
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

      -- Toggle key: only shown when there is a subfile/root relationship
      if is_subfile or mode == "local" then
        local opposite = mode == "global" and "local" or "global"
        local toggle_fn = function()
          actions.close(prompt_bufnr)
          vim.schedule(function()
            M.open(opts, config, {
              mode            = opposite,
              origin_filepath = origin_filepath,
              root_filepath   = root_filepath,
            })
          end)
        end
        map("i", toggle_key, toggle_fn)
        map("n", toggle_key, toggle_fn)
      end

      -- Copy label reference to system clipboard
      local copy_key = config.copy_label_key or "<C-y>"
      local copy_fn = function()
        local selection = action_state.get_selected_entry()
        if not selection then return end
        local label = selection.value.id
        vim.fn.setreg("+", label)
        vim.fn.setreg('"', label)
        actions.close(prompt_bufnr)
        vim.notify('[latex_labels] Copied "' .. label .. '" to clipboard.', vim.log.levels.INFO)
      end
      map("i", copy_key, copy_fn)
      map("n", copy_key, copy_fn)

      return true
    end,
  }):find()
end

return M
