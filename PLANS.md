# PLANS.md — Bugs, Features, Roadmap

Living work queue for `bible_ref.nvim`. Newest items on top. Check items off
when fixed/shipped, and add a line to the **Notes** field of each item describing
what was done (or why it was deferred).

**Last updated:** 2026-11-24
**Status legend:** `[ ]` open · `[x]` done (add date + note)

---

## Bugs

- [ ] **B4 — Multi-citation carry-over (bare `C:V` / `V` after `;` or `,`) is not parsed** — **TOP PRIORITY**
  - **Filed:** 2026-11-24 (user). Shelved from active work; first priority when resumed.
  - **Symptom:** Citations without a book name after a comma or semicolon are
    dropped. `Rev. 16:13; 18:19` → only `Rev 16:13` parses; `18:19` is lost.
    `Galatians 2:5, 7; 4:12` → only `Gal 2:5` resolves.
  - **Spec:** bare `C:V` following `;` or `,` inherits the most recently named
    book; bare `V` inherits book *and* chapter from the latest full citation.
    Acceptance: `Rev. 16:13; 18:19` → `Rev 16:13, Rev 18:19`;
    `Galatians 2:5, 7; 4:12` → `Gal 2:5, Gal 2:7, Gal 4:12`.
  - **Location:** `lua/bible_ref/parse.lua` — `if #book_words == 0 then
    return nil end` (~L325) is the blocker; `find_refs_in_line` must then
    return one span per resolved citation.
  - **History:** first attempt delegated to the ttop sub-agent (2026-11-24) —
    failed catastrophically: rewrote `parse.lua` with a syntax error (E5113)
    and **fabricated content** (aliases for "3–12 Corinthians," books that do
    not exist), and rewrote the test harness (590 lines deleted). Both files
    restored from `4942c18`. See the ttop note in AGENT_INSTRUCTIONS.md.
  - **Notes:**

