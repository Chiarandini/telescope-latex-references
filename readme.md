# telescope-latex-labels.nvim

A Telescope extension for fast LaTeX label navigation across multi-file projects.
Mirrors the architecture of `telescope-cached-headings` but specialised for
recursive project scanning and automatic label-prefix transformation (e.g.
`thm` → `th:snakeLem`).

Like its sibling plugin, results are written to a small plaintext cache on first
use so that the picker is essentially instant on large projects — no live regex
scan on every open.

## Features

- **Instant opening** after first use — subsequent opens read the cache, not the files
- **Recursive scanning** — follows `\include` and `\input` directives automatically
- **Prefix transformation** — maps environment names to label prefixes
  (`thm` → `th:`, `defn` → `df:`, etc.)
- **Smart context** — for bare `\label{id}` lines, looks back through the
  preceding lines to find a meaningful context (section title, question text,
  environment name, or any custom command)
- **vimtex-aware** — uses `b:vimtex.tex` to find the project root when vimtex
  is active; falls back to the current buffer
- **Smart Jump** — automatically finds a label that has shifted since the cache
  was written, silently patches the cache entry, and warns when a label cannot
  be located at all
- **Multi-file jump** — opens the correct file automatically when a label lives
  in a file other than the current buffer
- **Two cache strategies**: global (tidy) or local (inspectable)
- **Auto-update** on save via `BufWritePost` (opt-in)
- **Wipe all caches** in one command when you need a clean slate
- **Subfile toggle** — when editing a LaTeX subfile (using the `subfiles` package),
  press a key to switch between a full-project view and a view of only the labels
  defined in your current file, with the cursor pre-positioned on the first label
  from your file in the full-project view
- **Copy with transform** — press a key inside the picker to copy a label
  reference to the system clipboard; an optional `copy_transform` hook lets you
  wrap the label automatically (e.g. `df:grp` → `\cref{df:grp}`)

## Requirements

- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [lervag/vimtex](https://github.com/lervag/vimtex) *(optional — enables
  automatic root-file detection for multi-file projects)*

## Why so fast?

1. **Streaming with `io.lines()`** — files are never fully loaded into memory.
   The scanner reads one line at a time from the C standard library.

2. **Early-exit matching** — the `\label{` pattern anchors to a literal prefix,
   so the vast majority of lines are rejected in O(1).

3. **Caching** — after the first scan the results are written to a flat text
   file (`line|id|context|path` format). Subsequent picker opens are just a
   cache read; no files are touched.

4. **Cycle-guarded recursion** — `\include` / `\input` graphs are traversed
   with a visited-set so each file is scanned exactly once regardless of how the
   project is structured.

## Installation

**lazy.nvim**

```lua
{
  "Chiarandini/telescope-latex-labels.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("telescope").load_extension("latex_labels")
  end,
}
```

**packer.nvim**

```lua
use {
  "Chiarandini/telescope-latex-labels.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("telescope").load_extension("latex_labels")
  end,
}
```

## Setup

Pass options inside `telescope.setup()`:

```lua
require("telescope").setup({
  extensions = {
    latex_labels = {
      -- all keys are optional; defaults shown below
      cache_strategy    = "global",
      recursive         = true,
      auto_update       = false,
      enable_smart_jump = true,
      smart_jump_window = 200,

      -- Subfile toggle: manual root override and toggle key
      root_file          = "",
      subfile_toggle_key = "<C-g>",

      -- Copy label key and optional transformation hook
      copy_label_key = "<C-y>",
      -- copy_transform: nil (raw label), a prefix→format table, or a function.
      -- Example table (see "Copy Label" section below for details):
      -- copy_transform = {
      --   ["df:"] = "\\cref{%s}", ["lm:"] = "\\cref{%s}",
      --   ["eq:"] = "equation~\\eqref{%s}",
      -- },

      -- Map environment names to label prefixes.
      -- Applied when the pattern \begin{env}{Title}{label} is matched.
      transformations = {
        thm      = "th:",
        prop     = "pr:",
        defn     = "df:",
        lem      = "lm:",
        cor      = "co:",
        example  = "ex:",
        exercise = "x:",
      },

      -- Ordered pattern list. Processing stops at the first "environment"
      -- match for a given line.
      patterns = {
        { pattern = "\\begin{(%w+)}{(.-)}{(.-)}", type = "environment" },
        { pattern = "\\label{(.-)}", type = "standard" },
      },
    },
  },
})

require("telescope").load_extension("latex_labels")
```

