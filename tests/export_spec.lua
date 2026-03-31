-- Run with:
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

local export = require("latex_nav_core.export")

-- ── Shared fixtures ───────────────────────────────────────────────────────────

local ROOT_PATH = "/proj/main.tex"

local ENTRIES = {
  { line = 121, id = "sec:classicalAlgGeo", context = "Classical Algebraic Geometry", filename = "/proj/main.tex"       },
  { line = 164, id = "df:zeroSet",          context = "Zero Set",                     filename = "/proj/chapters/ch1.tex" },
  { line = 182, id = "df:zariskiTopology",  context = "Zariski Topology",             filename = "/proj/chapters/ch1.tex" },
  { line = 10,  id = "fig:mainGraph",       context = "Main Graph",                   filename = "/proj/chapters/ch2.tex" },
  { line = 20,  id = "noprefixlabel",       context = "No Prefix",                    filename = "/proj/archive/old.tex"  },
}

-- ─── get_prefix ───────────────────────────────────────────────────────────────

describe("export.get_prefix", function()
  it("extracts the part before the first colon", function()
    assert.equal("sec", export.get_prefix("sec:classicalAlgGeo"))
    assert.equal("df",  export.get_prefix("df:zeroSet"))
    assert.equal("fig", export.get_prefix("fig:mainGraph"))
  end)

  it("returns empty string when there is no colon", function()
    assert.equal("", export.get_prefix("noprefixlabel"))
    assert.equal("", export.get_prefix(""))
  end)

  it("uses only the first colon as the delimiter", function()
    -- e.g. "th:snake:lemma" → prefix is "th"
    assert.equal("th", export.get_prefix("th:snake:lemma"))
  end)
end)

-- ─── relative_path ────────────────────────────────────────────────────────────

describe("export.relative_path", function()
  it("returns a path relative to root's directory", function()
    local rel = export.relative_path("/proj/chapters/ch1.tex", "/proj/main.tex")
    assert.equal("chapters/ch1.tex", rel)
  end)

  it("returns just the filename when the file is in the same directory as root", function()
    local rel = export.relative_path("/proj/main.tex", "/proj/main.tex")
    assert.equal("main.tex", rel)
  end)

  it("returns the absolute path when the file is outside the root directory", function()
    local rel = export.relative_path("/other/place/ch1.tex", "/proj/main.tex")
    assert.equal("/other/place/ch1.tex", rel)
  end)
end)

-- ─── parse_entry ─────────────────────────────────────────────────────────────

describe("export.parse_entry", function()
  it("produces correct fields in absolute mode", function()
    local e = ENTRIES[2]  -- df:zeroSet
    local p = export.parse_entry(e, ROOT_PATH, false)
    assert.equal("df:zeroSet",           p.id)
    assert.equal("df",                   p.prefix)
    assert.equal("Zero Set",             p.title)
    assert.equal("/proj/chapters/ch1.tex", p.file)
    assert.equal(164,                    p.line)
  end)

  it("uses relative file path when use_relative is true", function()
    local e = ENTRIES[2]  -- df:zeroSet at /proj/chapters/ch1.tex
    local p = export.parse_entry(e, ROOT_PATH, true)
    assert.equal("chapters/ch1.tex", p.file)
  end)

  it("handles labels with no prefix", function()
    local e = ENTRIES[5]  -- noprefixlabel
    local p = export.parse_entry(e, ROOT_PATH, false)
    assert.equal("noprefixlabel", p.id)
    assert.equal("",              p.prefix)
  end)
end)

-- ─── default_filename ────────────────────────────────────────────────────────

describe("export.default_filename", function()
  it("returns correct filenames for each format", function()
    assert.equal("project_labels.json", export.default_filename("json"))
    assert.equal("project_labels.csv",  export.default_filename("csv"))
    assert.equal("project_labels.tsv",  export.default_filename("tsv"))
    assert.equal("project_labels.txt",  export.default_filename("txt"))
  end)

  it("falls back to .txt for an unknown format key", function()
    assert.equal("project_labels.txt", export.default_filename("unknown"))
  end)
end)

-- ─── format_json ─────────────────────────────────────────────────────────────

