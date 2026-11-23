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

write_dataset("bible.json", {
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

ok("discovered exactly 2 versions (bible.json, bible_testb.json)",
  #versions == 2, "got: " .. tostring(#versions))

ok("first version tagged ESV (bible.json)",
  versions[1] and versions[1].tag == "ESV",
  "got: " .. tostring(versions[1] and versions[1].tag))

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

cfg.set_version("ESV") -- restore primary as active

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
  db.lookup(2, "James", 1, 1):find("TESTB:") ~= nil,
  "got: " .. db.lookup(2, "James", 1, 1):sub(1, 60))

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

ok("all_entries('ESV') has 5 entries in canonical order",
  (function()
    local es = db.all_entries("ESV")
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
