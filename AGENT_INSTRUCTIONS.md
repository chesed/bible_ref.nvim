# Agent Instructions — `bible_ref.nvim`

> **For:** Local LLM agent continuing development
> **Handed off by:** Antigravity (Claude Sonnet 4.6 Thinking), 2026-11-22
> **Neovim version on target machine:** 0.12.6 / LuaJIT 2.1

---

## Current State

The plugin is **fully scaffolded and all 53 unit tests pass** in headless Neovim. Every Lua module listed in `AGENT_SPEC.md` has been written.

```
bible_ref.nvim/
├── AGENT_SPEC.md              Original specification (source of truth)
├── AGENT_INSTRUCTIONS.md      This file
├── README.md                  User-facing docs + development log
├── data/
│   └── README.md              ← bible.json goes HERE (not yet present)
├── lua/bible_ref/
│   ├── init.lua               setup(), commands, keymaps
│   ├── db.lua                 JSON loader + verse index
│   ├── parse.lua              Reference parser (cursor + string)
│   ├── sbl.lua                SBL abbreviation map + formatter
│   ├── logos.lua              Logos.com URL + browser opener
│   └── ui/
│       ├── float.lua          LSP-style float window
│       └── picker.lua         fzf-lua / vim.ui.select picker
└── tests/
    └── run_tests.lua          Headless test runner
```

**Run tests at any time with:**
```bash
nvim --headless -u NONE -l tests/run_tests.lua
```
Expected output: `53 passed, 0 failed` — exit code 0.

---

## Your Tasks

Work through these in order. After each step, run the test suite and confirm exit 0 before moving on.

---

### Task 1 — Acquire the Bible JSON Dataset

The plugin cannot do real verse lookups without `data/bible.json`. The unit tests use an in-memory stub, so they pass without it, but the plugin will fail silently at runtime.

**Goal:** Place a verse-by-verse JSON file at:
```
bible_ref.nvim/data/bible.json
```

**Preferred schema (flat map):**
```json
{
  "Genesis 1:1": "In the beginning, God created the heavens and the earth.",
  "Genesis 1:2": "The earth was without form and void...",
  ...
}
```

**Where to get it:**
- ESV flat map: https://github.com/acbellini/esv-json
- Multi-translation (includes ESV, KJV, etc.): https://github.com/scrollmapper/bible_databases
- KJV (fully public domain, no copyright concerns): many sources; e.g. https://github.com/thiagobodruk/bible

The array-of-objects schema is also supported by `db.lua` automatically:
```json
[{ "book": "Genesis", "chapter": 1, "verse": 1, "text": "In the beginning..." }, ...]
```

> **Copyright note:** ESV is © Crossway; personal use only. KJV and WEB are public domain. The plugin's `db.lua` is translation-agnostic — just match the schema above.

**After placing the file:**
1. Open Neovim (not headless).
2. Run `:lua require("bible_ref.db").set_path(vim.fn.getcwd() .. "/data/bible.json")`.
3. Run `:lua print(require("bible_ref.db").lookup("James", 1, 1))`.
4. Confirm you see the actual verse text (not a "not found" fallback).

---

### Task 2 — Wire the Plugin into Neovim Config

The user's plugin manager is **lazy.nvim** (located wherever their Neovim config lives).

Add a spec entry like this:

```lua
{
  dir = vim.fn.expand("~/Nephos/Code/neovim/bible_ref.nvim"),
  name = "bible_ref.nvim",
  dependencies = { "ibhagwan/fzf-lua" },   -- fzf-lua is already installed
  config = function()
    require("bible_ref").setup({
      -- json_path defaults to <plugin_dir>/data/bible.json automatically
      keymaps = {
        hover      = "<leader>bh",
        pick       = "<leader>bp",
        open_logos = "<leader>bl",
      },
    })
  end,
}
```

> **Note:** The user's nvim config location is non-standard (not `~/.config/nvim`). You will need to locate it. Try:
> ```bash
> nvim --headless -u NONE --cmd "lua print(vim.fn.stdpath('config'))" --cmd "qa" 2>&1
> find ~ -maxdepth 5 -name "lazy.lua" -o -name "plugins.lua" 2>/dev/null | grep -v cache
> ```

---

### Task 3 — Interactive Verification

Once the dataset and config are in place, perform the three manual verification steps from `AGENT_SPEC.md § 5`:

#### 3a. `:BibleHover` on a Markdown file

