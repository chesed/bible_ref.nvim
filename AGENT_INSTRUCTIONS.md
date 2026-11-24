# Agent Work Instruction — bible_ref.nvim

**Repository:** `~/Nephos/Code/neovim/bible_ref.nvim`
**Branch:** `feature/f2-float-keymaps` (HEAD `4942c18`; `master` at `c263293` = v1.0)
**Status (2026-11-24):** v1.1 in release — citation navigation (F2), hover fallback to the first ref on the line, `<C-y>` verse-text insertion (F1), default `<leader>r*` keymaps. 125/125 hermetic unit tests. Open work: **B4 carry-over parsing (top priority)** plus the F3/Open-logic backlog in **[PLANS.md](PLANS.md)** — read it before proposing work, and respect user-deferred items.

---

## 1. What this project is

A modular Neovim Lua plugin for Bible reference inspection and SBL-style citation
insertion, aimed at Markdown, LaTeX, and plain-text theological writing. Three user
capabilities:

1. **Hover** — `:BibleHover` shows the verse(s) under the cursor in an LSP-style
   float, cycling through every installed translation.
2. **Pick** — `:BiblePick` fuzzy-searches all verses of the active dataset and
   inserts an SBL-formatted abbreviation at the cursor.
3. **Logos** — `:BibleOpenLogos` (and in-float / in-picker actions) open a
   reference in Logos.

Multi-version support: automatic discovery of `data/bible_<tag>.json` in
`data/` and `data/user/`, lazy per-version indexing, span-aware multi-citation
hover, and stateful rotation shared between the float and the picker.

## 2. Current state

- v1.0 shipped (`c263293`, tag `v1.0`, on `master`). **v1.1 in release** on
  `feature/f2-float-keymaps`: F2 citation navigation + `<leader>r*` keymaps
  (`4942c18`), hover fallback to the first ref on the line, and `<C-y>`
  verse-text insertion (F1) — the latter two uncommitted at time of writing.
- Verification: `luac -p` clean; hermetic unit suite **125/125**; real-data
  sanity across all 7 datasets (CSB, ESV, KJV, NIV, NLT, WEB, WLC-SBLGNT),
  including WEB-default selection and `default_version = "NIV"`.
- **Release package (2026-11-23):** shipped `data/` = KJV + **WEB (built-in
  default)** + WLC-SBLGNT (31,083 entries). The user's licensed datasets
  (ESV, CSB, NIV, NLT) live in `data/user/` as `bible_<tag>.json` — gitignored,
  discovered via the shadowing rule, never committed. MIT LICENSE in place
  (© 2026 Thomas Keene). A `.gitignore` exists; pipeline artifacts
  (`scripts/`, `data/*.py`, scratch test files) are untracked + ignored.
- **This set is not stable** — the user curates `data/` externally and has
  changed it repeatedly mid-session.
- The plugin tags by filename only and never inspects content: **do not "fix"
  the data** to match a label, and do not "fix" a label to match the data.
- Post-release backlog: **[PLANS.md](PLANS.md)** (F1–F3, Open-logic — all
  user-deferred).

## 3. Architecture

```
lua/bible_ref/
├── init.lua       Public API, setup(), user commands, global keymaps
├── config.lua     Version registry: discovery, labels, stateful rotation
├── db.lua         Lazy per-version JSON index; dual-signature lookup/range
├── parse.lua      Reference parser, alias table (66 books × variants), cursor span
├── sbl.lua        SBL book map, format(), canonical book_list/book_order
├── logos.lua      Logos URL builder + browser launcher  (see bug B3 in PLANS.md)
└── ui/
    ├── float.lua  Float window, version-cycling keymaps, v1 backward compat
    └── picker.lua fzf-lua primary / vim.ui.select fallback, <C-v> cycling
tests/run_tests.lua  Hermetic unit suite (no external test framework)
```

### Module responsibilities

| Module | Owns | Must not |
|--------|------|----------|
| `config.lua` | Discovery, tag derivation, labels, rotation state, `setup(opts)` | Loading JSON, touching buffers |
| `db.lua` | Lazy per-version indexes, `lookup`/`lookup_range`/`all_entries`, graceful misses | Resolving aliases, formatting SBL refs |
| `parse.lua` | Book alias resolution, ref parsing, `ref_at_cursor()` | Looking up verse text |
| `sbl.lua` | Canonical names, SBL abbreviations, ref formatting, book order | Parsing user input |
| `float.lua` | Float buffer/window lifecycle, cycling keymaps | Discovery, indexing |
| `picker.lua` | Backend selection, item lists, insert behavior | Cycling state *ownership* (reads config, writes via `config.set_version`) |

