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
-- Tests: Database lookup (db.lua)
-- ---------------------------------------------------------------------------
section("Database Lookups")

local db = require("bible_ref.db")

-- Use a tiny in-memory stub by patching the internal index directly
-- (avoids needing the real JSON file for unit tests)
do
  -- Access the module's internals by calling set_path with a temp file
  local tmp = os.tmpname() .. ".json"
  local f = io.open(tmp, "w")
  f:write(vim.json.encode({
    ["James 1:1"]         = "James, a servant of God and of the Lord Jesus Christ.",
    ["James 1:2"]         = "Count it all joy, my brothers, when you meet trials of various kinds,",
    ["James 1:3"]         = "for you know that the testing of your faith produces steadfastness.",
    ["1 Corinthians 4:2"] = "Moreover, it is required of stewards that they be found faithful.",
    ["Genesis 1:1"]       = "In the beginning, God created the heavens and the earth.",
  }))
  f:close()
  db.set_path(tmp)
end

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

ok("Missing verse returns fallback string (not error)",
  db.lookup("Jude", 99, 99):find("not found") ~= nil,
  "got: " .. db.lookup("Jude", 99, 99))

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
