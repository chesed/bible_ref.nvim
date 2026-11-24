--- lua/bible_ref/parse.lua
--- Reference parser: cursor span extraction and alias resolution.
---
--- Understands:
---   • Full names:         James, 1 Corinthians, Song of Solomon
---   • Common abbrevs:     Jas., 1 Cor., 2 Pet., Phlm.
---   • SBL abbrevs:        Jas, 1 Cor, 2 Pet
---   • Compressed:         1Cor, 2Pet
---   • Ranges with -, –, — (hyphen, en-dash, em-dash)
---   • Wrapped in () [] LaTeX \cmd{…}

local M = {}

-- ---------------------------------------------------------------------------
-- Alias table: lowercase alias → canonical full name
-- ---------------------------------------------------------------------------
-- Each entry maps every recognised spelling/abbreviation to the canonical
-- name that sbl.lua uses as its key.
local ALIASES = {
  -- Genesis
  ["gen"]    = "Genesis", ["gen."]   = "Genesis",
  ["genesis"]= "Genesis",
  -- Exodus
  ["exod"]   = "Exodus",  ["exod."]  = "Exodus",
  ["ex"]     = "Exodus",  ["ex."]    = "Exodus",
  ["exodus"] = "Exodus",
  -- Leviticus
  ["lev"]    = "Leviticus", ["lev."] = "Leviticus",
  ["leviticus"] = "Leviticus",
  -- Numbers
  ["num"]    = "Numbers", ["num."]   = "Numbers",
  ["numbers"]= "Numbers",
  -- Deuteronomy
  ["deut"]   = "Deuteronomy", ["deut."] = "Deuteronomy",
  ["dt"]     = "Deuteronomy",
  ["deuteronomy"] = "Deuteronomy",
  -- Joshua
  ["josh"]   = "Joshua",  ["josh."]  = "Joshua",
  ["joshua"] = "Joshua",
  -- Judges
  ["judg"]   = "Judges",  ["judg."]  = "Judges",
  ["jdg"]    = "Judges",
  ["judges"] = "Judges",
  -- Ruth
  ["ruth"]   = "Ruth",
  -- 1 Samuel
  ["1 sam"]  = "1 Samuel", ["1 sam."] = "1 Samuel",
  ["1sam"]   = "1 Samuel",
  ["1 samuel"] = "1 Samuel",
  -- 2 Samuel
  ["2 sam"]  = "2 Samuel", ["2 sam."] = "2 Samuel",
  ["2sam"]   = "2 Samuel",
  ["2 samuel"] = "2 Samuel",
  -- 1 Kings
  ["1 kgs"]  = "1 Kings",  ["1 kgs."] = "1 Kings",
  ["1kgs"]   = "1 Kings",
  ["1 kings"]= "1 Kings",
  -- 2 Kings
  ["2 kgs"]  = "2 Kings",  ["2 kgs."] = "2 Kings",
  ["2kgs"]   = "2 Kings",
  ["2 kings"]= "2 Kings",
  -- 1 Chronicles
  ["1 chr"]  = "1 Chronicles", ["1 chr."] = "1 Chronicles",
  ["1chr"]   = "1 Chronicles",
  ["1 chronicles"] = "1 Chronicles",
  -- 2 Chronicles
  ["2 chr"]  = "2 Chronicles", ["2 chr."] = "2 Chronicles",
  ["2chr"]   = "2 Chronicles",
  ["2 chronicles"] = "2 Chronicles",
  -- Ezra
  ["ezra"]   = "Ezra",
  -- Nehemiah
  ["neh"]    = "Nehemiah",  ["neh."]  = "Nehemiah",
  ["nehemiah"] = "Nehemiah",
  -- Esther
  ["esth"]   = "Esther",  ["esth."]  = "Esther",
  ["est"]    = "Esther",
  ["esther"] = "Esther",
  -- Job
  ["job"]    = "Job",
  -- Psalms
  ["ps"]     = "Psalms",  ["ps."]    = "Psalms",
  ["pss"]    = "Psalms",
  ["psalm"]  = "Psalms",  ["psalms"] = "Psalms",
  -- Proverbs
  ["prov"]   = "Proverbs", ["prov."] = "Proverbs",
  ["proverbs"] = "Proverbs",
  -- Ecclesiastes
  ["eccl"]   = "Ecclesiastes", ["eccl."] = "Ecclesiastes",
  ["eccles"] = "Ecclesiastes",
  ["ecclesiastes"] = "Ecclesiastes",
  -- Song of Solomon / Song of Songs
  ["song"]     = "Song of Solomon",
  ["song of solomon"] = "Song of Solomon",
  ["song of songs"]   = "Song of Solomon",
  ["cant"]     = "Song of Solomon",
  -- Isaiah
  ["isa"]    = "Isaiah",  ["isa."]   = "Isaiah",
  ["isaiah"] = "Isaiah",
  -- Jeremiah
  ["jer"]    = "Jeremiah", ["jer."]  = "Jeremiah",
  ["jeremiah"] = "Jeremiah",
  -- Lamentations
  ["lam"]    = "Lamentations", ["lam."] = "Lamentations",
  ["lamentations"] = "Lamentations",
  -- Ezekiel
  ["ezek"]   = "Ezekiel",  ["ezek."] = "Ezekiel",
  ["ezekiel"]= "Ezekiel",
  -- Daniel
  ["dan"]    = "Daniel",   ["dan."]  = "Daniel",
  ["daniel"] = "Daniel",
  -- Minor Prophets
  ["hos"]    = "Hosea",   ["hosea"] = "Hosea",
  ["joel"]   = "Joel",
  ["amos"]   = "Amos",
  ["obad"]   = "Obadiah",  ["obadiah"] = "Obadiah",
  ["jonah"]  = "Jonah",    ["jon"]   = "Jonah",
  ["mic"]    = "Micah",    ["micah"] = "Micah",
  ["nah"]    = "Nahum",    ["nahum"] = "Nahum",
  ["hab"]    = "Habakkuk", ["habakkuk"] = "Habakkuk",
  ["zeph"]   = "Zephaniah", ["zephaniah"] = "Zephaniah",
  ["hag"]    = "Haggai",   ["haggai"] = "Haggai",
  ["zech"]   = "Zechariah", ["zechariah"] = "Zechariah",
  ["mal"]    = "Malachi",  ["malachi"] = "Malachi",
  -- NT Gospels / Acts
  ["matt"]   = "Matthew",  ["matt."] = "Matthew",
  ["mt"]     = "Matthew",
  ["matthew"]= "Matthew",
  ["mark"]   = "Mark",     ["mk"]    = "Mark",
  ["luke"]   = "Luke",     ["lk"]    = "Luke",
  ["john"]   = "John",     ["jn"]    = "John",
  ["acts"]   = "Acts",
  -- Romans
  ["rom"]    = "Romans",   ["rom."]  = "Romans",
  ["romans"] = "Romans",
  -- 1 Corinthians
  ["1 cor"]  = "1 Corinthians", ["1 cor."] = "1 Corinthians",
  ["1cor"]   = "1 Corinthians",
  ["1 corinthians"] = "1 Corinthians",
  -- 2 Corinthians
  ["2 cor"]  = "2 Corinthians", ["2 cor."] = "2 Corinthians",
  ["2cor"]   = "2 Corinthians",
  ["2 corinthians"] = "2 Corinthians",
  -- Galatians
  ["gal"]    = "Galatians", ["gal."] = "Galatians",
  ["galatians"] = "Galatians",
  -- Ephesians
  ["eph"]    = "Ephesians", ["eph."] = "Ephesians",
  ["ephesians"] = "Ephesians",
  -- Philippians
  ["phil"]   = "Philippians", ["phil."] = "Philippians",
  ["philippians"] = "Philippians",
  -- Colossians
  ["col"]    = "Colossians", ["col."] = "Colossians",
  ["colossians"] = "Colossians",
  -- 1 Thessalonians
  ["1 thess"] = "1 Thessalonians", ["1 thess."] = "1 Thessalonians",
  ["1thess"]  = "1 Thessalonians",
  ["1 thessalonians"] = "1 Thessalonians",
  -- 2 Thessalonians
  ["2 thess"] = "2 Thessalonians", ["2 thess."] = "2 Thessalonians",
  ["2thess"]  = "2 Thessalonians",
  ["2 thessalonians"] = "2 Thessalonians",
  -- 1 Timothy
  ["1 tim"]  = "1 Timothy", ["1 tim."] = "1 Timothy",
  ["1tim"]   = "1 Timothy",
  ["1 timothy"] = "1 Timothy",
  -- 2 Timothy
  ["2 tim"]  = "2 Timothy", ["2 tim."] = "2 Timothy",
  ["2tim"]   = "2 Timothy",
  ["2 timothy"] = "2 Timothy",
  -- Titus
  ["titus"]  = "Titus",    ["tit"]   = "Titus",
  -- Philemon
  ["phlm"]   = "Philemon", ["philm"] = "Philemon",
  ["phm"]    = "Philemon",
  ["philemon"] = "Philemon",
  -- Hebrews
  ["heb"]    = "Hebrews",  ["heb."]  = "Hebrews",
  ["hebrews"]= "Hebrews",
  -- James
  ["jas"]    = "James",    ["jas."]  = "James",
  ["james"]  = "James",
  -- 1 Peter
  ["1 pet"]  = "1 Peter",  ["1 pet."] = "1 Peter",
  ["1pet"]   = "1 Peter",
  ["1 peter"]= "1 Peter",
  -- 2 Peter
  ["2 pet"]  = "2 Peter",  ["2 pet."] = "2 Peter",
  ["2pet"]   = "2 Peter",
  ["2 peter"]= "2 Peter",
  -- 1 John
  ["1 john"] = "1 John",   ["1john"] = "1 John",
  -- 2 John
  ["2 john"] = "2 John",   ["2john"] = "2 John",
  -- 3 John
  ["3 john"] = "3 John",   ["3john"] = "3 John",
  -- Jude
  ["jude"]   = "Jude",
  -- Revelation
  ["rev"]    = "Revelation", ["rev."] = "Revelation",
  ["revelation"] = "Revelation",
}