- [x] **B1 — Hover on a line with multiple citations resolves the *previous* reference** (fixed 2026-11-23)
  - **Fixed:** `parse.ref_at_cursor()` is now span-aware: every candidate that
    parses is kept with its span in line byte coordinates; the span containing
    the cursor byte wins, else the nearest span (strict-`<` keeps the leftmost
    on ties). Token end = first plain-text occurrence of `chapter:verse`,
    extended over a verse range when present. +6 regression tests in
    `tests/run_tests.lua` (cursor on each citation of a two-citation line,
    between-citation nearest-wins both directions, single-ref with `cf.`
    prefix, cursor past the token).
  - **Reported:** 2026-11-23 (user)
  - **Symptom:** On a line like `… Jas 3:1 … 1 Cor 4:2 …` with the cursor over
    `1 Cor 4:2`, `:BibleHover` shows the text for `Jas 3:1`.
  - **Suspected root cause** (from reading `parse.lua`, unverified in code —
    re-check before fixing): `ref_at_cursor()` (lines ~397–425) extracts a region
    starting up to **40 bytes before the cursor**, then iterates candidate
    substrings from the *earliest* offset and returns the **first** one
    `try_parse()` accepts. The comment at line 420 ("the original cursor position
    should fall inside this token") is aspirational — the check is a no-op and
    always passes. So when two citations sit within ~40 bytes of each other, the
    **leftmost** one wins, regardless of where the cursor is.
  - **Fix direction:** compute the candidate's actual span in line coordinates and
    require (or at least prefer) that the cursor byte falls inside it; fall back
    to nearest-citation only when no citation contains the cursor.
  - **Notes:**

- [fixed by user; mapped to TAB] **B2 — Picker: version cycling is `<C-v>` only; Tab/Space do not cycle**
  - **Reported:** 2026-11-23 (user) — "maybe this is just not implemented yet?"
  - **Status:** partially implemented by design: `<C-v>` cycles the dataset and
    reopens the picker (fzf-lua path, per spec §D of the original brief).
    Tab/Space are *not* bound for cycling.
  - **Complication:** in fzf-lua, `<Tab>` toggles the preview window and
    `<Space>` is a normal query-input character; rebinding either changes
    expected fzf behavior. The `vim.ui.select` fallback backend has no extra-key
    surface at all.
  - **Open decision (user):** which key(s) should cycle, and are we willing to
    override fzf-lua's defaults? Keep `<C-v>` as well, or replace it?
  - **Notes:** Revisit C-v if TAB proves problematic.

- [fixed by user] **B3 — Logos link opens the store (logos.com), not the app (app.logos.com)**
  - **Reported:** 2026-11-23 (user)
  - **Location:** `lua/bible_ref/logos.lua`, `BASE_URL =
    "https://www.logos.com/search?q="` — this is the marketing/storefront search,
    not the Logos app. Affects `:BibleOpenLogos`, the float's `l`, and the
    picker's `<C-l>`/`<C-o>`.
  - **Open question:** what is the correct app URL form (the app is a desktop
    product; its web URL scheme needs to be confirmed, e.g.
    `https://app.logos.com/…` with the right query/fragment for a search)?
    Confirm the target URL before touching code.
  - **Notes:**

## Features

- [x] **F1 — Picker: verse *text* insertion** (shipped 2026-11-24, v1.1 — as `<C-y>`, not `<S-Return>`)
  - **Reported:** 2026-11-23 (user)
  - **Idea:** Shift+Enter on a highlighted picker entry copies the verse text to
    the system clipboard instead of inserting the reference. Possible extensions:
    copy with SBL ref prefix, copy in a specific version, insert the text rather
    than the ref.
  - **Constraint:** fzf-lua backend only — `vim.ui.select` cannot take extra
    keys.
  - **Shipped as:** `<C-y>` inserts the quoted verse text + reference at the
    cursor — `"And the dragon stood on the shore of the sea." (Rev 18:19)` —
    via `insert_text_with_ref()` in `picker.lua` (the single formatting point;
    falls back to the plain reference when the entry has no text). Key changed
    from `<S-Return>` to `<C-y>` per user choice — Shift+Enter emits the same
    byte as Enter in most terminals.
  - **Deferred (user: "add options later"):** formatting options (curly vs
    straight quotes, ref-only/text-only variants).
  - **Notes:**

- [x] **F2 — Float: previous / next citation and previous / next verse navigation in the document** (implemented 2026-11-24, committed `4942c18`, v1.1)
  - **Reported:** 2026-11-23 (user)
  - **Idea:** `h` = previous citation in the text, `l` = next citation; the float
    follows the cursor's target reference and shows it. Also: j navigates to the next verse in the bible, k to the previous verse.
  - **⚠ Key conflict:** `l` is currently bound to **Logos** in the float (and is
    the muscle-memory norm from LSP hover). Binding `l` to "next citation"
    displaces Logos — needs a new home (e.g. `L`, `<leader>l`, or a picker-style
    `<C-l>`).
    - User decision: unbind l from "logos" (we want to make logos an option not the default anyway) and bind it to o ("open") instead.
    - Keybindings should follow vim conventions: j for next canonical verse, k for previous canonical verse, h for previous verse mentioned in the document, l for next verse mentioned in the document.
    - And how about: shift-l JUMPS to the next verse, shift-h JUMPS to the previous verse (where the normal h and l just DISPLAY it in hover)
  - **Resolved (user, 2026-11-23):** `l` unbound from Logos — `o` = open;
    `h`/`l` = prev/next citation (display), `j`/`k` = prev/next verse,
    `H`/`L` = jump. See decision bullets above.
    Implementation note: requires a multi-citation line scanner in `parse.lua`
    (a direct sibling of bug B1 — B1's span logic in `parse.ref_at_cursor()`
    now exists and is the natural basis for a multi-citation line scanner).
  - **Notes:**
    - 2026-11-24: implemented on `feature/f2-float-keymaps` (uncommitted):
      `parse.lua` gained a shared `scan_refs()` line scanner (deduped by span
      finish, left-to-right), public `find_refs_in_line()`, and
      `find_ref_near(buf, line, col, direction)` for document navigation;
      `ref_at_cursor()` now reuses the same scanner. `db.lua` gained
      `max_chapter()` / `max_verse()` plus `next_verse()` / `prev_verse()`
      (ranges step from the range's end/start; wrap chapters; nil at book
      edges). `float.lua` rebinds: `h`/`l` = prev/next citation (display),
      `H`/`L` = jump cursor (float re-anchors, version preserved), `j`/`k` =
      prev/next canonical verse, `o` = open (Logos moved off `l`).
      Test coverage added in `tests/run_tests.lua` (3 new sections: Line
      Scanning, Document Navigation, Verse Stepping — incl. partial datasets,
      chapter wrap, book edges, cross-line navigation). Suite: 125 passed,
      0 failed; headless smoke of all float keymaps passes. Committed
      `4942c18`; ships in v1.1.

- [ ] **F3 — Expanded corpora (ordered roadmap)**
  - **Reported:** 2026-11-23 (user)
  - **Order, as specified:** ① apocrypha → ② church fathers → ③
    pseudepigrapha → ④ Qumran → …
  - **What each stage needs:**
    - **Data:** new dataset file(s) in `data/` (user-curated; the WLC-SBLGNT file
      proves multi-language, multi-corpus files work — 31,083 entries, Hebrew +
      Greek).
    - **`parse.lua`:** alias entries for non-66 books (e.g. *Tob, Judt, 1 Macc,
      Wis, Sir, Bar, 1 Esdr, Add Esth, Pr Azar*; then *1 Clement, Didache,
      Shepherd of Hermas*; then *Enoch 1, Jubilees, Assumption of Moses*; then
      *1QS, 1QH, 11Q5 / 4QSamᵃ*-style designations).
    - **`sbl.lua`:** SBL (or equivalent scholarly) abbreviations for each book +
      canonical ordering in `book_order`.
    - **`config.lua`:** optional `KNOWN_LABELS` entries for the new dataset tags.
    - **Schema caveat:** church fathers / Qumran are not strictly
      book/chapter/verse; the flat-map key format (`"Book Ch:V"`) may need to
      admit free-form keys (e.g. `"1QS 1:1"`, `"Clement 1"`). `db.lua`'s index
      is a flat string-key map, so it likely tolerates this — verify per corpus.
  - **Notes:**

- [ ] Update the "Open" logic so that it is not dependent on Logos.
  - Reported: 2026-11-23 (user)
  - Determine whether the functionality should be "open" or "search." User thinks "open" is more universal. Do we need *two* functions in case users want to use two different programs?
  - Make the default biblia.com instead of app.logos.com
  - Create on option in the setup to change the default to app.logos.com
  - Other possibilities are biblegateway or a desktop app.

## Release (public availability)

- [x] **R1 — Separate shipped vs private datasets** (done 2026-11-23)
  - `config.lua`: `data/user/` scanned second; same-named file there shadows
    the shipped copy (one-time warning). `default_version` fallback hardened:
    unknown tag/index now warns and falls back to primary instead of silently
    inheriting the previous active version.
  - Layout: `data/bible_kjv.json` + `data/bible_wlc-sblgnt.json` shipped; ESV,
    CSB, NIV, NLT in `data/user/` (gitignored). `.gitignore` created. Pipeline
    artifacts untracked + ignored: `scripts/`, `data/*.py`, `nvim.log`,
    `test_loader.lua`, `test_runner.py`, `test_script.lua`, `run_tests.sh`.
  - Verified: 77/77 unit suite (+5 new tests for shadowing/default_version),
    real-data sanity across all 6 datasets (ESV primary from `user/`, KJV
    public, WLC-SBLGNT Greek NT resolves).
  - **Notes:** uncommitted; user reviews before any commit.

- [x] **R2 — SBLGNT copyright decision (user's call)**
  - The WLC Hebrew half of `bible_wlc-sblgnt.json` is genuinely public domain.
    The SBLGNT Greek half is built on the NA28/29 text, on which Deutsche
    Bibelgesellschaft/SBL hold copyright in the *edition*. User said "keep it"
    (2026-11-23) — reconfirm before the first public push.
  - **Notes:** User confirmed use of sblgnt is fine.

- [x] **R3 — LICENSE file** (done 2026-11-23)
  - MIT, `Copyright (c) 2026 Thomas Keene`. README gained a License section.
  - **Notes:** name supplied by the user.

- [x] **R4 — `bible.json` → `ESV` is a hardcoded tag (v1 fossil)** (done 2026-11-23)
  - Removed entirely. `scan_dir` now only matches `bible_<tag>.json`; a stray
    bare `bible.json` (parent or `user/`) is simply not discovered — asserted
    by test. Tag derivation is filename-only everywhere: `config.lua`
    (`tag_of`/`make_version`), `init.lua` v1-compat `json_path` (tag from the
    filename, `bible.json` → `DEFAULT`), placeholder entry when no datasets are
    found (neutral `DEFAULT`, no fake ESV identity).
  - **Built-in default:** `default_version` unset ⇒ tag **WEB** if present,
    else index 1 (tag-based, since alphabetical order puts KJV first). Unknown
    explicit `default_version` still warns and falls back to the built-in
    default. `picker.append_version` now compares against the *resolved*
    default (`config.get_default_version_index()`), not `versions[1]`.
  - **Notes:** shipped `data/` is now KJV + WEB (default) + WLC-SBLGNT.

- [x] **R5 — v1.0 publish (user handoff)** (done 2026-11-23)
  - All release blockers closed (B1, R1, R2, R3, R4; 84/84 suite). The user
    commits (with `v1.0` tag), merges the feature branch, and publishes.
  - **Notes:** agent makes no commits; `data/user/` never enters the commit.
    Shipped: `master` @ `c263293`, tag `v1.0`, pushed to origin.

- [ ] **R6 — v1.1 publish (user handoff)** (2026-11-24)
  - **Contents:** F2 citation navigation + `<leader>r*` keymaps (`4942c18`) ·
    hover fallback to the first ref on the line · `<C-y>` verse-text insertion
    (F1) · docs pass (README, PLANS, AGENT_INSTRUCTIONS). Suite 125/125.
  - User commits with the `v1.1` tag and publishes.
  - **Notes:** B4 (carry-over parsing) is **explicitly not in v1.1** — shelved
    2026-11-24 as the top-priority post-release bug.

## Backlog / parked

*(nothing yet — park items here when the user defers them, with the date)*

---

## Process reminder

Per `AGENT_INSTRUCTIONS.md` §8 and `NVIM_CONFIG.md`: no code changes without
approval; no commits without approval; data files are the user's; every fix
gets `luac -p` + the 125-test suite + a targeted smoke check before it's called
done.