describe("export.format_json", function()
  it("produces valid JSON that can be decoded", function()
    local json = export.format_json(ENTRIES, ROOT_PATH)
    local ok, decoded = pcall(vim.fn.json_decode, json)
    assert.is_true(ok, "json_decode raised an error: " .. tostring(decoded))
    assert.is_not_nil(decoded)
  end)

  it("includes project_root and export_date at the top level", function()
    local decoded = vim.fn.json_decode(export.format_json(ENTRIES, ROOT_PATH))
    assert.equal("/proj", decoded.project_root)
    assert.is_not_nil(decoded.export_date)
    -- export_date should be an ISO 8601 UTC string
    assert.is_truthy(decoded.export_date:match("^%d%d%d%d%-%d%d%-%d%dT"))
  end)

  it("contains the correct number of label entries", function()
    local decoded = vim.fn.json_decode(export.format_json(ENTRIES, ROOT_PATH))
    assert.equal(#ENTRIES, #decoded.labels)
  end)

  it("encodes id, type, title, file, and line by default", function()
    local decoded = vim.fn.json_decode(export.format_json(ENTRIES, ROOT_PATH))
    local first   = decoded.labels[1]
    assert.equal("sec:classicalAlgGeo",         first.id)
    assert.equal("sec",                         first.type)
    assert.equal("Classical Algebraic Geometry", first.title)
    assert.equal("/proj/main.tex",              first.file)
    assert.equal(121,                           first.line)
  end)

  it("omits 'line' when include_line = false", function()
    local decoded = vim.fn.json_decode(
      export.format_json(ENTRIES, ROOT_PATH, { include_line = false })
    )
    assert.is_nil(decoded.labels[1].line)
    assert.is_not_nil(decoded.labels[1].id)
  end)

  it("omits 'title' when include_title = false", function()
    local decoded = vim.fn.json_decode(
      export.format_json(ENTRIES, ROOT_PATH, { include_title = false })
    )
    assert.is_nil(decoded.labels[1].title)
  end)

  it("omits 'file' when include_file = false", function()
    local decoded = vim.fn.json_decode(
      export.format_json(ENTRIES, ROOT_PATH, { include_file = false })
    )
    assert.is_nil(decoded.labels[1].file)
  end)

  it("uses relative paths when use_relative_paths = true", function()
    local decoded = vim.fn.json_decode(
      export.format_json(ENTRIES, ROOT_PATH, { use_relative_paths = true })
    )
    -- ENTRIES[2] is at /proj/chapters/ch1.tex → should become "chapters/ch1.tex"
    assert.equal("chapters/ch1.tex", decoded.labels[2].file)
    -- ENTRIES[1] is at /proj/main.tex → "main.tex"
    assert.equal("main.tex", decoded.labels[1].file)
  end)

  it("excludes entries whose filename matches an exclude_files pattern", function()
    local decoded = vim.fn.json_decode(
      export.format_json(ENTRIES, ROOT_PATH, { exclude_files = { "archive" } })
    )
    -- ENTRIES[5] has filename containing "archive" — it should be gone
    assert.equal(#ENTRIES - 1, #decoded.labels)
    for _, lbl in ipairs(decoded.labels) do
      assert.is_nil(lbl.id == "noprefixlabel" or nil)
    end
  end)

  it("handles an empty entry list gracefully", function()
    local json = export.format_json({}, ROOT_PATH)
    local decoded = vim.fn.json_decode(json)
    assert.are.same({}, decoded.labels)
  end)

  it("escapes special characters in string fields", function()
    local tricky = {
      { line = 1, id = 'id"with"quotes', context = 'line\nnewline', filename = "/proj/main.tex" },
    }
    local json = export.format_json(tricky, ROOT_PATH)
    local ok, decoded = pcall(vim.fn.json_decode, json)
    assert.is_true(ok, "JSON with special chars failed to decode")
    assert.equal('id"with"quotes', decoded.labels[1].id)
  end)
end)

-- ─── format_csv ──────────────────────────────────────────────────────────────

describe("export.format_csv", function()
  it("starts with the correct header row", function()
    local csv   = export.format_csv(ENTRIES, ROOT_PATH)
    local lines = vim.split(csv, "\n")
    assert.equal("Label ID,Type,Title,File,Line", lines[1])
  end)

  it("produces one data row per entry plus the header", function()
    local csv   = export.format_csv(ENTRIES, ROOT_PATH)
    local lines = vim.split(csv, "\n")
    assert.equal(#ENTRIES + 1, #lines)
  end)

  it("encodes the first data row correctly", function()
    local csv   = export.format_csv(ENTRIES, ROOT_PATH)
    local lines = vim.split(csv, "\n")
    -- sec:classicalAlgGeo,sec,Classical Algebraic Geometry,/proj/main.tex,121
    assert.equal(
      "sec:classicalAlgGeo,sec,Classical Algebraic Geometry,/proj/main.tex,121",
      lines[2]
    )
  end)

  it("omits Title column when include_title = false", function()
    local csv    = export.format_csv(ENTRIES, ROOT_PATH, { include_title = false })
    local header = vim.split(csv, "\n")[1]
    assert.is_nil(header:find("Title", 1, true))
    assert.is_truthy(header:find("Label ID", 1, true))
  end)

  it("omits Line column when include_line = false", function()
    local csv    = export.format_csv(ENTRIES, ROOT_PATH, { include_line = false })
    local header = vim.split(csv, "\n")[1]
    assert.is_nil(header:find("Line", 1, true))
  end)

  it("wraps fields containing commas in double-quotes", function()
    local tricky = {
      { line = 1, id = "sec:foo", context = "Title, with comma", filename = "/proj/main.tex" },
    }
    local csv   = export.format_csv(tricky, ROOT_PATH)
    local row   = vim.split(csv, "\n")[2]
    assert.is_truthy(row:find('"Title, with comma"', 1, true))
  end)

  it("escapes double-quotes inside CSV fields", function()
    local tricky = {
      { line = 1, id = "sec:foo", context = 'Title "quoted"', filename = "/proj/main.tex" },
    }
    local csv = export.format_csv(tricky, ROOT_PATH)
    local row = vim.split(csv, "\n")[2]
    -- RFC 4180: embedded quote becomes ""
    assert.is_truthy(row:find('""quoted""', 1, true))
  end)

  it("filters entries via exclude_files", function()
    local csv   = export.format_csv(ENTRIES, ROOT_PATH, { exclude_files = { "archive" } })
    local lines = vim.split(csv, "\n")
    assert.equal(#ENTRIES - 1 + 1, #lines)   -- 4 data rows + 1 header
  end)
end)

-- ─── format_tsv ──────────────────────────────────────────────────────────────

describe("export.format_tsv", function()
  it("starts with a tab-separated header", function()
    local tsv    = export.format_tsv(ENTRIES, ROOT_PATH)
    local header = vim.split(tsv, "\n")[1]
    assert.is_truthy(header:find("\t", 1, true))
    assert.is_truthy(header:find("Label ID", 1, true))
    assert.is_truthy(header:find("Type",     1, true))
  end)

  it("produces one data row per entry plus the header", function()
    local tsv   = export.format_tsv(ENTRIES, ROOT_PATH)
    local lines = vim.split(tsv, "\n")
    assert.equal(#ENTRIES + 1, #lines)
  end)

  it("first data row has tab-separated fields", function()
    local tsv   = export.format_tsv(ENTRIES, ROOT_PATH)
    local row   = vim.split(tsv, "\n")[2]
    local parts = vim.split(row, "\t")
    assert.equal("sec:classicalAlgGeo",         parts[1])
    assert.equal("sec",                         parts[2])
    assert.equal("Classical Algebraic Geometry", parts[3])
  end)
end)

-- ─── format_txt ──────────────────────────────────────────────────────────────

describe("export.format_txt", function()
  it("produces pipe-separated lines with all fields by default", function()
    local txt   = export.format_txt(ENTRIES)
    local lines = vim.split(txt, "\n")
    assert.equal(#ENTRIES, #lines)
    -- Default order: line|id|context|file
    assert.equal(
      "121|sec:classicalAlgGeo|Classical Algebraic Geometry|/proj/main.tex",
      lines[1]
    )
  end)

  it("omits line when include_line = false", function()
    local txt  = export.format_txt(ENTRIES, { include_line = false })
    local row  = vim.split(txt, "\n")[1]
    assert.equal("sec:classicalAlgGeo|Classical Algebraic Geometry|/proj/main.tex", row)
  end)

  it("omits file when include_file = false", function()
    local txt = export.format_txt(ENTRIES, { include_file = false })
    local row = vim.split(txt, "\n")[1]
    assert.equal("121|sec:classicalAlgGeo|Classical Algebraic Geometry", row)
  end)

  it("omits both line and file when both are false", function()
    local txt = export.format_txt(ENTRIES, { include_line = false, include_file = false })
    local row = vim.split(txt, "\n")[1]
    assert.equal("sec:classicalAlgGeo|Classical Algebraic Geometry", row)
  end)

  it("filters entries via exclude_files", function()
    local txt   = export.format_txt(ENTRIES, { exclude_files = { "archive" } })
    local lines = vim.split(txt, "\n")
    assert.equal(#ENTRIES - 1, #lines)
  end)

  it("returns an empty string for an empty entry list", function()
    assert.equal("", export.format_txt({}))
  end)
end)

-- ─── write_export ─────────────────────────────────────────────────────────────

describe("export.write_export", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname() .. ".json"
  end)

  after_each(function()
    os.remove(tmp)
  end)

  it("writes content to disk and returns true", function()
    local ok, err = export.write_export(tmp, '{"test":true}')
    assert.is_true(ok)
    assert.is_nil(err)
    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.equal('{"test":true}', content)
  end)

  it("returns false when the parent directory does not exist", function()
    local ok, err = export.write_export("/no/such/directory/out.json", "data")
    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.is_truthy(err:find("Directory does not exist", 1, true))
  end)

  it("round-trips JSON content correctly", function()
    local content = export.format_json(ENTRIES, ROOT_PATH)
    local ok, _   = export.write_export(tmp, content)
    assert.is_true(ok)

    local f = io.open(tmp, "r")
    local written = f:read("*a")
    f:close()

    local decoded = vim.fn.json_decode(written)
    assert.equal(#ENTRIES, #decoded.labels)
    assert.equal("sec:classicalAlgGeo", decoded.labels[1].id)
  end)
end)
