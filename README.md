# bible\_ref.nvim

A modular Neovim Lua plugin for Bible reference inspection and SBL-style citation insertion. Designed for Markdown, LaTeX, and plain-text theological writing.

> **Status (2026-11-23):** v1.0 — first public release. Multi-version dataset
> support: automatic discovery of every translation in `data/` and `data/user/`,
> lazy per-version indexing, version cycling in both the hover window and the
> picker, and span-aware hover on lines with multiple citations.
> 84/84 headless unit tests passing.

## Features

- **`:BibleHover`** — Inspect any Bible reference under the cursor in an LSP-style floating window.
  - `<Space>` / `<Tab>` — next installed translation
  - `<S-Tab>` — previous translation (wraps around)
  - `h` / `l` — previous / next citation in the document (display only)
  - `H` / `L` — jump the cursor to the previous / next citation (float re-anchors)
  - `j` / `k` — next / previous canonical verse (wraps chapters, stops at book edges)
  - `o` — open the passage in Logos
  - `q` / `<Esc>` — close
- **`:BiblePick`** — Fuzzy-search all verses of the active dataset (`fzf-lua` primary, `vim.ui.select` fallback) and insert an SBL-formatted abbreviation at the cursor (`Jas 1:1`, `1 Cor 4:2`, …).
  - `TAB` — cycle to the next dataset (picker reopens with the new dataset)
  - `<CR>` — insert the reference (optionally with the version tag)
  - `<C-l>` / `<C-o>` — open the highlighted verse in Logos
- **`:BibleVersion [tag]`** — Without arguments: list installed datasets and mark the active one. With an argument (`:BibleVersion KJV`): set it active. Case-insensitive.
- **`:BibleOpenLogos`** — Open the reference under the cursor directly in Logos.com.
- **Multi-version datasets** — Any number of translations live side by side in `data/`; each is loaded lazily on first use.
- **Translation-aware insertion** — Optionally append the version tag to inserted references when the active dataset is not the default one (`Jas 3:1 KJV`).

Understands a wide range of reference formats:

| Written form       | Resolved as             |
|--------------------|-------------------------|
| `Jas. 3:1`         | James 3:1               |
| `James 3:1-3`      | James 3:1–3 (range)     |
| `1 Cor. 4:2–5`     | 1 Corinthians 4:2–5     |
| `2 Pet 1:4`        | 2 Peter 1:4             |
| `1Cor 4:2`         | 1 Corinthians 4:2       |
| `(cf. Jas 3:1)`    | James 3:1 (strips parens) |
| `\bref{Jas 3:1}`   | James 3:1 (strips LaTeX) |

## Requirements