Suggested keybindings:

```lua
vim.keymap.set("n", "<leader>fl",
  "<cmd>Telescope latex_labels<cr>",
  { desc = "Find LaTeX labels" })

vim.keymap.set("n", "<leader>fL",
  "<cmd>LatexLabelsUpdate<cr>",
  { desc = "Update LaTeX labels cache" })
```

## Usage

```
:Telescope latex_labels
```

- The first time you open the picker the project is scanned automatically and
  the cache is written. All subsequent opens read the cache directly.
- Each entry is displayed as `[label_id] :: context  (filename:line)`.
- Selecting an entry opens the correct file (if necessary) and jumps to the
  label's line.

To force-rebuild the cache after adding or renaming labels:

```
:LatexLabelsUpdate
```

To delete every cache file and start fresh:

```
:LatexLabelsWipeAll
```

## Label patterns

### Environment pattern

Matches labels declared inline with a title on one line:

```latex
\begin{thm}{Snake Lemma}{snakeLem}
```

The environment name is looked up in `transformations`. If a prefix is found,
the entry is stored as `th:snakeLem` with context `Snake Lemma`. Unknown
environments (not in `transformations`) are silently skipped by this pattern.

### Standard pattern

Matches any bare `\label{id}`, regardless of what surrounds it:

```latex
\Question[Why is the sky blue?]
  Some question text here.
  \label{q:sky}
```

The plugin looks back through the preceding lines to infer a context string.
It tries (in order):

1. First brace group on the preceding line — `{Why is the sky blue?}`
2. First bracket group — `[Why is the sky blue?]`
3. Command name — `\Question`
4. Raw line text (truncated to 80 characters)

This handles `\Question`, `\exercise`, `\section`, `\begin{...}`, and any
other custom LaTeX command gracefully without any configuration.

## Adding custom environments

Add entries to the `transformations` table and, if your environment uses a
different signature, add a custom pattern:

```lua
transformations = {
  -- built-ins
  thm = "th:", defn = "df:",
  -- your custom environments
  myEnv = "my:",
},
patterns = {
  -- built-in: \begin{env}{Title}{label}
  { pattern = "\\begin{(%w+)}{(.-)}{(.-)}", type = "environment" },
  -- custom: \begin{env}[label]{Title}
  { pattern = "\\begin{(%w+)}%[(.-)%]{(.-)}", type = "environment" },
  -- standard fallback
  { pattern = "\\label{(.-)}", type = "standard" },
},
```

## Smart Jump

When you select a label the plugin verifies whether the cached line number still
holds the expected label in the target file:

| Situation | Behaviour |
|---|---|
| Exact match | Silent jump |
| Label shifted | Jump to new position, auto-patch the cache entry, print info message |
| Label missing | Jump to cached line, warn and ask you to run `:LatexLabelsUpdate` |

Set `enable_smart_jump = false` to skip verification and always jump directly
to the cached line number.

**How labels are located:** the search looks for `{label_id}` as a substring of
each line. For prefix-transformed labels (e.g. id `th:snakeLem` produced from
`\begin{thm}{...}{snakeLem}`) the search also tries the raw suffix after the
last colon (`{snakeLem}`), so environment-inline labels are found correctly.

If the file is already open in a buffer the Neovim buffer API is used (no disk
I/O). For files not yet loaded, the search streams the relevant line window
directly from disk so no extra buffer is opened.

## Subfile Toggle

