-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local cache = require("telescope._extensions.latex_labels.cache")

local this_file = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fn.fnamemodify(this_file, ":p:h")
local fixtures  = tests_dir .. "/fixtures"

-- ─── get_cache_path ───────────────────────────────────────────────────────────

describe("cache.get_cache_path", function()
  it("local strategy: hidden file next to source", function()
    local p = cache.get_cache_path(fixtures .. "/main.tex", "local")
    assert.is_not_nil(p)
    assert.is_true(p:find("main.tex.labels", 1, true) ~= nil)
    assert.equal(".", p:match("([^/]+)%.labels$"):sub(1, 1))  -- starts with dot
  end)

  it("global strategy: path inside stdpath(data)", function()
    local p = cache.get_cache_path(fixtures .. "/main.tex", "global")
    assert.is_not_nil(p)
    local data = vim.fn.stdpath("data")
    assert.is_true(p:sub(1, #data) == data)
    assert.is_true(p:find("cached_labels", 1, true) ~= nil)
  end)

  it("global strategy: two different files produce different paths", function()
    local p1 = cache.get_cache_path(fixtures .. "/main.tex", "global")
    local p2 = cache.get_cache_path(fixtures .. "/chapters/chapter1_include.tex", "global")
    assert.are_not.equal(p1, p2)
  end)
end)

-- ─── read_cache ───────────────────────────────────────────────────────────────

describe("cache.read_cache", function()
  it("returns nil for a non-existent file", function()
    assert.is_nil(cache.read_cache("/tmp/__no_such_cache__.labels"))
  end)
end)

-- ─── Round-trip ───────────────────────────────────────────────────────────────

describe("cache round-trip", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname() .. ".labels"
  end)

  after_each(function()
    os.remove(tmp)
  end)

  it("preserves line, id, context, and filename for a single entry", function()
    local entries = {
      { line = 42, id = "th:snakeLem", context = "Snake Lemma", filename = "/abs/path/chapter1.tex" },
    }
    cache.write_cache(tmp, entries)
    local out = cache.read_cache(tmp)
    assert.is_not_nil(out)
    assert.equal(1, #out)
    assert.equal(42,                    out[1].line)
    assert.equal("th:snakeLem",         out[1].id)
    assert.equal("Snake Lemma",         out[1].context)
    assert.equal("/abs/path/chapter1.tex", out[1].filename)
  end)

  it("preserves multiple entries in order", function()
    local entries = {
      { line = 10, id = "sec:intro",  context = "Introduction",    filename = "/a/main.tex" },
      { line = 20, id = "pr:bigProp", context = "Big Proposition", filename = "/a/ch1.tex"  },
      { line = 30, id = "df:myDef",   context = "My Definition",   filename = "/a/ch2.tex"  },
    }
    cache.write_cache(tmp, entries)
    local out = cache.read_cache(tmp)
    assert.equal(3, #out)
    assert.equal("sec:intro",  out[1].id)
    assert.equal("pr:bigProp", out[2].id)
    assert.equal("df:myDef",   out[3].id)
  end)

  it("returns empty table for an empty cache file", function()
    cache.write_cache(tmp, {})
    local out = cache.read_cache(tmp)
    assert.is_not_nil(out)
    assert.are.same({}, out)
  end)

  it("skips comment lines starting with #", function()
    -- Manually write a cache file with comment lines
    local f = io.open(tmp, "w")
    f:write("# this is a comment\n")
    f:write("5|sec:root|Root Section|/main.tex\n")
    f:write("# another comment\n")
    f:write("10|th:foo|Some Theorem|/ch1.tex\n")
    f:close()
    local out = cache.read_cache(tmp)
    assert.equal(2, #out)
    assert.equal("sec:root", out[1].id)
    assert.equal("th:foo",   out[2].id)
  end)

  it("sanitizes pipe characters in id and context", function()
    local entries = {
      { line = 1, id = "id|with|pipes", context = "context|with|pipes", filename = "/f.tex" },
    }
    cache.write_cache(tmp, entries)
    local out = cache.read_cache(tmp)
    -- The sanitized id and context must not contain pipe characters
    assert.is_nil(out[1].id:find("|", 1, true))
    assert.is_nil(out[1].context:find("|", 1, true))
  end)

  it("write_cache returns false when path is unwritable", function()
    local ok, _ = cache.write_cache("/no/such/directory/file.labels", {})
    assert.is_false(ok)
  end)
end)
