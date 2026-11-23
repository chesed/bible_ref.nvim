# Agent Work Instruction: Multi-Version Dataset Discovery & Version Switching

**Target Repository:** `~/Nephos/Code/neovim/bible_ref.nvim`  
**Current Branch:** `feature/bible-hover-version-select`  
**Goal:** Implement dynamic dataset auto-discovery for all Bible translations in `data/` (`bible.json` and `bible_<VER>.json`), and enable seamless rotation between versions in both the hover popup window (`:BibleHover`) and the fuzzy verse picker (`:BiblePick`).

---

## 1. Project Background & Context

`bible_ref.nvim` is a modular Neovim plugin for parsing Bible citations, viewing verses in floating windows, and fuzzy-searching references for SBL-style citation insertion.

Prior work established initial multi-dataset foundations in `lua/bible_ref/db.lua`, but version cycling was left incomplete across the UI modules. Your mission is to complete this feature cleanly, maintaining backward compatibility with single-dataset setups and ensuring zero runtime crashes.

---

## 2. Dataset Convention & Discovery

All datasets reside under `<plugin_root>/data/`. Files follow these naming patterns:
- `bible.json` → Primary/fallback version (label: `ESV` or `Default`)
- `bible_<tag>.json` → Translation datasets, where `<tag>` is lowercase (e.g., `bible_kjv.json` → `KJV`, `bible_sblgnt.json` → `SBLGNT`).

### Dataset Formats Supported
Each JSON file may use either:
1. **Flat Map:** `{ "Genesis 1:1": "In the beginning...", ... }`
2. **Array of Objects:** `[ { "book": "Genesis", "chapter": 1, "verse": 1, "text": "..." }, ... ]`

`db.lua` already detects both schemas in `build_index()`. Do not alter this detection; extend it to index per version tag.

---

## 3. Specification & Implementation Checklist

### A. Dynamic Discovery in `lua/bible_ref/config.lua`
- [ ] Implement `discover_versions(data_dir)`:
  - Scan the `data/` directory using `vim.uv.fs_scandir` or `vim.fn.readdir`.
  - For each `.json` file matching `bible_?([%w_-]*)%.json`:
    - If filename is `bible.json`, tag is `"ESV"` (or `"DEFAULT"`), label is `"English Standard Version (ESV)"`.
    - If filename is `bible_<tag>.json`, uppercase the tag (e.g. `kjv` → `"KJV"`, `sblgnt` → `"SBLGNT"`).
    - Provide human-readable labels for well-known tags (`KJV` → `"King James Version"`, `SBLGNT` → `"SBL Greek New Testament"`) with fallback to uppercase tag name.
  - Store discovered versions in an ordered table:
    ```lua
    {
      { tag = "ESV", file = "bible.json", path = "/abs/path/to/data/bible.json", label = "ESV" },
      { tag = "KJV", file = "bible_kjv.json", path = "/abs/path/to/data/bible_kjv.json", label = "KJV" },
      { tag = "SBLGNT", file = "bible_sblgnt.json", path = "/abs/path/to/data/bible_sblgnt.json", label = "SBL Greek NT" },
    }
    ```
- [ ] Provide stateful rotation helpers:
  - `get_versions()`: return list of registered versions.
  - `get_version(tag_or_idx)`: retrieve version entry.
  - `get_current_version_index()` / `set_current_version_index(idx)`.
  - `next_version_index(current_idx)`: wrap-around rotation (`1 -> 2 -> ... -> N -> 1`).
  - `prev_version_index(current_idx)`: reverse wrap-around.
- [ ] Support user overrides via `setup(opts)`:
  - Users may define `opts.versions` to specify explicit display names, paths, or custom ordering.

---

### B. Multi-Dataset Caching in `lua/bible_ref/db.lua`
- [ ] Maintain an internal index table keyed by version tag or index:
  ```lua
  local _indices = {} -- { [version_tag] = { ["Book|ch|v"] = "verse text" } }
  local _loaded  = {} -- { [version_tag] = true }
  ```
- [ ] Lazy loading:
  - Only read and parse a JSON dataset when that specific version is first queried.
  - When switching versions in hover or picker, load the newly selected dataset on demand without reloading already cached versions.
- [ ] Dual-signature lookup APIs:
  - `M.lookup(ver_tag_or_idx, book, chapter, verse)`:
    - If first argument is a string representing a book name (e.g. `"James"`), default version to active default.
  - `M.lookup_range(ver_tag_or_idx, book, chapter, v_start, v_end)`.
  - `M.all_entries(ver_tag_or_idx)`: Return sorted `{ key, label, ref, text }` entries for fuzzy picker.
