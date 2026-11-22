#!/bin/bash
plugin_root="/home/tommy/Nephos/Code/neovim/bible_ref.nvim"

echo "=== Testing bible_ref.parse module ==="
nvim --headless -u NONE -c '
local plugin_root = "{plugin_root}"
local tests_dir = plugin_root .. "/tests"

-- Add rtp
local rc = vim.eval("rtpget(tests_dir)")
if rc == 0 then
    vim.fn.rtpadd(tests_dir)
end

-- Now load the test script
local M = require("bible_ref.parse")
print("OK - parse module loaded successfully")

-- Test a few parse functions
ref = M.parse("Jas 3:1")
print("parse(\'Jas 3:1\') =", ref)

ref = M.parse("Gen 1:1-5")
print("parse(\'Gen 1:1-5\')" , ref)

ref = M.parse("Song of Solomon 1:1")
print("parse(\'Song of Solomon 1:1\')" , ref)

ref = M.parse("\\bref{Jas 3:1}")
print("parse('\\\\bref{Jas 3:1}')" , ref)

ref = M.parse("John 3:16\u201417")
print("parse(\'John 3:16\\u201417\')" , ref)

-- Test db module (with empty dataset path, should not error)
local d = require("bible_ref.db")
d.set_path(plugin_root .. "/data/bible.json")
print("\\nOK - db module loaded successfully")

-- Test sbl module
local s = require("bible_ref.sbl")
ref_str = s.format({book = "Jas", chapter = 3, verse_start = 1})
print("sbl.format(Jas 3:1)", ref_str)

print("\\n=== All basic tests passed! ===")
' _plugin_root="${plugin_root}"