If you work with the LaTeX [`subfiles`](https://ctan.org/pkg/subfiles) package,
the plugin detects when you are editing a subfile by checking three sources in
order:

1. **vimtex** — if vimtex is active, `b:vimtex.tex` already points to the root
2. **`\documentclass[root.tex]{subfiles}`** — parsed from the first 20 lines of
   the current file when vimtex is not available
3. **`root_file` config key** — an absolute path you set manually as a fallback

When a root file is detected and differs from the file you are editing, the
picker title changes to indicate the current mode and the available toggle key:

- **Full-project mode** (default): shows all labels from the entire project,
  with the cursor pre-positioned on the first label defined in your current file
  — title reads `LaTeX Labels (full project) [<C-g>: this file]`
- **This-file mode**: shows only labels defined in the current file — title reads
  `LaTeX Labels (this file) [<C-g>: full project]`

Press the toggle key (`<C-g>` by default) inside the picker to switch between
modes. Press it again to return.

If root detection fails (e.g. the `\documentclass` argument is non-trivial and
vimtex is not active), set `root_file` as a manual override:

```lua
latex_labels = {
  root_file          = "/home/user/thesis/main.tex",
  subfile_toggle_key = "<C-g>",
}
```

## Copy Label

Press `copy_label_key` (default `<C-y>`) inside the picker to copy the selected
label's reference to the system clipboard (`+` register) without jumping to the
file.

### `copy_transform`

An optional hook that transforms the label string before it is placed in the
clipboard. Accepts two forms:

**Table** — map label prefixes to Lua format strings (`%s` is replaced with the
full label id):

```lua
copy_transform = {
  ["df:"] = "\\cref{%s}",
  ["lm:"] = "\\cref{%s}",
  ["th:"] = "\\cref{%s}",
  ["co:"] = "\\cref{%s}",
  ["pr:"] = "\\cref{%s}",
  ["ex:"] = "example~\\ref{%s}",
  ["eq:"] = "equation~\\eqref{%s}",
},
```

With this config, pressing `<C-y>` on `df:grp` copies `\cref{df:grp}`, and on
`eq:euler` copies `equation~\eqref{eq:euler}`. Labels whose prefix is not in the
table are copied unchanged.

**Function** — for logic that a flat table cannot express:

```lua
copy_transform = function(label)
  if label:match("^eq:") then
    return "equation~\\eqref{" .. label .. "}"
  end
  return "\\cref{" .. label .. "}"
end,
```

When `copy_transform` is `nil` (the default) the raw label id is copied.

## Configuration reference

| Option | Type | Default | Description |
|---|---|---|---|
| `cache_strategy` | `string` | `"global"` | `"global"` stores caches in `stdpath("data")/cached_labels/`; `"local"` places a hidden `.filename.tex.labels` file next to your root file |
| `recursive` | `boolean` | `true` | Follow `\include` and `\input` directives when scanning |
| `auto_update` | `boolean` | `false` | Regenerate cache on every `BufWritePost` for `.tex` files |
| `enable_smart_jump` | `boolean` | `true` | Search for shifted labels instead of jumping blindly to the cached line |
| `smart_jump_window` | `integer` | `200` | Lines to search on each side of the cached position |
| `transformations` | `table` | see above | Maps environment names to label prefixes |
| `patterns` | `table` | see above | Ordered list of capture patterns |
| `root_file` | `string` | `""` | Absolute path to the root `.tex` file; fallback when vimtex is absent and auto-detection fails |
| `subfile_toggle_key` | `string` | `"<C-g>"` | Key to toggle between full-project and this-file view inside the picker |
| `copy_label_key` | `string` | `"<C-y>"` | Key to copy the selected label reference to the system clipboard without opening the file |
| `copy_transform` | `table\|function\|nil` | `nil` | Transform applied to the label before copying; see [Copy Label](#copy-label) |

## Cache format

Cache files are plain text — one label per line:

```
line_number|label_id|context|absolute_filepath
```

Example:

```
50|th:snakeLem|Snake Lemma|/Users/me/thesis/chapter1.tex
102|pr:bigProp|Main Proposition|/Users/me/thesis/chapter1.tex
15|df:myDef|Definition of X|/Users/me/thesis/chapter2.tex
```

For the `"local"` strategy the file is placed next to your root `.tex` file
(add `*.labels` to `.gitignore`). For `"global"` the cache lives in
`stdpath("data")/cached_labels/` and your project directories stay clean.

## Help

Full documentation is available in Neovim after installation:

```
:help telescope-latex-labels
```