- [ ] Missing verse handling:
  - If a verse or book does not exist in a given dataset (e.g., Old Testament references queried against `sblgnt` Greek New Testament), return a graceful message:
    `"[%s %d:%d — not present in %s]"` rather than nil or crashing.

---

### C. Floating Window Version Rotation in `lua/bible_ref/ui/float.lua`
- [ ] Refactor `M.show` to accept reference details:
  ```lua
  M.show(ref, initial_version_idx)
  ```
  Where `ref` is `{ book = "...", chapter = ..., verse_start = ..., verse_end = ... }`.
  Keep backward compatibility if called as `M.show(ref_str, verse_text)`.
- [ ] Window Header & Footer Decoration:
  - Top header or title: ` Jas 3:1–3  [Version: KJV] `
  - Footer hints: `[Space/Tab] Next Version  [S-Tab] Prev Version  [l] Logos  [q/Esc] Close`
- [ ] Interactive Keymaps within Float Buffer:
  - `<Space>` and `<Tab>`: Cycle forward to next available version.
  - `<S-Tab>`: Cycle backward to previous version.
  - `l`: Open reference on Logos.com.
  - `q`, `<Esc>`: Close floating window.
- [ ] Buffer Update Logic on Cycle:
  - Update `vim.b[buf].version_index = next_idx`.
  - Fetch updated verse or range text from `db.lookup` / `db.lookup_range` using the new version.
  - Re-wrap text and update buffer contents via `vim.api.nvim_buf_set_lines()`.
  - Adjust window height/width dynamically if text length significantly differs.

---

### D. Fuzzy Verse Picker Version Rotation in `lua/bible_ref/ui/picker.lua`
- [ ] Enhance `:BiblePick` (`picker.lua`):
  - Primary backend: `fzf-lua` with fallback to `vim.ui.select`.
  - Picker prompt shows current translation:
    `prompt = string.format("Bible [%s] > ", current_version.tag)`
- [ ] Version Rotation Action:
  - Bind `<C-v>` (or `<A-v>`) in `fzf-lua` actions to cycle version:
    - Rotate active version index.
    - Retrieve entries for the new version via `db.all_entries(new_version.tag)`.
    - Seamlessly reload or restart picker with the new version entries at the same cursor position.
- [ ] Insert Behavior:
  - On `<CR>`: insert standard SBL reference (e.g. `Jas 3:1`).
  - Config option `opts.picker.append_version = true/false`:
    - When `true`, appends translation tag if non-default (e.g. `Jas 3:1 KJV`).

---

### E. Public User Commands in `lua/bible_ref/init.lua`
- [ ] Update `:BibleHover`:
  - Pass the structured reference object from `parse.ref_at_cursor()` into `ui.float.show(ref)`.
- [ ] Add `:BibleVersion [tag]`:
  - Without arguments: print current version and list available versions via `vim.notify`.
  - With argument: set the active default translation to the matching tag.
- [ ] Expose public Lua API:
  - `require("bible_ref").set_version(tag)`
  - `require("bible_ref").get_version()`
  - `require("bible_ref").get_versions()`

---

## 4. Architectural Rules & Best Practices

1. **No Fictitious Neovim APIs:**
   - Do NOT use non-existent functions (e.g. `nvim_bufsetprop`).
   - Use buffer-local variables: `vim.b[buf].property_name = val`.
   - Use `vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)` for buffer line modifications.
2. **Buffer Modifiability:**
   - Scratch preview buffers must be set `modifiable = true` before writing lines, then toggled back to `modifiable = false`.
3. **Robust String Handling:**
   - Always sanitize or fallback missing verse ranges. En-dashes (`–`) should be used for citation ranges following SBL standards.
4. **Performance:**
   - Lazy indexing is mandatory. `data/bible.json` contains >31,000 verses. Never load all JSON files during Neovim startup.

---

## 5. Verification & Test Plan

1. **Syntax Integrity:**
   Run `luac -p` on every touched Lua file in `lua/bible_ref/`:
   ```bash
   luac -p lua/bible_ref/*.lua lua/bible_ref/ui/*.lua
   ```
2. **Automated Unit Tests:**
   If a test harness exists (e.g. plenary / mini.test), execute test suite:
   ```bash
   nvim --headless -u NONE -c "set rtp+=. | runtime! plugin/*.lua" -c "qa"
   ```
3. **Manual Functional Checks:**
   - Open a test file containing `Jas 3:1` and `1 Cor 4:2–5`.
   - Run `:BibleHover` → press `<Space>` repeatedly. Verify verse text cycles across `ESV`, `KJV`, `SBLGNT` smoothly without flicker or errors.
   - Run `:BiblePick` → press `<C-v>`. Verify picker switches datasets and inserts the selected verse reference accurately.
