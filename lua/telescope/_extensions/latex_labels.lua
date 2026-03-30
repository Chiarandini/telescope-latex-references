local telescope = require("telescope")

local DEFAULT_CONFIG = {
  -- "local"  -> hidden file next to the root .tex file: .main.tex.labels
  -- "global" -> stdpath("data")/cached_labels/<sha256>.labels
  cache_strategy = "global",

  -- ── Export settings ──────────────────────────────────────────────────────
  -- These control the behaviour of :LatexLabelsExport.
  -- All can be overridden in the format-selection UI; these act as defaults.
  export_include_line       = true,   -- include line numbers in exported records
  export_include_title      = true,   -- include label titles (context strings)
  export_include_file       = true,   -- include file paths in exported records
  export_use_relative_paths = false,  -- false → absolute paths, true → relative to project root
  export_exclude_files      = {},     -- list of Lua patterns; matching filenames are skipped

  -- Follow \include and \input directives when scanning
  recursive = true,

  -- Automatically regenerate the cache whenever a .tex file is saved
  auto_update = false,

  -- Search ±N lines around the cached position when a label seems to have moved
  enable_smart_jump = true,
  smart_jump_window = 200,

  -- Subfile toggle: manual root override and toggle key
  root_file          = "",        -- manual override: absolute path to the root .tex file
  subfile_toggle_key = "<C-g>",   -- key to toggle full-project↔this-file mode inside the picker

  -- Copy label reference to system clipboard without opening the file
  copy_label_key = "<C-y>",       -- key to yank the label id (e.g. "df:scheme") into the + register

  -- Optional transformation applied to a label before it is copied.
  -- Accepts either:
  --   • a table  { ["prefix:"] = "format string with %s" }
  --     e.g. { ["df:"] = "\\cref{%s}", ["ex:"] = "example~\\ref{%s}" }
  --   • a function(label: string) -> string
  -- When nil (default) the raw label id is copied unchanged.
  copy_transform = nil,

  -- Map LaTeX environment names to label prefixes.
  -- Used for the \begin{env}{Title}{label} pattern.
  transformations = {
    thm      = "th:",
    prop     = "pr:",
    defn     = "df:",
    lem      = "lm:",
    cor      = "co:",
    example  = "ex:",
    exercise = "x:",
  },

  -- Ordered list of capture patterns.
  -- Processing stops at the first "environment" match for a given line.
  patterns = {
    -- Custom envs with inline title + label: \begin{thm}{Snake Lemma}{snakeLem}
    { pattern = "\\begin{(%w+)}{(.-)}{(.-)}", type = "environment" },
    -- Standard bare label: \label{id}
    { pattern = "\\label{(.-)}", type = "standard" },
  },
}

-- Module-level config table (populated during setup)
local config = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

---Resolve the current project's root, load (or generate) its label cache,
---and open the interactive export UI.
local function export_labels()
  local cache     = require("telescope._extensions.latex_labels.cache")
  local scanner   = require("telescope._extensions.latex_labels.scanner")
  local utils     = require("telescope._extensions.latex_labels.utils")
  local export_ui = require("latex_nav_core.export_ui")

  local root_file = utils.get_root_file()
  if not root_file then
    vim.notify("[latex_labels] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  local cache_path = cache.get_cache_path(root_file, config.cache_strategy)
  local entries    = cache.read_cache(cache_path)

  if not entries then
    entries = scanner.scan_project(root_file, config)
    cache.write_cache(cache_path, entries)
  end

  if #entries == 0 then
    vim.notify("[latex_labels] No labels found for export.", vim.log.levels.WARN)
    return
  end

  export_ui.open(entries, root_file, {
    include_line       = config.export_include_line,
    include_title      = config.export_include_title,
    include_file       = config.export_include_file,
    use_relative_paths = config.export_use_relative_paths,
    exclude_files      = config.export_exclude_files,
  })
end

---Open the cache file for the current project in a read-only split.
local function inspect_cache()
  local cache = require("telescope._extensions.latex_labels.cache")
  local utils = require("telescope._extensions.latex_labels.utils")
  local root_file = utils.get_root_file()
  if not root_file then
    vim.notify("[latex_labels] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  local cache_path = cache.get_cache_path(root_file, config.cache_strategy)
  if vim.fn.filereadable(cache_path) == 0 then
    vim.notify(
      "[latex_labels] No cache found. Run :LatexLabelsUpdate to generate it.",
      vim.log.levels.WARN
    )
    return
  end

  vim.cmd("split " .. vim.fn.fnameescape(cache_path))
  vim.bo.readonly   = true
  vim.bo.modifiable = false
end

---Run a full cache regeneration for the project rooted at the current buffer.
local function update_cache()
  local cache   = require("telescope._extensions.latex_labels.cache")
  local scanner = require("telescope._extensions.latex_labels.scanner")
  local utils   = require("telescope._extensions.latex_labels.utils")
  local root_file = utils.get_root_file()
  if not root_file then
    vim.notify("[latex_labels] No file associated with current buffer.", vim.log.levels.WARN)
    return
  end

  local entries    = scanner.scan_project(root_file, config)
  local cache_path = cache.get_cache_path(root_file, config.cache_strategy)
  local ok, err    = cache.write_cache(cache_path, entries)

  if ok then
    vim.notify(
      string.format("[latex_labels] Cache updated (%d labels).", #entries),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      "[latex_labels] Failed to write cache: " .. (err or "unknown error"),
      vim.log.levels.ERROR
    )
  end
end

-- ─── Extension registration ───────────────────────────────────────────────────

return telescope.register_extension({

  setup = function(ext_config, _telescope_config)
    config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, ext_config or {})

    -- :LatexLabelsExport — export labels to JSON / CSV / TSV / TXT via UI
    vim.api.nvim_create_user_command("LatexLabelsExport", function()
      export_labels()
    end, { desc = "Export LaTeX labels to JSON / CSV / TSV / TXT" })

    -- :LatexLabelsUpdate — force-regenerate the cache for the current project
    vim.api.nvim_create_user_command("LatexLabelsUpdate", function()
      update_cache()
    end, { desc = "Regenerate telescope-latex-labels cache for current project" })

    -- :LatexLabelsInspect — open the cache file for the current project
    vim.api.nvim_create_user_command("LatexLabelsInspect", function()
      inspect_cache()
    end, { desc = "Open the telescope-latex-labels cache file in a read-only split" })

    -- :LatexLabelsWipeAll — delete every cache file written by this plugin
    vim.api.nvim_create_user_command("LatexLabelsWipeAll", function()
      local cache = require("telescope._extensions.latex_labels.cache")
      local count, err = cache.wipe_all_caches(config.cache_strategy)
      if err then
        vim.notify("[latex_labels] " .. err, vim.log.levels.WARN)
      else
        vim.notify(
          string.format("[latex_labels] Wiped %d cache file(s).", count),
          vim.log.levels.INFO
        )
      end
    end, { desc = "Delete all telescope-latex-labels cache files" })

    -- Optional: auto-regenerate cache on every .tex save
    if config.auto_update then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group   = vim.api.nvim_create_augroup("LatexLabelsAutoUpdate", { clear = true }),
        pattern = "*.tex",
        desc    = "telescope-latex-labels: auto-regenerate cache on save",
        callback = function()
          update_cache()
        end,
      })
    end
  end,

  exports = {
    latex_labels = function(opts)
      require("telescope._extensions.latex_labels.picker").open(opts or {}, config)
    end,
  },
})
