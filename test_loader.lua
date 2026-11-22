-- Test loader script for debugging plugin loading issues
local plugin_root = "/home/tommy/Nephos/Code/neovim/bible_ref.nvim"

print("=== Testing bible_ref.parse module ===")
-- Add rtp before requiring modules (inline in the script)
local tests_dir = plugin_root .. "/tests"
eval('rtpadd("' .. vim.fn.expand(plugin_root) .. '"/tests")')

local p = require("bible_ref.parse")
print("✓ parse module loaded successfully")

-- Test a few parse functions
print("\n=== Testing parse functions ===")

if type(p) ~= "table" then
    print("✗ Error: require returned non-table value")
    return
end

-- Test parse function with simple reference
local ref = p.parse("Jas 3:1")
print("parse('Jas 3:1') =", ref)

-- Test parse with range
ref = p.parse("Gen 1:1-5")
print("parse('Gen 1:1-5') =", ref)

-- Test parse with multi-word book
ref = p.parse("Song of Solomon 1:1")
print("parse('Song of Solomon 1:1') =", ref)

-- Test parse with LaTeX macros
ref = p.parse("\\bref{Jas 3:1}")
print("parse('\\bref{Jas 3:1}') =", ref)

-- Test parse with en-dash range (using actual em-dash character U+2013)
ref = p.parse("John 3:16\u{2013}17")
print("parse('John 3:16\u{2013}17') =", ref)

-- Test ref_at_cursor (with empty string input should return nil)
ref = p.ref_at_cursor("")
print("ref_at_cursor('') =", ref)

print("\n=== Testing db module ===")
local d = require("bible_ref.db")
print("✓ db module loaded successfully")

-- Test set_path
d.set_path(plugin_root .. "/data/bible.json")
print("✓ set_path called")

-- Test is_loaded (should be false since json file doesn't exist)
if d.is_loaded() then
    print("✗ Error: is_loaded returned true without data file")
else
    print("✓ is_loaded returns false as expected")
end

-- Test lookup with no dataset loaded
result = d.lookup("Gen", 1, 1)
print("lookup('Gen', 1, 1)", result)

print("\n=== Testing sbl module ===")
local s = require("bible_ref.sbl")
print("✓ sbl module loaded successfully")

ref_str = s.format({book = "Jas", chapter = 3, verse_start = 1})
print("sbl.format(Jas 3:1)", ref_str)

print("\n=== Testing logos module ===")
local l = require("bible_ref.logos")
print("✓ logos module loaded successfully")

url = l.open("Jas 3:1")
print("logos.open('Jas 3:1') =", url)

print("\n=== Testing float module (just check it loads) ===")
local f = require("bible_ref.ui.float")
print("✓ float module loaded successfully")

-- Check that M.show exists and is callable
if f.show then
    print("✓ float.show is available")
else
    print("✗ Error: M.show not found in float module")
end

print("\n=== Testing picker module (just check it loads) ===")
local pk = require("bible_ref.ui.picker")
print("✓ picker module loaded successfully")

if pk.open then
    print("✓ picker.open is available")
else
    print("✗ Error: M.open not found in picker module")
end

print("\n=== All modules loaded successfully! ===")
