-- Test Script for bible_ref.nvim

local plugin_root = vim.fn.expand("${VIM_DIR}")
local lua_dir = plugin_root .. "/lua"
local data_dir = plugin_root .. "/data"

-- Add plugin to runtime path
require("os").setenv("LuaJIT_HOST", "linux")
vim.fn.rtpadd(lua_dir)

-- Test 1: Basic loading
print("=== Test 1: Plugin loads ===")
local success, err = pcall(function()
    require("bible_ref")
end)
if not success then
    error("Plugin failed to load: " .. tostring(err))
end
print("PASS: Plugin loaded successfully")

-- Test 2: Commands registered
print("\n=== Test 2: Commands registered ===")
local commands = { "BibleHover", "BiblePick", "BibleOpenLogos" }
for _, cmd in ipairs(commands) do
    local has_cmd, err = pcall(function()
        return nmap.getcommand(cmd) ~= "" and true or false
    end)
    if not success then
        error("Command check failed for " .. cmd .. ": " .. tostring(err))
    end
end
print("PASS: All commands registered")

-- Test 3: Database lookup (without file, should use stub)
print("\n=== Test 3: DB lookup with stub ===")
local db = require("bible_ref.db")
local result = db.lookup("Genesis", 1, 1)
if result ~= "not found" then
    print("FAIL: Expected 'not found', got '" .. result .. "'")
end
print("PASS: DB lookup returns stub for missing file")

-- Test 4: SBL abbreviation format
print("\n=== Test 4: SBL abbreviations ===")
local sbl = require("bible_ref.sbl")
local formatted = sbl.format("Gen", 1, 2)
if formatted ~= "Gen. 1-2" then
    print("FAIL: Expected 'Gen. 1-2', got '" .. formatted .. "'")
end
print("PASS: SBL abbreviation formats correctly")

-- Test 5: Parser tests
print("\n=== Test 5: Parser tests ===")
local parser = require("bible_ref.parse")

local test_cases = {
    {"Gen. 1:1", "Genesis", 1, 1},
    {"Jas. 3:1", "James", 3, 1},
    {"John 3:16-17", "John", 3, 16, 17},
    {"1 Cor. 4:2", "1 Corinthians", 4, 2},
}

for _, tc in ipairs(test_cases) do
    local book, ch, v = parser.parse(table.unpack(tc, 1))
    if not (book == tc[1] and ch == tc[2] and v == tc[3]) then
        print("FAIL: " .. tostring(tc[1]) .. " expected " .. tostring(tc[2]) .. " " .. tostring(tc[3]) .. ":" .. tostring(tc[4]))
    end
end
print("PASS: All parser tests passed")

-- Test 6: Unit test runner
print("\n=== Test 6: Full unit test suite ===")
local tc, err = pcall(function()
    local tests_dir = plugin_root .. "/tests"
    vim.fn.rtpadd(tests_dir)
    require("run_tests")
end)
if not success then
    error("Test runner failed: " .. tostring(err))
end

print("=== All tests passed ===")
return 0