- Neovim ≥ 0.10
- At least one verse-by-verse JSON dataset for the whole Bible. Package includes three open-source datasets: (1) the WEB bible (default); (2) the KJV; (3) an original-language dataset composed of the WLC for Hebrew and SBLGNT for Greek (see [Data](#data))
- [`fzf-lua`](https://github.com/ibhagwan/fzf-lua) *(recommended)* or any `vim.ui.select` provider (e.g. `snacks.nvim`)

## Installation

### lazy.nvim

```lua
{
  "chesed/bible_ref.nvim",
  config = function()
    require("bible_ref").setup({
      keymaps = {
        hover      = "<leader>rh",
        pick       = "<leader>rp",
        open_logos = "<leader>ro",
      },
    })
  end,
}
```

## Data

Datasets are **discovered automatically** from two directories (default
`<plugin_root>/data/` and `<plugin_root>/data/user/`):

| Location       | Purpose                                                        |
|----------------|----------------------------------------------------------------|
| `data/`        | Public datasets, shipped with the repository                   |
| `data/user/`   | **Your** private datasets — add your own datasets here (see [Data Format](#data-format))        |

In both directories:

| File               | Tag            | Role                                    |
|--------------------|----------------|------------------------------------------|
| `bible_<tag>.json` | `<TAG>` upper | A translation; hyphens allowed          |

Examples: `bible_kjv.json` → `KJV`, `bible_wlc-sblgnt.json` → `WLC-SBLGNT`.
Well-known tags get human-readable labels in the `:BibleVersion` list (e.g.
`WLC-SBLGNT` → "Westminster Leningrad Codex + SBL Greek NT"); unknown tags fall
back to the uppercase tag itself.

**Shadowing (the override slot):** a file in `data/user/` with the same name
as one in `data/` replaces the shipped copy — same name ⇒ same tag — with a
one-time warning. Drop a `bible_kjv.json` you prefer into `data/user/` and it
silently wins.

**Shipped in this repository (public domain):** WEB (`bible_web.json`, the
built-in default), KJV (`bible_kjv.json`), and WLC-SBLGNT
(`bible_wlc-sblgnt.json` — Westminster Leningrad Codex Hebrew OT + SBL Greek
NT, 31,083 entries). A fresh clone therefore starts its rotation with WEB;
set `default_version` to change the starting dataset.

### Data Format

**Supported schemas** (auto-detected per file):

```json
{ "Genesis 1:1": "In the beginning, God created the heavens and the earth.", ... }
```

or

```json
[ { "book": "Genesis", "chapter": 1, "verse": 1, "text": "In the beginning..." }, ... ]
```

> **Graceful misses:** verses absent from a dataset (e.g. an OT reference against a
> Greek NT-only dataset) render as `[Mal 4:6 — not present in WLC-SBLGNT]` instead
> of crashing.

Sources for free datasets (will need to be converted to match the schema's described above): [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases).

## Usage

### Commands & global keymaps

Default keymaps can be changed via config options.

| Keymap       | Command            | Action                               |
|--------------|--------------------|--------------------------------------|
| `<leader>rh` | `:BibleHover`      | Show verse preview under cursor      |
| `<leader>rp` | `:BiblePick`       | Open fuzzy verse picker              |
| `<leader>ro` | `:BibleOpenLogos`  | Open reference in Logos.com          |

### In the floating preview window

| Key          | Action                                          |
|--------------|-------------------------------------------------|
| `<Space>`,`<Tab>` | Next translation (wraps)                  |
| `<S-Tab>`    | Previous translation (wraps)                   |
| `h` / `l`    | Previous / next citation in the document       |
| `H` / `L`    | Jump cursor to previous / next citation        |
| `j` / `k`    | Next / previous canonical verse (stops at book edges) |
| `o`          | Open passage in Logos.com                      |
| `q`/`<Esc>`  | Close preview                                  |

The window header shows the reference and the active tag: `Jas 3:1  [Version: KJV]`.

### In the picker

| Key          | Action                                          |
|--------------|-------------------------------------------------|
| `<CR>`       | Insert SBL reference at cursor position         |
| `<C-v>`      | Cycle dataset (prompt shows the new tag)        |
| `<C-l>`/`<C-o>` | Open highlighted verse in Logos.com         |

The prompt reflects the active dataset: `Bible [KJV] >`.

## Configuration

```lua
require("bible_ref").setup({
  -- Directory to scan for datasets (default <plugin_root>/data/)
  data_dir = nil,

  -- Explicit version list, overriding directory discovery:
  -- versions = {
  --   { tag = "ESV",  path = "/abs/path/esv.json",  label = "ESV" },
  --   { tag = "KJV",  path = "/abs/path/kjv.json",  label = "KJV" },
  -- },

  -- Starting active version (tag string or 1-based index).
  -- Case-insensitive tag; the tag is whatever follows `bible_` in the
  -- filename — e.g. default_version = "esv" selects bible_esv.json.
  -- When unset, the built-in default applies: WEB, if present; otherwise
  -- the first dataset in the registry.
  default_version = nil,

  -- Picker
  picker = {
    backend        = "auto",   -- "auto" | "fzf-lua" | "select"
    append_version = false,    -- true → "Jas 3:1 KJV" for non-default datasets
  },

  -- Global keymap bindings (set any to false to disable)
  keymaps = {
    hover      = "<leader>rh",
    pick       = "<leader>rp",
    open_logos = "<leader>ro",
  },

  -- Which filetypes to restrict keymaps to (empty = all)
  filetypes = {},

  -- v1 backward-compat: a single dataset path collapses the registry
  json_path = nil,
})
```

## Lua API

```lua
require("bible_ref").setup(opts)          -- see Configuration
require("bible_ref").set_version("KJV")   -- set active dataset (case-insensitive); returns bool
require("bible_ref").get_version()        -- active version entry
require("bible_ref").get_version("KJV")   -- entry by tag or 1-based index
require("bible_ref").get_versions()       -- all registered versions, in order
require("bible_ref").get_current_version()
require("bible_ref").opts()               -- merged options after setup()
```

## SBL Abbreviations

All 66 canonical books are mapped to SBL 2nd-edition standard abbreviations (no trailing periods):

`Gen · Exod · Lev · Num · Deut · Josh · Judg · Ruth · 1 Sam · 2 Sam · 1 Kgs · 2 Kgs · 1 Chr · 2 Chr · Ezra · Neh · Esth · Job · Ps · Prov · Eccl · Song · Isa · Jer · Lam · Ezek · Dan · Hos · Joel · Amos · Obad · Jonah · Mic · Nah · Hab · Zeph · Hag · Zech · Mal · Matt · Mark · Luke · John · Acts · Rom · 1 Cor · 2 Cor · Gal · Eph · Phil · Col · 1 Thess · 2 Thess · 1 Tim · 2 Tim · Titus · Phlm · Heb · Jas · 1 Pet · 2 Pet · 1 John · 2 John · 3 John · Jude · Rev`

## Testing

```bash
luac -p lua/bible_ref/*.lua lua/bible_ref/ui/*.lua   # syntax
nvim --headless -u NONE -l tests/run_tests.lua        # unit suite (84 tests)
```

The suite is **hermetic**: it builds its own temporary dataset directories
(`WEB`/`TESTB`/`KJV`), so it never depends on which datasets live in `data/`.
Covers: SBL formatting, reference parsing, multi-citation hover (cursor-span
selection), per-version lookups and ranges, version discovery/rotation, the
built-in default (WEB, with no-WEB fallback), `data/user/` shadowing, and
lazy-load markers.

## Architecture

```
lua/bible_ref/
├── init.lua       Public API, setup(), user command + keymap registration
├── config.lua     Version registry: discovery, labels, stateful rotation
├── db.lua         Lazy per-version JSON index; lookup/lookup_range (dual signature)
├── parse.lua      Reference parser, alias resolution, cursor span extraction
├── sbl.lua        SBL book map, reference formatter, canonical book order
├── logos.lua      Logos URL builder and browser launcher
└── ui/
    ├── float.lua  LSP-style floating window with version-cycling keymaps
    └── picker.lua fzf-lua / vim.ui.select picker with dataset cycling
```

## License

MIT — see [LICENSE](LICENSE).

## Roadmap

See [PLANS.md](PLANS.md) for the post-release backlog (picker keymap
redesign, expanded corpora: apocrypha → church fathers → pseudepigrapha →
Qumran, and citation navigation).
