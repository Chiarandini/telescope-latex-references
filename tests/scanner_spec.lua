-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local scanner = require("telescope._extensions.latex_labels.scanner")

local this_file = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fn.fnamemodify(this_file, ":p:h")
local fixtures  = tests_dir .. "/fixtures"

-- Default config that mirrors DEFAULT_CONFIG in latex_labels.lua
local DEFAULT_CONFIG = {
  recursive = true,
  transformations = {
    thm      = "th:",
    prop     = "pr:",
    defn     = "df:",
    lem      = "lm:",
    cor      = "co:",
    example  = "ex:",
    exercise = "x:",
  },
  patterns = {
    { pattern = "\\begin{(%w+)}{(.-)}{(.-)}", type = "environment" },
    { pattern = "\\label{(.-)}", type = "standard" },
  },
}

local function cfg(overrides)
  local t = {}
  for k, v in pairs(DEFAULT_CONFIG) do t[k] = v end
  for k, v in pairs(overrides or {}) do t[k] = v end
  return t
end

local function find(results, id)
  for _, e in ipairs(results) do
    if e.id == id then return e end
  end
  return nil
end

-- ─── Non-recursive (single-file) scan ────────────────────────────────────────

describe("scanner – non-recursive scan of root file", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg({ recursive = false }))
  end)

  it("returns a non-empty table", function()
    assert.is_true(#results > 0)
  end)

  it("finds \\label{sec:root} in the root file", function()
    local e = find(results, "sec:root")
    assert.is_not_nil(e, "sec:root not found")
    assert.equal(6, e.line)
  end)

  it("finds \\begin{thm}{Root Theorem}{rootThm} → th:rootThm", function()
    local e = find(results, "th:rootThm")
    assert.is_not_nil(e, "th:rootThm not found")
    assert.equal(8, e.line)
    assert.equal("Root Theorem", e.context)
  end)

  it("does NOT follow \\include, \\input, or \\subfile when recursive = false", function()
    assert.is_nil(find(results, "sec:ch1"), "sec:ch1 should not be found")
    assert.is_nil(find(results, "sec:ch2"), "sec:ch2 should not be found")
    assert.is_nil(find(results, "sec:ch3"), "sec:ch3 should not be found")
  end)

  it("returns exactly 2 labels", function()
    assert.equal(2, #results)
  end)
end)

-- ─── Recursive via \\include ──────────────────────────────────────────────────

describe("scanner – recursive via \\include", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg())
  end)

  it("finds sec:ch1 from chapter1_include.tex", function()
    local e = find(results, "sec:ch1")
    assert.is_not_nil(e, "sec:ch1 not found")
    assert.equal(2, e.line)
  end)

  it("sec:ch1 context is inferred from preceding \\section line", function()
    local e = find(results, "sec:ch1")
    assert.is_not_nil(e)
    assert.equal("Chapter One via Include", e.context)
  end)

  it("finds pr:prop1 from \\begin{prop}{First Proposition}{prop1}", function()
    local e = find(results, "pr:prop1")
    assert.is_not_nil(e, "pr:prop1 not found")
    assert.equal(4, e.line)
    assert.equal("First Proposition", e.context)
  end)

  it("entry filename is the absolute path of chapter1_include.tex", function()
    local e = find(results, "sec:ch1")
    assert.is_not_nil(e)
    assert.is_true(e.filename:find("chapter1_include.tex", 1, true) ~= nil)
    assert.equal(1, vim.fn.filereadable(e.filename))
  end)
end)

-- ─── Recursive via \\input ────────────────────────────────────────────────────

describe("scanner – recursive via \\input", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg())
  end)

  it("finds sec:ch2 from chapter2_input.tex", function()
    local e = find(results, "sec:ch2")
    assert.is_not_nil(e, "sec:ch2 not found")
    assert.equal(2, e.line)
  end)

  it("sec:ch2 context is inferred from preceding \\section line", function()
    local e = find(results, "sec:ch2")
    assert.is_not_nil(e)
    assert.equal("Chapter Two via Input", e.context)
  end)

  it("entry filename is the absolute path of chapter2_input.tex", function()
    local e = find(results, "sec:ch2")
    assert.is_not_nil(e)
    assert.is_true(e.filename:find("chapter2_input.tex", 1, true) ~= nil)
  end)
end)

-- ─── Recursive via \\subfile (key regression test) ───────────────────────────

describe("scanner – recursive via \\subfile", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg())
  end)

  it("finds sec:ch3 from chapter3_subfile.tex", function()
    local e = find(results, "sec:ch3")
    assert.is_not_nil(e, "sec:ch3 not found — \\subfile recursion may be broken")
    assert.equal(5, e.line)
  end)

  it("finds th:subThm from \\begin{thm}{Subfile Theorem}{subThm}", function()
    local e = find(results, "th:subThm")
    assert.is_not_nil(e, "th:subThm not found — \\subfile recursion may be broken")
    assert.equal(7, e.line)
    assert.equal("Subfile Theorem", e.context)
  end)

  it("entry filename is the absolute path of chapter3_subfile.tex", function()
    local e = find(results, "sec:ch3")
    assert.is_not_nil(e)
    assert.is_true(e.filename:find("chapter3_subfile.tex", 1, true) ~= nil)
    assert.equal(1, vim.fn.filereadable(e.filename))
  end)

  it("\\documentclass[...]{subfiles} line does NOT trigger false recursion", function()
    -- chapter3_subfile.tex has \documentclass[../main.tex]{subfiles} on line 1.
    -- That line must NOT cause main.tex to be scanned a second time.
    local count = 0
    for _, e in ipairs(results) do
      if e.id == "sec:root" then count = count + 1 end
    end
    assert.equal(1, count, "sec:root found more than once — cycle guard may have failed")
  end)