## 4. Version registry semantics

- **Discovery:** `config.lua` scans `data/` **and `data/user/`** (default
  `<plugin_root>/data/`, overridable via `setup({ data_dir = ... })`) on first
  use — never at module load. One pattern: `bible_<tag>.json` → tag uppercased.
  A bare `bible.json` is **not** a recognized dataset (the v1 ESV special case
  was removed 2026-11-23) — it is silently not discovered. Tag character set:
  letters, digits, underscores, **hyphens** (the hyphen was a real bug, fixed
  2026-11-23 — keep it). Merged registry ordered alphabetically by filename.
- **`user/` shadowing:** a same-named file in `data/user/` *replaces* the
  file in `data/` (same name ⇒ same tag), with a one-time `vim.notify` warning.
  This is the user-override slot for private/licensed datasets — do not
  "simplify" it away, and do not commit anything under `data/user/`.
- **`default_version`:** `setup({ default_version = "niv" })` starts on tag
  `NIV` (case-insensitive; `find_version_index` matches tag, alias, label, or
  filename). When unset, the **built-in default** applies: the version tagged
  `WEB` (config.lua `DEFAULT_TAG`), if present — otherwise index 1 (tag-based,
  because alphabetical order puts KJV first). `setup()` always ends with a
  valid starting version: an unknown explicit tag/index warns and falls back
  to the built-in default, so a re-setup can never silently inherit the
  previous active version. `picker.append_version` compares the active version
  against `config.get_default_version_index()` (the *resolved* default), not
  `versions[1]`.
- **State:** one *active* version index, global. `next_version_index` /
  `prev_version_index` wrap around. `set_version(tag)` is case-insensitive.
- **Per-float state:** the float window tracks its own position in
  `vim.b[buf].version_index`; cycling in the float also updates the global
  active version, so float, picker, and `:BibleVersion` stay coherent.
- **Lazy loading:** `db.lua` keeps `_indices[tag]` and `_loaded[tag]`; a dataset's
  JSON is read and indexed only on first query for that tag. **Never load all
  datasets at startup** — the WLC-SBLGNT file alone is 7.7 MB / 31k entries.
- **Dual-signature lookups:** `lookup(book, ch, v)` and `lookup(book, ch, vs, ve)`
  use the active version; `lookup(tag_or_idx, book, ch, v)` and
  `lookup(tag_or_idx, book, ch, vs, ve)` use an explicit one. Both must keep
  working — they are the v1 public surface.
- **Graceful miss:** missing verse/book → `"<ref> — not present in <TAG>"`, never
  nil and never an error. Unknown tags (e.g. a dataset removed from `data/`)
  also degrade gracefully.

## 5. Data conventions

- Datasets: flat map `{ "Book Ch:V": "text" }` **or** array of
  `{book, chapter, verse, text}` objects. `db.build_index()` auto-detects per
  file. Both schemas must keep working.
- Book keys use English canonical names (`"James"`, `"1 Corinthians"`).
- Datasets may be bilingual/bicameral (WLC-SBLGNT is Hebrew OT + Greek NT).
- **Public vs private:** root-level `data/*.json` are the *shipped* datasets
  (public domain: KJV, WLC-SBLGNT). `data/user/` is the user's private
  override space (licensed translations) — gitignored, and never to be
  committed, moved up, or inspected for content.
- Data files are **user property**: the user curates `data/` outside this repo's
  workflow. Never rewrite, reformat, or commit `data/` changes without explicit
  instruction. (One exception made with approval: a single missing-comma JSON
  repair in `bible_wlc-sblgnt.json`, verified by full re-parse.)

## 6. Commands & keymaps

| Command | Behavior |
|---------|----------|
| `:BibleHover` | ref under cursor → `float.show(ref)`; no ref under cursor ⇒ **first ref on the line** (cursor moves onto it); float cycles versions |
| `:BiblePick` | `picker.open()`; fzf-lua or select backend; `<C-v>` cycles dataset |
| `:BibleVersion [tag]` | No arg: list + mark active. Arg: `set_version(tag)` |
| `:BibleOpenLogos` | `logos.open(sbl.format(ref))` |