--- Resolve an alias string (any casing) to canonical book name.
---@param alias string
---@return string|nil
function M.resolve_book(alias)
  return ALIASES[alias:lower()]
end

-- ---------------------------------------------------------------------------
-- Reference pattern
-- ---------------------------------------------------------------------------
-- Matches: (optional leading digit + space) book-word(s) (optional dot)
--          space? chapter : verse_start (optional dash/en-dash/em-dash verse_end)
--
-- We work at the byte level.  The en-dash (–) is 3 bytes: 0xE2 0x80 0x93
-- The em-dash (—) is 3 bytes: 0xE2 0x80 0x94
-- We escape them as literal byte patterns.

-- A single pattern that handles:
--   optional "1 " / "2 " / "3 " prefix
--   book name word(s) (letters only, optionally followed by ".")
--   optional space then more words (for multi-word books like "Song of Solomon")
--   chapter:verse
--   optional range end
--
-- Because Lua patterns cannot handle multi-word books elegantly with a single
-- pattern across all cases, we use a two-phase approach:
--   1. Extract a "candidate region" around the cursor character position.
--   2. Try to match from the leftmost possible book start in that region.

-- Bytes for en-dash and em-dash (used as range separators)
local EN_DASH = "\xE2\x80\x93"
local EM_DASH = "\xE2\x80\x94"