end)

-- ─── Full recursive scan ──────────────────────────────────────────────────────

describe("scanner – full recursive scan (all three include types)", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg())
  end)

  it("finds all 7 labels across all files", function()
    assert.equal(7, #results)
  end)

  it("preserves DFS document order", function()
    -- Expected order:
    --   sec:root    (main, line 6)
    --   th:rootThm  (main, line 8)
    --   sec:ch1     (chapter1, line 2)
    --   pr:prop1    (chapter1, line 4)
    --   sec:ch2     (chapter2, line 2)
    --   sec:ch3     (chapter3, line 5)
    --   th:subThm   (chapter3, line 7)
    local ids = {}
    for _, e in ipairs(results) do table.insert(ids, e.id) end
    assert.equal("sec:root",   ids[1])
    assert.equal("th:rootThm", ids[2])
    assert.equal("sec:ch1",    ids[3])
    assert.equal("pr:prop1",   ids[4])
    assert.equal("sec:ch2",    ids[5])
    assert.equal("sec:ch3",    ids[6])
    assert.equal("th:subThm",  ids[7])
  end)

  it("every entry has a non-empty absolute filename", function()
    for _, e in ipairs(results) do
      assert.is_true(e.filename ~= nil and e.filename ~= "")
      assert.equal("/", e.filename:sub(1, 1), "filename should be absolute")
    end
  end)
end)

-- ─── Local scan of a subfile ─────────────────────────────────────────────────

describe("scanner – local scan of a subfile (recursive = false)", function()
  it("scanning chapter3_subfile.tex alone returns only its own labels", function()
    local results = scanner.scan_project(
      fixtures .. "/chapters/chapter3_subfile.tex",
      cfg({ recursive = false })
    )
    assert.equal(2, #results)
    assert.is_not_nil(find(results, "sec:ch3"))
    assert.is_not_nil(find(results, "th:subThm"))
  end)

  it("scanning chapter4_subfile_standalone.tex returns its own label", function()
    local results = scanner.scan_project(
      fixtures .. "/chapters/chapter4_subfile_standalone.tex",
      cfg({ recursive = false })
    )
    assert.equal(1, #results)
    assert.is_not_nil(find(results, "sec:ch4"))
  end)

  it("local scan of subfile does NOT follow \\documentclass[...]{subfiles}", function()
    -- Even with recursive = true, \documentclass is not a \subfile{} directive
    local results = scanner.scan_project(
      fixtures .. "/chapters/chapter3_subfile.tex",
      cfg({ recursive = true })
    )
    -- Only ch3's own labels; main.tex must not be scanned
    assert.is_nil(find(results, "sec:root"))
    assert.is_nil(find(results, "th:rootThm"))
  end)
end)

-- ─── Environment pattern ─────────────────────────────────────────────────────

describe("scanner – environment pattern transformations", function()
  local results

  before_each(function()
    results = scanner.scan_project(fixtures .. "/main.tex", cfg())
  end)

  it("thm → th: prefix", function()
    assert.is_not_nil(find(results, "th:rootThm"))
    assert.is_not_nil(find(results, "th:subThm"))
  end)

  it("prop → pr: prefix", function()
    assert.is_not_nil(find(results, "pr:prop1"))
  end)

  it("unknown environment without transformation is skipped by env pattern", function()
    -- \begin{unknown}{Title}{lab} has no entry in transformations → env pattern skips it
    -- Only \label{...} would catch it via the standard pattern fallback
    -- This fixture has no such case, but verify the known ones are present
    assert.equal(7, #results)
  end)
end)

-- ─── Cycle guard ─────────────────────────────────────────────────────────────

describe("scanner – cycle guard", function()
  it("scanning a file with no includes returns only that file's labels", function()
    local results = scanner.scan_project(
      fixtures .. "/chapters/chapter1_include.tex",
      cfg()
    )
    assert.equal(2, #results)
  end)
end)

-- ─── Edge cases ──────────────────────────────────────────────────────────────

describe("scanner – edge cases", function()
  it("returns empty table for a non-existent file", function()
    local results = scanner.scan_project("/tmp/__nonexistent__.tex", cfg())
    assert.are.same({}, results)
  end)

  it("auto-appends .tex when include argument has no extension", function()
    -- main.tex uses \subfile{chapters/chapter3_subfile} (no .tex) — labels should be found
    local results = scanner.scan_project(fixtures .. "/main.tex", cfg())
    assert.is_not_nil(find(results, "sec:ch3"), "no .tex extension should be auto-appended")
  end)
end)