Global defaults: `<leader>rh` / `<leader>rp` / `<leader>ro` (all configurable,
all disable-able via `setup({ keymaps = ... })`).

Float: `<Space>`/`<Tab>` next · `<S-Tab>` prev · `h`/`l` prev/next citation in
document (display) · `H`/`L` jump cursor to prev/next citation (float re-anchors,
version preserved) · `j`/`k` next/prev canonical verse (wraps chapters, stops at
book edges with a notice) · `o` open (Logos, until the Open-logic item ships) ·
`q`/`<Esc>` close.
Picker: `<CR>` insert · `<C-y>` insert quoted verse text + reference
(`"text…" (Rev 18:19)`) · `<C-v>` next dataset (code binding; the user maps TAB
on their side — B2 closed user-side) · `<C-l>`/`<C-o>` Logos.

## 7. Testing & verification protocol

**Every change** gets, in order:

```bash
luac -p lua/bible_ref/*.lua lua/bible_ref/ui/*.lua tests/run_tests.lua
nvim --headless -u NONE -l tests/run_tests.lua     # expect "125 passed, 0 failed"
```

Then, for UI-touching changes, headless smoke tests that drive the **real**
module code (prior sessions used `/tmp/opencode/smoke_float.lua` and
`smoke_picker.lua`; they are scratch files, not committed).

Rules:

1. **Hermetic tests are mandatory.** The unit suite builds its own temp data
   dirs (WEB/TESTB/KJV) and never reads the real `data/`. `data/` changes under
   us mid-session; tests that depend on it will rot.
2. **Drive the real code.** Stub `vim.ui.select` / `package.loaded["fzf-lua"]`
   and invoke the plugin's own callbacks — never re-implement plugin logic in
   the test.
3. **Manual checks** (when a human is available): `Jas 3:1` single-verse hover +
   cycling; `1 Cor 4:2–5` range float; `:BiblePick` insert; `:BibleVersion`
   list/switch.

### Headless (`nvim -l`) quirks — all confirmed, do not rediscover

- `normal!` **suppresses user mappings** — use `feedkeys` or invoke the mapping
  callback directly via `vim.fn.maparg(lhs, "n", false, true)` (the `bufmode=false`
  form is the one that returns the `.callback` function).
- `feedkeys` with `\<Key>` codes is unreliable headless; literal keys (e.g. `" "`)
  work.
- `nvim_win_set_cursor` **clamps the column to `len-1` in normal mode**; use
  `startinsert!` to park the cursor at true end-of-line.
- `nvim_win_set_current` does not exist — it is `nvim_set_current_win`.
- Lua `string.find` pattern pitfall: the `-` in a pattern is the *bounded match*
  metacharacter. Searching for `"fzf-lua"` as a pattern is silently wrong; use a
  plain search (`:find(s, 1, true)`) or escape as `%-`.
- The parser works at **byte level**: en-dash is `0xE2 0x80 0x93`, em-dash
  `0xE2 0x80 0x94`. Character classes like `[%-]` do not match multi-byte
  sequences.
- Real fzf-lua is **not resolvable under `-u NONE`** in this environment — the
  fallback path is what headless tests exercise. In the user's actual config,
  fzf-lua is present.

## 8. Standing rules (non-negotiable)

1. **No code changes without explicit user approval.** Diagnose, plan, propose —
   then ask. (Protocol in `~/.config/nvim/NVIM_CONFIG.md` §7; precedence: code >
   NVIM_CONFIG.md > this file.)
2. **No commits without approval**, and never commit `data/` changes unless
   explicitly told to — *especially* `data/user/`, which holds licensed
   translations (ESV, NIV, NLT, CSB) and is gitignored for exactly that reason.
   The feature branch stays unmerged until the user merges it.
3. **Change log:** after approved, committed work, append a dated entry to
   `~/.config/nvim/NVIM_CONFIG.md` §8 (newest first,
   `### YYYY-MM-DD — <summary>`).
4. **No fictitious Neovim APIs** (e.g. there is no `nvim_bufsetprop`). Use
   `vim.b[buf].x`, `nvim_buf_set_lines`, `nvim_open_win`.
