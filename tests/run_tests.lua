--- tests/run_tests.lua
--- Headless Neovim test runner for bible_ref.nvim
---
--- Usage:
---   nvim --headless -u NONE -l tests/run_tests.lua
---
--- Exit code 0 = all tests passed; 1 = one or more failures.

-- ---------------------------------------------------------------------------
-- Bootstrap: add plugin lua/ directory to runtimepath so require() works.
-- ---------------------------------------------------------------------------
local script_dir = debug.getinfo(1, "S").source:sub(2):match("^(.+)/[^/]+$")
local plugin_root = script_dir:match("^(.+)/tests$") or script_dir .. "/.."
vim.opt.runtimepath:prepend(plugin_root)

-- ---------------------------------------------------------------------------
-- Minimal test harness
-- ---------------------------------------------------------------------------
local pass_count = 0
local fail_count = 0
local errors     = {}

local function ok(name, cond, msg)
  if cond then
    pass_count = pass_count + 1
    io.write(string.format("  \27[32m✓\27[0m  %s\n", name))
  else
    fail_count = fail_count + 1
    local detail = msg and (" — " .. msg) or ""
    io.write(string.format("  \27[31m✗\27[0m  %s%s\n", name, detail))
    table.insert(errors, name .. detail)
  end
end

local function eq(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    return true
  end
  return a == b
end

local function section(title)
  io.write(string.format("\n\27[1m%s\27[0m\n", title))
end

-- ---------------------------------------------------------------------------
-- Tests: SBL formatting (sbl.lua)
-- ---------------------------------------------------------------------------
section("SBL Formatting")

local sbl = require("bible_ref.sbl")

ok("James → Jas",
  sbl.resolve("James") == "Jas",
  "got: " .. tostring(sbl.resolve("James")))

ok("1 Corinthians → 1 Cor",
  sbl.resolve("1 Corinthians") == "1 Cor",
  "got: " .. tostring(sbl.resolve("1 Corinthians")))

ok("2 Peter → 2 Pet",
  sbl.resolve("2 Peter") == "2 Pet",
  "got: " .. tostring(sbl.resolve("2 Peter")))

ok("Song of Solomon → Song",
  sbl.resolve("Song of Solomon") == "Song",
  "got: " .. tostring(sbl.resolve("Song of Solomon")))

ok("Revelation → Rev",
  sbl.resolve("Revelation") == "Rev",
  "got: " .. tostring(sbl.resolve("Revelation")))

ok("format James 1:1 → 'Jas 1:1'",
  sbl.format({ book = "James", chapter = 1, verse_start = 1 }) == "Jas 1:1",
  "got: " .. sbl.format({ book = "James", chapter = 1, verse_start = 1 }))

ok("format 1 Corinthians 4:2 → '1 Cor 4:2'",
  sbl.format({ book = "1 Corinthians", chapter = 4, verse_start = 2 }) == "1 Cor 4:2",
  "got: " .. sbl.format({ book = "1 Corinthians", chapter = 4, verse_start = 2 }))

ok("format James 3:1-3 → 'Jas 3:1\u{2013}3' (en-dash range)",
  sbl.format({ book = "James", chapter = 3, verse_start = 1, verse_end = 3 }) == "Jas 3:1\u{2013}3",
  "got: " .. sbl.format({ book = "James", chapter = 3, verse_start = 1, verse_end = 3 }))

-- ---------------------------------------------------------------------------
-- Tests: Parsing (parse.lua)
-- ---------------------------------------------------------------------------
section("Reference Parsing")

local parse = require("bible_ref.parse")

local function check_parse(input, expected_book, expected_ch, expected_vs, expected_ve)
  local ref = parse.parse(input)
  local name = string.format("parse(%q)", input)
  if not ref then
    ok(name, false, "returned nil")
    return
  end
  ok(name .. " book",        ref.book        == expected_book, "got: " .. tostring(ref.book))
  ok(name .. " chapter",     ref.chapter     == expected_ch,   "got: " .. tostring(ref.chapter))
  ok(name .. " verse_start", ref.verse_start == expected_vs,   "got: " .. tostring(ref.verse_start))
  if expected_ve then
    ok(name .. " verse_end", ref.verse_end   == expected_ve,   "got: " .. tostring(ref.verse_end))
  else
    ok(name .. " verse_end nil", ref.verse_end == nil or ref.verse_end == false,
      "got: " .. tostring(ref.verse_end))
  end
end

check_parse("Jas. 3:1",           "James",          3, 1)
check_parse("James 3:1-3",        "James",          3, 1, 3)
check_parse("1 Cor. 4:2\u{2013}5","1 Corinthians",  4, 2, 5)  -- en-dash range
check_parse("2 Pet 1:4",          "2 Peter",        1, 4)
check_parse("1Cor 4:2",           "1 Corinthians",  4, 2)
check_parse("John 3:16",          "John",           3, 16)
check_parse("Gen 1:1",            "Genesis",        1, 1)
check_parse("Rev 22:21",          "Revelation",     22, 21)

-- Wrapped references
check_parse("(cf. Jas 3:1)",      "James",          3, 1)
check_parse("[1 Cor 4:2]",        "1 Corinthians",  4, 2)

-- ---------------------------------------------------------------------------
-- Tests: Multi-citation lines (parse.ref_at_cursor, B1 regression)
-- ---------------------------------------------------------------------------
-- A line may carry several citations; the reference under the cursor must be
-- the one whose span contains (or is nearest to) the cursor byte — not always
-- the leftmost citation on the line.
section("Multi-Citation Hover (B1 regression)")

local function ref_at(line, col0)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, math.min(col0, #line - 1) })
  local ref = parse.ref_at_cursor()
  vim.api.nvim_buf_delete(buf, { force = true })
  return ref
end

-- "Jas 3:1" occupies bytes 5-11; "1 Cor 4:2" occupies bytes 17-25.
local line2 = "See Jas 3:1 and 1 Cor 4:2 in context."

do
  local r = ref_at(line2, 4) -- on the "J" of "Jas"
  ok("cursor on 'Jas 3:1' → James 3:1",
    r ~= nil and r.book == "James" and r.chapter == 3 and r.verse_start == 1,
    "got: " .. tostring(r and r.book))
end

do
  local r = ref_at(line2, 18) -- on the "C" of "Cor"
  ok("cursor on '1 Cor 4:2' → 1 Corinthians 4:2 (not the leftmost citation)",
    r ~= nil and r.book == "1 Corinthians" and r.chapter == 4 and r.verse_start == 2,
    "got: " .. tostring(r and r.book))
end

do
  local r = ref_at(line2, 12) -- on the "a" of "and" — closer to Jas 3:1
  ok("cursor between citations, nearer the left → James 3:1",
    r ~= nil and r.book == "James" and r.verse_start == 1,
    "got: " .. tostring(r and r.book))
end

do
  local r = ref_at(line2, 14) -- on the "d" of "and" — closer to 1 Cor 4:2
  ok("cursor between citations, nearer the right → 1 Corinthians 4:2",
    r ~= nil and r.book == "1 Corinthians" and r.verse_start == 2,
    "got: " .. tostring(r and r.book))
end

do
  local r = ref_at("cf. Jas 3:1 in context", 4) -- on the "J" of "Jas"
  ok("single citation after a 'cf.' prefix → James 3:1",
    r ~= nil and r.book == "James" and r.verse_start == 1,
    "got: " .. tostring(r and r.book))
end

do
  local r = ref_at("cf. Jas 3:1 in context", 15) -- on the "i" of "in"
  ok("cursor past the token → nearest citation wins (James 3:1)",
    r ~= nil and r.book == "James" and r.verse_start == 1,
    "got: " .. tostring(r and r.book))
end

-- ---------------------------------------------------------------------------
-- Tests: Version registry & rotation (config.lua)
-- ---------------------------------------------------------------------------
-- Hermetic: build a temporary data directory so the suite never depends on
-- which datasets happen to live in the real data/ folder.
section("Version Registry & Rotation (hermetic data dir)")

local cfg = require("bible_ref.config")

local data_dir = vim.fn.tempname()
assert(vim.fn.mkdir(data_dir, "p") == 1)

local function write_dataset(filename, obj)
  local f = io.open(data_dir .. "/" .. filename, "w")
  f:write(vim.json.encode(obj))
  f:close()
end

write_dataset("bible_web.json", {
  ["James 1:1"]         = "James, a servant of God and of the Lord Jesus Christ.",
  ["James 1:2"]         = "Count it all joy, my brothers, when you meet trials of various kinds,",
  ["James 1:3"]         = "for you know that the testing of your faith produces steadfastness.",
  ["1 Corinthians 4:2"] = "Moreover, it is required of stewards that they be found faithful.",
  ["Genesis 1:1"]       = "In the beginning, God created the heavens and the earth.",
})

write_dataset("bible_testb.json", {
  -- Same references, different text; deliberately NO Genesis (OT absent)
  ["James 1:1"]         = "TESTB: James 1:1 text.",
  ["James 1:2"]         = "TESTB: James 1:2 text.",
  ["James 1:3"]         = "TESTB: James 1:3 text.",
  ["1 Corinthians 4:2"] = "TESTB: 1 Corinthians 4:2 text.",
})

cfg.setup({ data_dir = data_dir })
local versions = cfg.get_versions()

ok("discovered exactly 2 versions (bible_web.json, bible_testb.json)",
  #versions == 2, "got: " .. tostring(#versions))

ok("no default_version → built-in WEB selected even though it is index 2",
  cfg.find_version_index("WEB") == 2
    and cfg.get_current_version_index() == 2,
  "current=" .. tostring(cfg.get_current_version_index())
    .. " WEB_idx=" .. tostring(cfg.find_version_index("WEB")))

ok("TESTB discovered (bible_testb.json → uppercased tag)",
  cfg.find_version_index("TESTB") ~= nil)

ok("next_version_index wraps N → 1",
  cfg.next_version_index(#versions) == 1,
  "got: " .. tostring(cfg.next_version_index(#versions)))

ok("prev_version_index wraps 1 → N",
  cfg.prev_version_index(1) == #versions,
  "got: " .. tostring(cfg.prev_version_index(1)))

ok("next from 1 → 2",
  cfg.next_version_index(1) == 2,
  "got: " .. tostring(cfg.next_version_index(1)))

ok("set_version('testb') (case-insensitive)",
  cfg.set_version("testb") == true)

ok("current index follows set_version",
  cfg.get_current_version_index() == (cfg.find_version_index("TESTB") or -1))

ok("set_version('bogus') returns false",
  cfg.set_version("bogus") == false)

cfg.set_version("WEB") -- restore the built-in default as active

-- ---------------------------------------------------------------------------
-- Tests: Database lookup (db.lua)
-- ---------------------------------------------------------------------------
section("Database Lookups")

local db = require("bible_ref.db")

ok("Single verse lookup: James 1:1",
  db.lookup("James", 1, 1):find("servant of God") ~= nil,
  "got: " .. db.lookup("James", 1, 1):sub(1, 60))

ok("Single verse lookup: 1 Corinthians 4:2",
  db.lookup("1 Corinthians", 4, 2):find("faithful") ~= nil,
  "got: " .. db.lookup("1 Corinthians", 4, 2):sub(1, 60))

ok("Single verse lookup: Genesis 1:1",
  db.lookup("Genesis", 1, 1):find("beginning") ~= nil,
  "got: " .. db.lookup("Genesis", 1, 1):sub(1, 60))

ok("Range lookup: James 1:1-3 returns 3 verses",
  db.lookup_range("James", 1, 1, 3):find("%[1%]") ~= nil and
  db.lookup_range("James", 1, 1, 3):find("%[2%]") ~= nil and
  db.lookup_range("James", 1, 1, 3):find("%[3%]") ~= nil,
  "got: " .. db.lookup_range("James", 1, 1, 3):sub(1, 80))

ok("Missing verse returns graceful 'not present' message (not error)",
  db.lookup("Jude", 99, 99):find("not present in") ~= nil,
  "got: " .. db.lookup("Jude", 99, 99))

-- ---------------------------------------------------------------------------
-- Tests: Per-version lookups (db.lua)
-- ---------------------------------------------------------------------------
section("Per-Version Lookups")

ok("TESTB James 1:1 found via explicit tag (distinct text)",
  db.lookup("TESTB", "James", 1, 1):find("TESTB:") ~= nil,
  "got: " .. db.lookup("TESTB", "James", 1, 1):sub(1, 60))

ok("TESTB lookup by 1-based index",
  db.lookup(1, "James", 1, 1):find("TESTB:") ~= nil,
  "got: " .. db.lookup(1, "James", 1, 1):sub(1, 60))

ok("TESTB absent book → graceful 'not present in TESTB'",
  db.lookup("TESTB", "Genesis", 1, 1):find("not present in TESTB") ~= nil,
  "got: " .. db.lookup("TESTB", "Genesis", 1, 1))

ok("TESTB 1 Corinthians 4:2 present",
  db.lookup("TESTB", "1 Corinthians", 4, 2):find("TESTB:") ~= nil,
  "got: " .. db.lookup("TESTB", "1 Corinthians", 4, 2):sub(1, 60))

ok("TESTB range James 1:1–3 via 5-arg signature",
  db.lookup_range("TESTB", "James", 1, 1, 3):find("%[3%]") ~= nil,
  "got: " .. db.lookup_range("TESTB", "James", 1, 1, 3):sub(1, 80))

ok("all_entries('TESTB') excludes Genesis",
  (function()
    local es = db.all_entries("TESTB")
    for _, e in ipairs(es) do
      if e.ref.book == "Genesis" then return false end
    end
    return #es == 4
  end)(),
  "expected 4 TESTB entries, no Genesis")

ok("all_entries('WEB') has 5 entries in canonical order",
  (function()
    local es = db.all_entries("WEB")
    if #es ~= 5 then return false end
    return es[1].ref.book == "Genesis" and es[#es].ref.book == "James"
  end)(),
  "expected Genesis first, James last")

-- Lazy-load check: TESTB must not be loaded until first queried
local db_loaded_testb = db.is_loaded("TESTB")
ok("TESTB marked loaded after queries", db_loaded_testb == true)

-- Cleanup temp dir
vim.fn.delete(data_dir, "rf")

-- ---------------------------------------------------------------------------
-- Tests: data/user/ shadowing & default_version (hermetic)
-- ---------------------------------------------------------------------------
section("data/user/ Discovery & default_version (hermetic)")

local dir2 = vim.fn.tempname()
assert(vim.fn.mkdir(dir2, "p") == 1)
assert(vim.fn.mkdir(dir2 .. "/user", "p") == 1)

local function write_at(dir, filename, obj)
  local f = io.open(dir .. "/" .. filename, "w")
  f:write(vim.json.encode(obj))
  f:close()
end

-- Shipped (public) KJV, plus a private user copy that shadows it.
write_at(dir2, "bible_kjv.json", { ["James 1:1"] = "PUBLIC KJV text." })
write_at(dir2 .. "/user", "bible_kjv.json", { ["James 1:1"] = "USER KJV text." })
-- User-only WEB dataset.
write_at(dir2 .. "/user", "bible_web.json", { ["James 1:1"] = "WEB text." })
-- Stray bare bible.json files (v1 fossil): neither location is a slot any more.
write_at(dir2, "bible.json", { ["James 1:1"] = "Stray parent text." })
write_at(dir2 .. "/user", "bible.json", { ["James 1:1"] = "Stray user text." })

cfg.setup({ data_dir = dir2 })
local v2 = cfg.get_versions()

ok("user/ shadow: KJV appears exactly once in registry",
  (function()
    local n = 0
    for _, v in ipairs(v2) do if v.tag == "KJV" then n = n + 1 end end
    return n
  end)() == 1)

local kjv_idx  = cfg.find_version_index("KJV")
local kjv_path = kjv_idx and v2[kjv_idx].path or "nil"

ok("user/ shadow: KJV resolves to the user/ copy",
  kjv_idx ~= nil and v2[kjv_idx].path:find("/user/bible_kjv.json", 1, true) ~= nil,
  "got: " .. tostring(kjv_path))

ok("user-only dataset discovered (bible_web.json → WEB)",
  cfg.find_version_index("WEB") ~= nil)

ok("stray bible.json (parent and user/) is NOT discovered",
  (function()
    if #v2 ~= 2 then return false end
    for _, v in ipairs(v2) do
      if v.file == "bible.json" or v.tag == "ESV" then return false end
    end
    return true
  end)(),
  "got: " .. tostring(#v2) .. " versions")

ok("shadowed verse text resolves from the user copy, not the shipped one",
  db.lookup("KJV", "James", 1, 1):find("USER KJV") ~= nil,
  "got: " .. db.lookup("KJV", "James", 1, 1):sub(1, 60))

-- default_version
cfg.setup({ data_dir = dir2, default_version = "web" })
ok("default_version='web' (case-insensitive tag) selects WEB",
  cfg.get_current_version_index() == (cfg.find_version_index("WEB") or -1))

cfg.setup({ data_dir = dir2, default_version = "bogus" })
ok("unknown default_version falls back to built-in default (WEB present)",
  cfg.get_current_version_index() == (cfg.find_version_index("WEB") or -1),
  "current=" .. tostring(cfg.get_current_version_index()))

-- Cleanup temp dir
vim.fn.delete(dir2, "rf")

-- ---------------------------------------------------------------------------
-- Tests: no-WEB fallback (hermetic)
-- ---------------------------------------------------------------------------
section("Built-in Default Fallback (no WEB present)")

local dir3 = vim.fn.tempname()
assert(vim.fn.mkdir(dir3, "p") == 1)
write_at(dir3, "bible_kjv.json", { ["James 1:1"] = "KJV text." })
write_at(dir3, "bible_testb.json", { ["James 1:1"] = "TESTB text." })

cfg.setup({ data_dir = dir3 })
ok("no WEB in registry → built-in default falls back to index 1 (KJV)",
  cfg.find_version_index("WEB") == nil
    and cfg.find_version_index("KJV") == 1
    and cfg.get_current_version_index() == 1,
  "current=" .. tostring(cfg.get_current_version_index())
    .. " KJV_idx=" .. tostring(cfg.find_version_index("KJV")))

-- Cleanup temp dir
vim.fn.delete(dir3, "rf")

-- ---------------------------------------------------------------------------
-- Tests: Line scanning (parse.find_refs_in_line, F2)
-- ---------------------------------------------------------------------------
section("Line Scanning (find_refs_in_line)")

local parse = require("bible_ref.parse")

do
  local rs = parse.find_refs_in_line("Jas 3:1 and 1 Cor 4:2")
  ok("two citations found in left-to-right order",
    #rs == 2
      and rs[1].ref.book == "James" and rs[1].ref.verse_start == 1
      and rs[2].ref.book == "1 Corinthians" and rs[2].ref.verse_start == 2,
    "got " .. tostring(#rs) .. " entries")
  ok("spans are ordered and disjoint",
    #rs == 2 and rs[1].start < rs[1].finish and rs[1].finish < rs[2].start,
    "spans: " .. tostring(rs and rs[1] and rs[1].start) .. "-"
      .. tostring(rs and rs[1] and rs[1].finish) .. ", "
      .. tostring(rs and rs[2] and rs[2].start) .. "-"
      .. tostring(rs and rs[2] and rs[2].finish))
end

do
  local rs = parse.find_refs_in_line("(cf. Jas 3:1)")
  ok("wrapped '(cf. Jas 3:1)' → exactly one citation (offsets deduped)",
    #rs == 1 and rs[1].ref.book == "James" and rs[1].ref.verse_start == 1,
    "got " .. tostring(#rs) .. " entries")
  ok("wrapped citation span starts at 'Jas' (wrapper stripped)",
    #rs == 1 and rs[1].start == 6 and rs[1].finish == 12,
    "span: " .. tostring(rs and rs[1] and rs[1].start) .. "-"
      .. tostring(rs and rs[1] and rs[1].finish))
end

do
  local rs = parse.find_refs_in_line("Jas 3:1\u{2013}3 and 1 Cor 4:2")
  ok("range end is included in the span",
    #rs == 2 and rs[1].ref.verse_end == 3 and rs[1].finish == 11,
    "got " .. tostring(#rs) .. " entries, finish "
      .. tostring(rs and rs[1] and rs[1].finish))
end

do
  local rs = parse.find_refs_in_line("1Cor 4:2")
  ok("compressed '1Cor 4:2' → one citation",
    #rs == 1 and rs[1].ref.book == "1 Corinthians" and rs[1].ref.verse_start == 2,
    "got " .. tostring(#rs) .. " entries")
end

ok("empty line → no citations", #parse.find_refs_in_line("") == 0)
ok("plain prose → no citations",
  #parse.find_refs_in_line("The Lord is my shepherd.") == 0)
ok("digits without a book → no citations",
  #parse.find_refs_in_line("3:1 is not a reference") == 0)

-- ---------------------------------------------------------------------------
-- Tests: Document navigation (parse.find_ref_near, F2)
-- ---------------------------------------------------------------------------
section("Document Navigation (find_ref_near)")

local nav_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(nav_buf, 0, -1, false, {
  "Jas 1:1 opens; 1 Cor 4:2 follows.",
  "",
  "Gen 1:1 closes the set.",
})

local function near(line, col, dir)
  return parse.find_ref_near(nav_buf, line, col, dir)
end

local function expect_nav(name, line, col, dir, exp_line, exp_col, exp_book)
  local r = near(line, col, dir)
  ok(name,
    r ~= nil and r.line == exp_line and r.col == exp_col and r.ref.book == exp_book,
    r == nil and "returned nil" or
      string.format("got line %s col %s book %s (want line %s col %s book %s)",
        tostring(r.line), tostring(r.col), tostring(r.ref.book),
        tostring(exp_line), tostring(exp_col), exp_book))
end

local function expect_nil(name, line, col, dir)
  local r = near(line, col, dir)
  ok(name, r == nil,
    r == nil and "" or
      string.format("got line %s book %s", tostring(r.line), tostring(r.ref.book)))
end

-- Line 1: "Jas 1:1" spans bytes 1–7; "1 Cor 4:2" spans bytes 16–24.
-- Line 3: "Gen 1:1" spans bytes 1–7.
expect_nav("next on-line (cursor before both) → 1 Cor 4:2",
  1, 0, 1, 1, 15, "1 Corinthians")
expect_nav("next on-line (cursor just past 'Jas 1:1') → 1 Cor 4:2",
  1, 7, 1, 1, 15, "1 Corinthians")
expect_nav("next cross-line (past line 1) → Gen 1:1",
  1, 24, 1, 3, 0, "Genesis")
expect_nav("next from a blank line → Gen 1:1",
  2, 0, 1, 3, 0, "Genesis")
expect_nav("prev on-line (cursor at line end) → 1 Cor 4:2",
  1, 24, -1, 1, 15, "1 Corinthians")
expect_nav("prev on-line (cursor between citations) → Jas 1:1",
  1, 8, -1, 1, 0, "James")
expect_nav("prev just after 'Gen 1:1' → Gen 1:1 itself",
  3, 7, -1, 3, 0, "Genesis")
expect_nav("prev cross-line (start of line 3) → last citation of line 1",
  3, 0, -1, 1, 15, "1 Corinthians")
expect_nav("prev from a blank line → last citation of line 1",
  2, 0, -1, 1, 15, "1 Corinthians")
expect_nil("prev before the first citation → nil", 1, 0, -1)
expect_nil("next after the last citation → nil", 3, 19, 1)

vim.api.nvim_buf_delete(nav_buf, { force = true })

-- ---------------------------------------------------------------------------
-- Tests: Verse stepping (db.next_verse / prev_verse, F2)
-- ---------------------------------------------------------------------------
section("Verse Stepping (db.next_verse / prev_verse)")

local db = require("bible_ref.db")

local vdir = vim.fn.tempname()
assert(vim.fn.mkdir(vdir, "p") == 1)
write_at(vdir, "bible_web2.json", {
  ["James 1:1"]         = "WEB2: James 1:1.",
  ["James 1:2"]         = "WEB2: James 1:2.",
  ["James 1:3"]         = "WEB2: James 1:3.",
  ["James 2:1"]         = "WEB2: James 2:1.",
  ["James 2:2"]         = "WEB2: James 2:2.",
  ["James 2:3"]         = "WEB2: James 2:3.",
  ["1 Corinthians 4:2"] = "WEB2: 1 Corinthians 4:2.",
  ["1 Corinthians 4:3"] = "WEB2: 1 Corinthians 4:3.",
  ["1 Corinthians 5:1"] = "WEB2: 1 Corinthians 5:1.",
})
write_at(vdir, "bible_testb2.json", {
  -- Deliberately partial: no James ch. 2, no 1 Cor 4:3 / 5:1.
  ["James 1:1"]         = "TESTB2: James 1:1.",
  ["James 1:2"]         = "TESTB2: James 1:2.",
  ["James 1:3"]         = "TESTB2: James 1:3.",
  ["1 Corinthians 4:2"] = "TESTB2: 1 Corinthians 4:2.",
})
cfg.setup({ data_dir = vdir })

local function fmt(r)
  return r
    and (r.book .. " " .. tostring(r.chapter) .. ":" .. tostring(r.verse_start))
    or "nil"
end

local function step_test(name, got, exp_book, exp_ch, exp_vs)
  ok(name,
    got ~= nil and got.book == exp_book
      and got.chapter == exp_ch and got.verse_start == exp_vs,
    "got " .. fmt(got) .. " (want "
      .. exp_book .. " " .. tostring(exp_ch) .. ":" .. tostring(exp_vs) .. ")")
end

local function step_nil(name, got)
  ok(name, got == nil, "got " .. fmt(got))
end

step_test("next: Jas 1:2 → 1:3",
  db.next_verse({ book = "James", chapter = 1, verse_start = 2 }, "WEB2"),
  "James", 1, 3)
step_test("next: range 1:1–3 steps from its end → 2:1",
  db.next_verse({ book = "James", chapter = 1, verse_start = 1, verse_end = 3 }, "WEB2"),
  "James", 2, 1)
step_test("next: 1 Cor 4:2 → 4:3",
  db.next_verse({ book = "1 Corinthians", chapter = 4, verse_start = 2 }, "WEB2"),
  "1 Corinthians", 4, 3)
step_test("next: 1 Cor 4:3 → 5:1 (chapter wrap)",
  db.next_verse({ book = "1 Corinthians", chapter = 4, verse_start = 3 }, "WEB2"),
  "1 Corinthians", 5, 1)
step_nil("next: book end (Jas 2:3) → nil",
  db.next_verse({ book = "James", chapter = 2, verse_start = 3 }, "WEB2"))
step_nil("next: book end (1 Cor 5:1) → nil",
  db.next_verse({ book = "1 Corinthians", chapter = 5, verse_start = 1 }, "WEB2"))
step_nil("next: absent book (Genesis) → nil",
  db.next_verse({ book = "Genesis", chapter = 1, verse_start = 1 }, "WEB2"))

step_test("prev: Jas 1:2 → 1:1",
  db.prev_verse({ book = "James", chapter = 1, verse_start = 2 }, "WEB2"),
  "James", 1, 1)
step_test("prev: range 1:2–3 → 1:1 (verse before range start)",
  db.prev_verse({ book = "James", chapter = 1, verse_start = 2, verse_end = 3 }, "WEB2"),
  "James", 1, 1)
step_test("prev: Jas 2:1 → 1:3 (chapter wrap to last verse)",
  db.prev_verse({ book = "James", chapter = 2, verse_start = 1 }, "WEB2"),
  "James", 1, 3)
step_nil("prev: book start (Jas 1:1) → nil",
  db.prev_verse({ book = "James", chapter = 1, verse_start = 1 }, "WEB2"))
step_nil("prev: absent book (Genesis) → nil",
  db.prev_verse({ book = "Genesis", chapter = 1, verse_start = 1 }, "WEB2"))

-- Partial dataset: stepping is bounded by what the dataset contains.
step_test("partial: TESTB2 Jas 1:2 → 1:3",
  db.next_verse({ book = "James", chapter = 1, verse_start = 2 }, "TESTB2"),
  "James", 1, 3)
step_nil("partial: TESTB2 Jas 1:3 → nil (ch. 2 absent in dataset)",
  db.next_verse({ book = "James", chapter = 1, verse_start = 3 }, "TESTB2"))
step_nil("partial: TESTB2 1 Cor 4:2 → nil (4:3 absent in dataset)",
  db.next_verse({ book = "1 Corinthians", chapter = 4, verse_start = 2 }, "TESTB2"))
step_nil("partial: TESTB2 Jas 1:1 → nil (book start)",
  db.prev_verse({ book = "James", chapter = 1, verse_start = 1 }, "TESTB2"))

ok("max_chapter(James, WEB2) = 2", db.max_chapter("James", "WEB2") == 2,
  "got: " .. tostring(db.max_chapter("James", "WEB2")))
ok("max_verse(James, 2, WEB2) = 3", db.max_verse("James", 2, "WEB2") == 3,
  "got: " .. tostring(db.max_verse("James", 2, "WEB2")))
ok("max_chapter(Genesis, WEB2) = nil (absent book)",
  db.max_chapter("Genesis", "WEB2") == nil)
ok("max_verse(James, 99, WEB2) = nil (absent chapter)",
  db.max_verse("James", 99, "WEB2") == nil)

-- Omitted tag resolves to the active version.
cfg.set_version("WEB2")
step_test("omitted tag uses the active version (Jas 1:2 → 1:3)",
  db.next_verse({ book = "James", chapter = 1, verse_start = 2 }),
  "James", 1, 3)

-- Cleanup temp dir
vim.fn.delete(vdir, "rf")

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
io.write(string.format(
  "\n\27[1m%d passed, %d failed\27[0m\n",
  pass_count, fail_count
))

if fail_count > 0 then
  io.write("\nFailed tests:\n")
  for _, e in ipairs(errors) do
    io.write("  • " .. e .. "\n")
  end
  os.exit(1)
else
  os.exit(0)
end