1. Create or open a `.md` file containing: `See Jas. 3:1 for context.`
2. Place cursor anywhere on `Jas. 3:1`.
3. Run `:BibleHover`.
4. **Expected:** A rounded floating window appears with:
   - Header: `Jas 3:1`
   - Body: the verse text
   - Footer: `[l] Open in Logos.com · [q/Esc] Close`
5. Press `l` — Logos.com should open in the default browser.
6. Press `q` — the float should close cleanly.

#### 3b. `:BibleHover` on a range

1. Place cursor on `James 3:1-3`.
2. Run `:BibleHover`.
3. **Expected:** Float shows `Jas 3:1–3` with all three verses concatenated.

#### 3c. `:BiblePick` insert

1. Position cursor at an empty insertion point in a buffer.
2. Run `:BiblePick`.
3. Type `James 1 1` or `Jas 1:1` to filter.
4. Press `<CR>`.
5. **Expected:** `Jas 1:1` is inserted at the original cursor position (not inside the picker).

#### 3d. `:BibleOpenLogos` direct

1. With cursor on `1 Cor 4:2`, run `:BibleOpenLogos`.
2. **Expected:** Browser opens `https://www.logos.com/search?q=1%20Cor%204%3A2`.

---

### Task 4 — Extended Parser Tests (optional but recommended)

Add these test cases to `tests/run_tests.lua` and confirm they pass. These cover real-world writing patterns from the user's theological documents:

```lua
-- LaTeX macro wrappers
check_parse("\\bref{Jas 3:1}",        "James",          3, 1)
check_parse("\\cite{Gen 1:1}",         "Genesis",        1, 1)

-- Em-dash ranges
check_parse("John 3:16\u{2014}17",     "John",           3, 16, 17)

-- Multi-word books
check_parse("Song of Solomon 1:1",     "Song of Solomon", 1, 1)
check_parse("1 Thessalonians 4:13",    "1 Thessalonians", 4, 13)

-- Cursor-span: ref embedded in prose (test via parse.parse(), not ref_at_cursor)
check_parse("cf. 2 Pet. 1:4",          "2 Peter",        1, 4)
check_parse("see also Rev 22:20\u{2013}21", "Revelation", 22, 20, 21)
```

---

### Task 5 — Known Limitations to Address (if time permits)

These are non-blocking but worth fixing:

1. **`parse.ref_at_cursor()`** — The cursor-span extractor uses a heuristic sliding window. It has not been tested interactively. Edge cases to watch for:
   - Cursor sitting exactly on the `:` between chapter and verse.
   - Cursor on a verse number that's also a list item number (e.g., `3. Jas 3:1`).
   - Multi-word books where the cursor is on the second word (`Corinthians`).

2. **Sort order in picker** — `db.all_entries()` sorts alphabetically by key string (`"1 Corinthians|4|2"`). This means `1 Chronicles` sorts before `1 Corinthians` correctly, but `2 Samuel` appears after `Zephaniah` alphabetically. Consider adding a canonical book-order sort using a lookup table.

3. **Performance** — The picker calls `db.all_entries()` which iterates the entire index on every open. For a ~31k-verse dataset this is fast enough, but the result could be cached.

4. **Treesitter highlight** — The float buffer sets `filetype = "bible_ref"` but no syntax/highlight is defined. A simple `vim.api.nvim_buf_add_highlight` call on the separator lines (using `Comment` group) would polish the UI.

---

## Key Design Contracts (do not break)

These invariants must hold across any changes you make:

| Contract | Location |
|----------|----------|
| JSON is **not** read at startup — only on first `:BibleHover` or `:BiblePick` | `db.lua: ensure_loaded()` |
| Picker saves target `{win, buf, row, col}` **before** opening picker | `picker.lua: M.open()` |
| Float uses `bufhidden = "wipe"` scratch buffers | `float.lua` |
| `sbl.format()` uses U+2013 en-dash (not hyphen) for ranges | `sbl.lua` |
| Missing verses return a string, never `nil` or an error | `db.lua: lookup()` |
| `M.parse(s)` in `parse.lua` strips wrappers before `try_parse()` | `parse.lua` |

---

## Running Tests

```bash
# From the plugin root:
nvim --headless -u NONE -l tests/run_tests.lua

# Expected final line:
# 53 passed, 0 failed
```

The test runner is self-contained — no external test framework. It bootstraps the plugin's `lua/` directory onto the runtimepath automatically.

---

## Reference: `AGENT_SPEC.md`

The original specification is at [`AGENT_SPEC.md`](AGENT_SPEC.md). It is authoritative on intent. If anything in the implementation deviates from the spec in a way that matters functionally, follow the spec.
