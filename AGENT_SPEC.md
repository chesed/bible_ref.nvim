
# Agent Task Specification: Neovim Lua Plugin for Bible Reference Inspection & SBL Insertion (`bible_ref.nvim`)

## 1. Project Overview & Objectives

Build a modular, self-contained, filetype-agnostic Neovim Lua plugin (`bible_ref.nvim`) designed primarily for Markdown (`.md`), LaTeX (`.tex`), and plain text buffers. The plugin operates against a verse-by-verse JSON Bible lookup dataset and provides two core capabilities:

1. **Cursor Reference Inspector (LSP-Style Floating Window):**
   - Inspects the reference token/span directly under or adjacent to the cursor across varied human-written reference formats (e.g., `Jas. 3:1`, `James 3:1-3`, `1 Cor. 4:2`, `2 Pet 1:4`).
   - Resolves and formats the verse text in an LSP-style floating window with a clear keybind action to open the passage directly on **logos.com**.
2. **Fuzzy Bible Verse Picker & SBL Reference Inserter:**
   - Provides a fuzzy picker over the JSON Bible dataset using `fzf-lua` (with a fallback architecture for `telescope.nvim` or standard `vim.ui.select`).
   - Inserts the selected verse reference at the active cursor position formatted strictly according to **SBL style** (e.g., selecting `James 1:1` inserts `Jas 1:1`; selecting `1 Corinthians 4:2` inserts `1 Cor 4:2`).
   - Allows opening the highlighted verse directly on **logos.com** via a secondary action within the picker interface.

---

## 2. Environment Discovery & Architecture

### Step 1: Pre-Coding Inspection

1. **Locate Dataset:** Find the verse-by-verse JSON Bible file in the project dataset directory and verify its schema (e.g., flat key-value map `"Genesis 1:1": "..."` vs. array of verse objects vs. nested book/chapter/verse object structure).
2. **Check Available Pickers:** Detect installed fuzzy pickers (`fzf-lua`, `telescope.nvim`, or standard `vim.ui.select`) to support smooth picker selection with zero hard crashes.
3. **Verify Opener:** Use Neovim's standard `vim.ui.open` (Neovim 0.10+) for launching URLs in the user's default browser, with fallback to `xdg-open` / OS handlers where needed.

### Step 2: Directory Layout

Scaffold the standalone plugin repository layout:

```text
bible_ref.nvim/
├── AGENT_SPEC.md
├── README.md
├── lua/
│   └── bible_ref/
│       ├── init.lua          # User setup, public API, and user command registrations
│       ├── db.lua            # JSON loader, lazy memory indexer, lookup & range logic
│       ├── parse.lua         # Reference parsing, alias resolution, cursor span extraction
│       ├── sbl.lua           # Canonical SBL book mapping & reference string formatter
│       ├── logos.lua         # Logos.com URL builder & web opener execution
│       └── ui/
│           ├── float.lua     # LSP-style floating window preview implementation
│           └── picker.lua    # fzf-lua / telescope / vim.ui.select picker integration
└── tests/
    └── run_tests.lua         # Headless Neovim test runner and assertions
```

---

## 3. Detailed Component Specifications

### A. Database Indexing & Lazy Loading (`lua/bible_ref/db.lua`)

- **Lazy Load:** Do **not** parse or load multi-megabyte JSON Bible files during Neovim startup. Defer reading and indexing until the first invocation of `:BibleHover` or `:BiblePick`.
- **Lookup Key Normalization:** Index verses internally under a unified structure (e.g., `Book|Chapter|Verse`).
- **Multi-Verse Range Assembly:** When a range like `John 3:16-17` or `James 3:1–3` is requested, fetch and concatenate contiguous verses cleanly with verse numbers or readable spacing.
- **Fallback:** Return a controlled message string if a reference or verse is missing from the dataset without throwing Lua runtime errors.

### B. Reference Parsing & Range Extraction (`lua/bible_ref/parse.lua`)

- Extract references surrounding the current cursor location in an active buffer:
  - Recognize full book names (`James`, `1 Corinthians`), common abbreviations (`Jas.`, `1 Cor.`, `2 Pet.`), SBL abbreviations (`Jas`, `1 Cor`), and compressed variants (`1Cor`).
  - Account for punctuation variations and multi-byte UTF-8 range dashes: standard hyphens (`-`), en-dashes (`–`), and em-dashes (`—`).
- **Cursor Boundary Detection:** Successfully extract the full reference whether the cursor is resting on the book name, chapter number, colon, dash, or verse number.
- **Syntax Insulation:** Strip surrounding punctuation like parentheses `(cf. Jas 3:1)`, brackets `[1 Cor 4:2]`, or LaTeX command macros (`\bref{Jas 3:1}`) without altering the underlying buffer text.

