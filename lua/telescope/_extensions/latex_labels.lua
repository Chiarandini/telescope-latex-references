local telescope = require("telescope")
local picker    = require("telescope._extensions.latex_labels.picker")
local cache     = require("telescope._extensions.latex_labels.cache")
local scanner   = require("telescope._extensions.latex_labels.scanner")
local utils     = require("telescope._extensions.latex_labels.utils")

local DEFAULT_CONFIG = {
  -- "local"  -> hidden file next to the root .tex file: .main.tex.labels
  -- "global" -> stdpath("data")/cached_labels/<sha256>.labels
  cache_strategy = "global",

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

---Run a full cache regeneration for the project rooted at the current buffer.
local function update_cache()
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

    -- :LatexLabelsUpdate — force-regenerate the cache for the current project
    vim.api.nvim_create_user_command("LatexLabelsUpdate", function()
      update_cache()
    end, { desc = "Regenerate telescope-latex-labels cache for current project" })

    -- :LatexLabelsWipeAll — delete every cache file written by this plugin
    vim.api.nvim_create_user_command("LatexLabelsWipeAll", function()
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
      picker.open(opts or {}, config)
    end,
  },
})