5. **Scratch buffers:** set `modifiable = true` before `nvim_buf_set_lines`,
   toggle back to `false` after.
6. **Lazy everything:** no dataset JSON read at startup; discovery is deferred
   to first use.
7. **SBL standard:** ranges use the en-dash (`4:2–5`); abbreviations per
   `sbl.lua` (2nd edition, no trailing periods).
8. Keep the **v1 backward-compat surface** working: `db.lookup(book,ch,v)`,
   `db.lookup_range(book,ch,vs,ve)`, `db.set_path(path)`,
   `float.show(ref_str, verse_text)`, `setup({ json_path = ... })`.
9. **Sub-agent delegation (ttop duet).** `ttop` (remote sub-agent: explore /
   general / data-collector) is for **small, tightly-specified, mechanical
   work only** — find-and-replace, doc sync, renames, scaffolding. **Never**
   for logic changes, parser work, or anything requiring full module context.
   Track record (2026-11-24): mechanical canary — *passed*; hard parser task
   (B4) — *failed catastrophically*: rewrote `parse.lua` with a syntax error
   and **fabricated content** (aliases for "3–12 Corinthians," books that do
   not exist), and rewrote the test harness. After any ttop task, before
   trusting its report: `luac -p` on touched files → full suite →
   `git diff --stat` scope check. Never run ttop and the parent agent on the
   same file concurrently.

## 9. What remains

Release items are **closed** (R1–R4 done; v1.0 published, v1.1 in release).
Bug status: B1 fixed span-aware · B2 closed user-side (TAB) · B3 closed
user-side · **B4 open — multi-citation carry-over, TOP PRIORITY** (PLANS.md:
spec, acceptance strings, and the ttop failure history).

Post-release backlog in **[PLANS.md](PLANS.md)**:

- **Shipped in v1.1:** F2 float prev/next-citation + verse navigation ·
  F1 picker verse-text insertion — as `<C-y>` `"text" (Ref)` inline insert,
  not the original `<S-Return>` clipboard idea.
- **Open:** B4 carry-over parsing (top priority) · F3 expanded corpora in
  order: apocrypha → church fathers → pseudepigrapha → Qumran.
- **Open logic:** decouple "open" from Logos — biblia.com default,
  app.logos.com as an option.

When starting an item: re-read its root-cause notes, re-verify they still hold
(the code may have moved), propose the fix, and get approval before touching
anything.

## 10. History pointer

- 2026-11-22 — v1 scaffolded (7 modules, 53 tests); see git history
  (`234a800`, `58af58e`).
- 2026-11-23 — 2.0 multi-version discovery + rotation implemented and verified
  (commit `116907d`); hyphenated-filename discovery bug and WLC-SBLGNT JSON
  repair fixed the same day; README, this file, and PLANS.md written.
- 2026-11-23 — public-release prep (uncommitted): `data/user/` override slot
  with shadowing + `default_version` fallback hardening in `config.lua` (suite
  then 77/77, +5 tests); KJV shipped; ESV/CSB/NIV/NLT in `data/user/`;
  `.gitignore` created; pipeline artifacts (`scripts/`, `data/*.py`, scratch
  test files) untracked + ignored.
- 2026-11-23 — **v1.0 release pass (uncommitted):** B1 fixed — span-aware
  `ref_at_cursor()` (+6 regression tests); R4 — `bible.json`→ESV fossil
  removed, bare `bible.json` no longer discovered (tag = filename only,
  everywhere incl. v1-compat `json_path`); built-in default = tag WEB (else
  index 1), `append_version` compares the resolved default; R3 — MIT LICENSE
  (© 2026 Thomas Keene); WEB added to shipped `data/`; suite now **84/84**
  (+7: WEB default, no-WEB fallback, B1 ×6); README, `data/README.md`, this
  file, and PLANS.md updated to v1.0 framing.
- 2026-11-24 — **v1.1 work:** F2 citation navigation + `<leader>r*` keymaps
  committed (`4942c18`, suite 125/125); hover fallback to first ref on the
  line; `<C-y>` verse-text insertion in the picker (F1, re-keyed from
  `<S-Return>`); B4 (carry-over parsing) filed as top priority after the
  ttop sub-agent attempt failed catastrophically — see §8 rule 9 and
  PLANS.md B4 history.
- Longer change history: `NVIM_CONFIG.md` §8.
