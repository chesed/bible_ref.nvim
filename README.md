# bible\_ref.nvim

A modular Neovim Lua plugin for Bible reference inspection and SBL-style citation insertion. Designed for Markdown, LaTeX, and plain-text theological writing.

> [!NOTE]
> **Development status:** Core implementation complete and passing all 53 unit tests (Neovim 0.12.6 headless). One remaining task before the plugin is fully usable: placing a Bible JSON dataset at `data/bible.json`. See [Data](#data) and [Development Log](#development-log).

## Features

- **`:BibleHover`** — Inspect any Bible reference under the cursor in an LSP-style floating window; press `l` to open it in [Logos.com](https://logos.com).
- **`:BiblePick`** — Fuzzy-search all verses (via `fzf-lua` or `vim.ui.select`) and insert an SBL-formatted abbreviation at the cursor (`Jas 1:1`, `1 Cor 4:2`, etc.).
- **`:BibleOpenLogos`** — Open the reference under the cursor directly in Logos.com.

Understands a wide range of reference formats:

| Written form       | Resolved as             |
|--------------------|-------------------------|
| `Jas. 3:1`         | James 3:1               |
| `James 3:1-3`      | James 3:1–3 (range)     |
| `1 Cor. 4:2–5`     | 1 Corinthians 4:2–5     |
| `2 Pet 1:4`        | 2 Peter 1:4             |
| `1Cor 4:2`         | 1 Corinthians 4:2       |
| `(cf. Jas 3:1)`    | James 3:1 (strips parens)|
| `\bref{Jas 3:1}`   | James 3:1 (strips LaTeX) |

## Requirements

- Neovim ≥ 0.10
- A verse-by-verse JSON Bible dataset (see [Data](#data))
- [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) *(recommended)* or any `vim.ui.select` provider (e.g. `snacks.nvim`)

## Installation

### lazy.nvim

```lua
{
  "your-username/bible_ref.nvim",
  config = function()
    require("bible_ref").setup({
      -- json_path defaults to <plugin_root>/data/bible.json
      -- json_path = vim.fn.expand("~/.local/share/nvim/bible/esv.json"),
      keymaps = {
        hover      = "<leader>bh",
        pick       = "<leader>bp",
        open_logos = "<leader>bl",
      },
    })
  end,
}
```

## Data

The plugin looks for a JSON Bible dataset at `<plugin_root>/data/bible.json`.

**Expected schema (flat map):**

```json
{
  "Genesis 1:1": "In the beginning, God created the heavens and the earth.",
  "Genesis 1:2": "The earth was without form and void...",
  ...
}
```

The array-of-objects schema is also supported:

```json
[
  { "book": "Genesis", "chapter": 1, "verse": 1, "text": "In the beginning..." },
  ...
]
```

### Getting a dataset

A freely usable ESV-style dataset can be obtained from open-source sources such as:
- [acbellini/esv-json](https://github.com/acbellini/esv-json) — ESV flat map
- [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases) — multi-translation exports

> **Note:** ESV text is copyright Crossway. For personal use only. The plugin is translation-agnostic; substitute any dataset using the same schema.

Place the file at `data/bible.json` inside the plugin repo, or configure a custom path:

```lua
require("bible_ref").setup({
  json_path = vim.fn.expand("~/.local/share/nvim/bible/esv.json"),
})
```

## Usage

### Keymaps (default)

| Keymap       | Command            | Action                               |
|--------------|--------------------|--------------------------------------|
| `<leader>bh` | `:BibleHover`      | Show verse preview under cursor      |
| `<leader>bp` | `:BiblePick`       | Open fuzzy verse picker              |
| `<leader>bl` | `:BibleOpenLogos`  | Open reference in Logos.com          |

### In the floating preview window

| Key       | Action                    |
|-----------|---------------------------|
| `l`       | Open passage in Logos.com |
| `q`/`Esc` | Close preview             |

### In the picker

| Key    | Action                                    |
|--------|-------------------------------------------|
| `<CR>` | Insert SBL reference at cursor position   |
| `<C-l>`| Open highlighted verse in Logos.com       |
| `<C-o>`| Open highlighted verse in Logos.com (alt) |

## Configuration

```lua
require("bible_ref").setup({
  -- Path to Bible JSON dataset
  json_path = nil,  -- defaults to <plugin_root>/data/bible.json

  -- Preferred picker: "fzf-lua" | "select" | "auto" (default)
  picker = "auto",

  -- Global keymap bindings (set any to false to disable)
  keymaps = {
    hover      = "<leader>bh",
    pick       = "<leader>bp",
    open_logos = "<leader>bl",
  },
})
```

## SBL Abbreviations

All 66 canonical books are mapped to SBL 2nd-edition standard abbreviations (no trailing periods):

`Gen · Exod · Lev · Num · Deut · Josh · Judg · Ruth · 1 Sam · 2 Sam · 1 Kgs · 2 Kgs · 1 Chr · 2 Chr · Ezra · Neh · Esth · Job · Ps · Prov · Eccl · Song · Isa · Jer · Lam · Ezek · Dan · Hos · Joel · Amos · Obad · Jonah · Mic · Nah · Hab · Zeph · Hag · Zech · Mal · Matt · Mark · Luke · John · Acts · Rom · 1 Cor · 2 Cor · Gal · Eph · Phil · Col · 1 Thess · 2 Thess · 1 Tim · 2 Tim · Titus · Phlm · Heb · Jas · 1 Pet · 2 Pet · 1 John · 2 John · 3 John · Jude · Rev`

## Testing

Run the headless test suite:

```bash
nvim --headless -u NONE -l tests/run_tests.lua
```

Tests cover:
1. SBL abbreviation resolution and formatting
2. Reference parsing (all major formats and edge cases)
3. Database lookup (single verse, range, missing verse fallback)

## Architecture

```
lua/bible_ref/
├── init.lua       Public API, setup(), user command registration
├── db.lua         JSON loader (lazy), verse index, lookup + range
├── parse.lua      Reference parser, alias resolution, cursor span
├── sbl.lua        SBL book map and reference formatter
├── logos.lua      Logos.com URL builder and browser launcher
└── ui/
    ├── float.lua  LSP-style floating window preview
    └── picker.lua fzf-lua / vim.ui.select picker integration
```

---

## Development Log

### Session 1 — 2026-11-22

**Agent:** Antigravity (Claude Sonnet 4.6 Thinking)
**Neovim version:** 0.12.6 / LuaJIT 2.1

#### What was built

Scaffolded the complete plugin from the `AGENT_SPEC.md` blueprint. All seven Lua modules were written, iterated on, and brought to a fully passing test suite in a single session.

**Files created:**

| File | Purpose |
|------|---------|
| `lua/bible_ref/init.lua` | `setup()`, user commands, default keymaps |
| `lua/bible_ref/db.lua` | Lazy JSON loader, verse index, single + range lookup |
| `lua/bible_ref/parse.lua` | Reference parser, alias table (all 66 books × variants), cursor-span extractor |
| `lua/bible_ref/sbl.lua` | SBL 2nd-ed. abbreviation map, `format()` function |
| `lua/bible_ref/logos.lua` | Logos.com URL builder, `vim.ui.open` + `xdg-open` fallback |
| `lua/bible_ref/ui/float.lua` | LSP-style `nvim_open_win` preview with `q`/`Esc`/`l` keymaps |
| `lua/bible_ref/ui/picker.lua` | fzf-lua primary picker with `<CR>` insert + `<C-l>`/`<C-o>` Logos actions; `vim.ui.select` fallback |
| `tests/run_tests.lua` | Headless unit test runner (no external test framework required) |
| `data/README.md` | Dataset acquisition instructions |
| `README.md` | This file |

#### Design decisions made

- **Translation:** ESV as target translation, but schema is fully agnostic — user configures any flat-map or array-of-objects JSON via `setup({ json_path = "..." })`.
- **Dataset location:** `data/bible.json` inside the plugin repo (default); user-configurable via `setup()`.
- **Picker:** `fzf-lua` primary (detected via `pcall(require, "fzf-lua")`), `vim.ui.select` fallback — compatible with `snacks.nvim` picker which implements `vim.ui.select`.
- **URL opener:** `vim.ui.open` (Neovim 0.10+) with `xdg-open` fallback.
- **Lazy loading:** JSON dataset is not read at startup — deferred until first `:BibleHover` or `:BiblePick` invocation.
- **Multi-byte ranges:** en-dash (`–` U+2013) and em-dash (`—` U+2014) are handled as explicit 3-byte UTF-8 sequences in the parser (Lua `string.find` is byte-level).

#### Parser edge cases resolved

Three edge cases required iteration to pass tests:

1. **Dotted abbreviations** (`Jas. 3:1`) — initial `cf.`-prefix stripping accidentally consumed book abbrevs with dots. Fixed with an explicit `known_prefixes` allowlist.
2. **Compressed numbered books** (`1Cor 4:2`) — initial regex required a space after the digit prefix. Fixed by detecting `^([123])%u` (digit immediately followed by uppercase).
3. **En-dash verse ranges** (`4:2–5`) — the `[%-...]` character class doesn't handle multi-byte UTF-8 sequences. Fixed by extracting verse-end separately with explicit `\xE2\x80\x93` byte pattern.

#### Test results

```
nvim --headless -u NONE -l tests/run_tests.lua
```

```
SBL Formatting    8/8  ✓
Reference Parsing 40/40 ✓  (covers Jas./1Cor/en-dash/cf./bracket wrapping)
Database Lookups   5/5  ✓  (single, range, missing-verse fallback)

53 passed, 0 failed  — exit 0
```

#### What remains (handoff to local agent)

See [`AGENT_INSTRUCTIONS.md`](AGENT_INSTRUCTIONS.md) for the complete handoff brief.