### C. SBL Standard Formatting (`lua/bible_ref/sbl.lua`)

- Map all biblical books to official SBL standard abbreviations without periods (e.g., `Jas`, `1 Cor`, `2 Pet`, `Matt`, `Gen`, `Phlm`, `Song`).
- Expose a clean formatting function:
  - Input: `{ book = "1 Corinthians", chapter = 4, verse_start = 2 }`
  - Output: `"1 Cor 4:2"`
  - Input: `{ book = "James", chapter = 3, verse_start = 1, verse_end = 3 }`
  - Output: `"Jas 3:1–3"`

### D. Logos URL Generation (`lua/bible_ref/logos.lua`)

- Construct clean passage URLs targeting Logos web readers:
  - Pattern: `https://www.logos.com/search?q=<Normalized_Reference>` (or standard passage view endpoints).
- Execute browser launch cleanly via `vim.ui.open(url)`.

### E. LSP Floating Window UI (`lua/bible_ref/ui/float.lua`)

- Open preview windows via `vim.api.nvim_open_win` styled like LSP hover previews (`border = "rounded"`).
- Display formatted content:
  - Header: SBL reference title.
  - Body: Resolved verse/passage text wrapped cleanly to window width.
  - Footer: Keymap hint (`[l] Open in Logos.com · [q/Esc] Close`).
- Set buffer-local keymaps inside the float:
  - `q` / `<Esc>`: Close float preview window cleanly.
  - `l`: Launch current passage in `logos.com`.

### F. Fuzzy Verse Picker (`lua/bible_ref/ui/picker.lua`)

- Capture target window ID (`vim.api.nvim_get_current_win()`) and cursor position (`vim.api.nvim_win_get_cursor()`) **prior** to opening the picker prompt.
- Populate fuzzy picker options formatted for fast search (`Jas 1:1 — James, a servant of God...`).
- **Picker Actions:**
  - `<CR>` (Accept): Format selection to SBL standard (e.g., `Jas 1:1`) and insert at saved cursor position in target buffer.
  - `<C-l>` / `<C-o>`: Open highlighted entry directly in `logos.com`.

### G. Public API & Command Setup (`lua/bible_ref/init.lua`)

Provide configuration setup and user command definitions:

```lua
local M = {}

function M.setup(opts)
  -- Merge defaults with user options (json_path, picker preferences, keymaps)
end

return M
```

Expose Neovim user commands:

- `:BibleHover` — Inspect reference under cursor in floating window.
- `:BiblePick` — Launch fuzzy picker to search and insert SBL reference.
- `:BibleOpenLogos` — Open passage under cursor directly in `logos.com`.

---

## 4. Edge Cases & Risk Mitigation

1. **Numbered Books vs. Leading Digits:** Ensure parser correctly distinguishes leading book numbers (`1 Cor`, `2 Kgs`, `3 John`) from preceding chapter/verse numbers or list items.
2. **Multi-Byte Character Offsets:** Lua `string.find` operates on byte indexes. When working with UTF-8 en-dashes (`–`) or em-dashes (`—`) in ranges, use UTF-8 aware offsets for precise column placement.
3. **Picker Target Buffers:** Always restore focus and insert text into the original target buffer and window rather than the active picker prompt window.
4. **Clean Buffer Cleanup:** Floating preview windows should use scratch buffers (`bufhidden = "wipe"`) to avoid cluttering Neovim's buffer list.

---

## 5. Testing & Verification Instructions

### Headless Unit Testing

Run unit tests in headless Neovim:

```bash
nvim --headless -u NONE -l tests/run_tests.lua
```

**Assertions to verify:**

1. **Parsing:** `Jas. 3:1`, `James 3:1-3`, `1 Cor. 4:2–5`, and `2 Pet 1:4` resolve to expected book/chapter/verse structures.
2. **SBL Formatting:** `James 1:1` formats to `Jas 1:1`; `1 Corinthians 4:2` formats to `1 Cor 4:2`.
3. **Database Lookups:** Single verse and range lookups return expected strings; missing keys return fallback strings gracefully.

### Interactive Manual Verification (.md & .tex)

1. Open a test `.md` or `.tex` file in Neovim.
2. Place cursor anywhere on `Jas. 3:1` and run `:BibleHover`. Confirm floating window appears with verse text and `l` opens `logos.com`.
3. Run `:BiblePick`, filter for `James 1:1`, and press `<CR>`. Confirm `Jas 1:1` is inserted at cursor position in original buffer.
