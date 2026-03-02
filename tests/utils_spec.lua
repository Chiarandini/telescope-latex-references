-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local utils = require("telescope._extensions.latex_labels.utils")

local this_file = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fn.fnamemodify(this_file, ":p:h")
local fixtures  = tests_dir .. "/fixtures"

-- ─── find_root_via_subfiles ───────────────────────────────────────────────────

describe("utils – find_root_via_subfiles", function()
  it("returns nil for a non-existent file", function()
    assert.is_nil(utils.find_root_via_subfiles("/tmp/__no_such_file__.tex"))
  end)

  it("returns nil for a file without \\documentclass[...]{subfiles}", function()
    -- main.tex has \documentclass{book}, not the subfiles form
    assert.is_nil(utils.find_root_via_subfiles(fixtures .. "/main.tex"))
  end)

  it("returns nil for a plain included file (no subfiles declaration)", function()
    assert.is_nil(utils.find_root_via_subfiles(fixtures .. "/chapters/chapter1_include.tex"))
  end)

  it("detects root from \\documentclass[../main.tex]{subfiles}", function()
    local root = utils.find_root_via_subfiles(fixtures .. "/chapters/chapter3_subfile.tex")
    assert.is_not_nil(root, "should detect root via subfiles declaration")
    assert.is_true(root:find("main.tex", 1, true) ~= nil)
    assert.equal(1, vim.fn.filereadable(root), "resolved root should be readable")
  end)

  it("returns the same root from two different subfiles in the same project", function()
    local root3 = utils.find_root_via_subfiles(fixtures .. "/chapters/chapter3_subfile.tex")
    local root4 = utils.find_root_via_subfiles(fixtures .. "/chapters/chapter4_subfile_standalone.tex")
    assert.is_not_nil(root3)
    assert.is_not_nil(root4)
    assert.equal(root3, root4)
  end)

  it("returns nil when the referenced root file does not exist", function()
    local tmp = vim.fn.tempname() .. ".tex"
    local f = io.open(tmp, "w")
    f:write("\\documentclass[../nonexistent_root.tex]{subfiles}\n")
    f:close()
    local result = utils.find_root_via_subfiles(tmp)
    os.remove(tmp)
    assert.is_nil(result)
  end)

  it("only reads up to 20 lines (does not scan whole file)", function()
    -- Put the declaration on line 21, which is past the 20-line limit
    local tmp = vim.fn.tempname() .. ".tex"
    local f = io.open(tmp, "w")
    for _ = 1, 20 do f:write("% padding line\n") end
    f:write("\\documentclass[../main.tex]{subfiles}\n")
    f:close()
    local result = utils.find_root_via_subfiles(tmp)
    os.remove(tmp)
    assert.is_nil(result, "declaration past line 20 should not be detected")
  end)
end)