--- Strip wrapper punctuation from a line region (parens, brackets, LaTeX macros).
--- Returns the stripped substring and the byte offset added to map back.
---@param s string
---@return string, number
local function strip_wrappers(s)
  -- Remove leading LaTeX-style \cmd{ or \cmd[
  local stripped, offset = s, 0
  local ms, me = stripped:find("^\\%a+[{%[]")
  if ms then
    offset = me
    stripped = stripped:sub(me + 1)
  end
  -- Remove leading ( or [
  if stripped:sub(1, 1) == "(" or stripped:sub(1, 1) == "[" then
    offset = offset + 1
    stripped = stripped:sub(2)
  end
  -- Remove trailing ) or ] or }
  stripped = stripped:gsub("[%)%]%}]$", "")
  return stripped, offset
end

--- Try to parse a reference from string `s`.
--- Returns a table {book, chapter, verse_start, verse_end} or nil.
---@param s string
---@return table|nil
local function try_parse(s)
  s = s:gsub("^%s+", ""):gsub("%s+$", "")

  -- Pattern: optional "1 "|"2 "|"3 " (with or without space) then book word(s),
  --          then chapter:verse with optional range.
  local num_prefix = ""
  local rest = s
  -- Match "1 " or "1" prefix (compressed: "1Cor")
  local np_m = s:match("^([123]%s)") or s:match("^([123])%u")
  if np_m then
    -- If the match has no trailing space, insert one so book resolution works
    if np_m:sub(-1) ~= " " then
      num_prefix = np_m .. " "
      rest = s:sub(#np_m + 1)
    else
      num_prefix = np_m
      rest = s:sub(#np_m + 1)
    end
  end

  -- Collect book words (letters + optional trailing dot), stop at a digit
  local book_words = {}
  local pos = 1
  while pos <= #rest do
    -- Skip leading spaces
    while pos <= #rest and rest:sub(pos, pos) == " " do pos = pos + 1 end
    if pos > #rest then break end
    -- If next char is a digit, we've hit chapter/verse numbers
    if rest:sub(pos, pos):match("%d") then break end
    -- Match a word: letters (possibly with trailing dot, or multi-byte chars up to space/digit)
    local wstart = pos
    while pos <= #rest do
      local c = rest:sub(pos, pos)
      if c:match("[%a%.]") then
        pos = pos + 1
      elseif c:match("[%d%s]") then
        break
      else
        -- Could be multi-byte UTF-8; skip one byte
        pos = pos + 1
      end
    end
    if pos > wstart then
      table.insert(book_words, rest:sub(wstart, pos - 1))
    else
      break
    end
    -- After a word, check if next is space then more letters (another word)
    local peek = rest:sub(pos, pos)
    if peek == " " then
      local after = rest:sub(pos + 1, pos + 1)
      if after:match("[%a]") then
        pos = pos + 1 -- consume space, loop again for next word
      else
        break -- next is a digit or end → stop
      end
    else
      break
    end
  end

  if #book_words == 0 then return nil end
  local book_raw = num_prefix .. table.concat(book_words, " ")

  -- Now expect space then chapter:verse
  while pos <= #rest and rest:sub(pos, pos) == " " do pos = pos + 1 end

  local chapter_str, verse_start_str, verse_end_str
  local cv_str = rest:sub(pos)
  -- Match chapter:verse_start, then optionally a range separator and verse_end.
  -- Range separators: hyphen (-), en-dash (UTF-8: 0xE2 0x80 0x93), em-dash (0xE2 0x80 0x94)
  chapter_str, verse_start_str = cv_str:match("^(%d+):(%d+)")
  if chapter_str then
    -- Look for a range separator immediately after verse_start digits
    local after_vs = cv_str:sub(1 + #chapter_str + 1 + #verse_start_str)
    verse_end_str = after_vs:match("^%-(%d+)")
                 or after_vs:match("^\xE2\x80\x93(%d+)")
                 or after_vs:match("^\xE2\x80\x94(%d+)")
  else
    -- Fallback: try matching anywhere in the full string (e.g. "Jas3:1")
    chapter_str, verse_start_str = s:match("(%d+):(%d+)")
    if not chapter_str then return nil end
    local vs_start_idx = s:find("%d+:%d+")
    if vs_start_idx then
      local after_vs = s:sub(vs_start_idx + #chapter_str + 1 + #verse_start_str)
      verse_end_str = after_vs:match("^%-(%d+)")
                   or after_vs:match("^\xE2\x80\x93(%d+)")
                   or after_vs:match("^\xE2\x80\x94(%d+)")
    end
  end

  local book_canonical = M.resolve_book(book_raw)
  if not book_canonical then return nil end

  return {
    book        = book_canonical,
    chapter     = tonumber(chapter_str),
    verse_start = tonumber(verse_start_str),
    verse_end   = verse_end_str and tonumber(verse_end_str) or nil,
  }
end

--- Parse a reference string directly (useful for testing).
---@param s string
---@return table|nil
function M.parse(s)
  -- Strip outer wrapper punctuation: (), [], {}
  local clean = s:gsub("^%s*[%(%)%[%]{}%s]+", ""):gsub("[%(%)%[%]{}%s]+%s*$", "")
  -- Strip LaTeX \cmd{…} or \cmd[…]
  clean = clean:gsub("^\\%a+[{%[]", ""):gsub("[}%]]$", "")
  -- Strip known non-book prefixes like "cf. ", "see ", "v. ", "vv. " etc.
  -- Use an explicit allowlist so we never accidentally strip book abbreviations (e.g. "Jas.")
  local known_prefixes = { cf = true, see = true, vv = true, v = true, also = true, cp = true, cp = true }
  -- "cf. " style (word + dot + space)
  clean = clean:gsub("^(%a+)%.%s+", function(w)
    if known_prefixes[w:lower()] then return "" end
    return w .. ". "  -- restore: it was a book abbrev like "Jas."
  end)
  -- "see " style (word + space, no dot)
  clean = clean:gsub("^(%a+)%s+", function(w)
    if known_prefixes[w:lower()] then return "" end
    return w .. " "  -- restore: it's a book name word
  end)
  return try_parse(clean)
end

-- ---------------------------------------------------------------------------
-- Cursor extraction
-- ---------------------------------------------------------------------------

--- Extract the reference under the cursor in the current buffer.
---
--- A line may carry several citations. Every candidate that parses is kept
--- together with its span in line coordinates; the span containing the
--- cursor byte wins. If no span contains the cursor (cursor on a trailing
--- parenthesis, between two citations, …) the nearest citation is returned.
---@return table|nil
function M.ref_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed byte column

  if #line == 0 then return nil end

  -- Expand a window around the cursor position to capture the full ref.
  -- We scan backward to find a reasonable start (up to 40 bytes) and
  -- forward for the end (up to 20 bytes), then try substrings.
  local win_start = math.max(1, col - 40 + 1)  -- 1-indexed
  local win_end   = math.min(#line, col + 20 + 1)
  local region    = line:sub(win_start, win_end)

  -- Cursor position in 1-based line byte coordinates.
  local cursor = col + 1

  -- Best candidate found so far: { ref = table, dist = number }.
  -- dist 0 ⇒ the cursor byte falls inside the token's span;
  -- dist > 0 ⇒ distance to the nearest edge of the span.
  local best = nil

  for s_off = 1, #region do
    local candidate = region:sub(s_off)
    -- strip leading non-reference chars (open brackets, backslashes, spaces)
    local stripped = candidate:gsub("^[%s%(%)%[%]{}\\]+", "")
    if #stripped == 0 then break end
    local ref = try_parse(stripped)
    if ref then
      -- Locate the token's span in line byte coordinates. It starts at the
      -- first unstripped byte and ends at its chapter:verse part (plus any
      -- verse range, if present).
      local strip_len   = #candidate - #stripped
      local span_start  = win_start + (s_off - 1) + strip_len
      local span_finish = span_start
      local cv     = tostring(ref.chapter) .. ":" .. tostring(ref.verse_start)
      local cv_pos = stripped:find(cv, 1, true)
      if cv_pos then
        span_finish = span_start + cv_pos + #cv - 2
        if ref.verse_end then
          local rest  = stripped:sub(cv_pos + #cv)
          local range = rest:match("^(%-%d+)")
                      or rest:match("^\xE2\x80\x93%d+")
                      or rest:match("^\xE2\x80\x94%d+")
          if range then span_finish = span_finish + #range end
        end
      end

      local dist
      if cursor < span_start then
        dist = span_start - cursor
      elseif cursor > span_finish then
        dist = cursor - span_finish
      else
        dist = 0
      end

      -- Strict < keeps the leftmost candidate on ties (deterministic).
      if not best or dist < best.dist then
        best = { ref = ref, dist = dist }
      end
    end
  end

  return best and best.ref or nil
end

return M
