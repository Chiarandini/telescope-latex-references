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
  "your-username/telescope-latex-labels.nvim",
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
  "your-username/telescope-latex-labels.nvim",
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
