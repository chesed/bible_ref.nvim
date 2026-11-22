--- lua/bible_ref/sbl.lua
--- SBL standard abbreviations and reference formatter.
--- All abbreviations follow the SBL Handbook of Style (2nd ed.) — no trailing periods.

local M = {}

-- ---------------------------------------------------------------------------
-- SBL book table
-- Keys: canonical full name (lowercase) → SBL abbreviation
-- ---------------------------------------------------------------------------
M.abbrev = {
  -- Pentateuch
  ["genesis"]          = "Gen",
  ["exodus"]           = "Exod",
  ["leviticus"]        = "Lev",
  ["numbers"]          = "Num",
  ["deuteronomy"]      = "Deut",
  -- Historical
  ["joshua"]           = "Josh",
  ["judges"]           = "Judg",
  ["ruth"]             = "Ruth",
  ["1 samuel"]         = "1 Sam",
  ["2 samuel"]         = "2 Sam",
  ["1 kings"]          = "1 Kgs",
  ["2 kings"]          = "2 Kgs",
  ["1 chronicles"]     = "1 Chr",
  ["2 chronicles"]     = "2 Chr",
  ["ezra"]             = "Ezra",
  ["nehemiah"]         = "Neh",
  ["esther"]           = "Esth",
  -- Wisdom / Poetry
  ["job"]              = "Job",
  ["psalms"]           = "Ps",
  ["psalm"]            = "Ps",
  ["proverbs"]         = "Prov",
  ["ecclesiastes"]     = "Eccl",
  ["song of solomon"]  = "Song",
  ["song of songs"]    = "Song",
  ["song"]             = "Song",
  -- Major Prophets
  ["isaiah"]           = "Isa",
  ["jeremiah"]         = "Jer",
  ["lamentations"]     = "Lam",
  ["ezekiel"]          = "Ezek",
  ["daniel"]           = "Dan",
  -- Minor Prophets
  ["hosea"]            = "Hos",
  ["joel"]             = "Joel",
  ["amos"]             = "Amos",
  ["obadiah"]          = "Obad",
  ["jonah"]            = "Jonah",
  ["micah"]            = "Mic",
  ["nahum"]            = "Nah",
  ["habakkuk"]         = "Hab",
  ["zephaniah"]        = "Zeph",
  ["haggai"]           = "Hag",
  ["zechariah"]        = "Zech",
  ["malachi"]          = "Mal",
  -- NT Gospels / Acts
  ["matthew"]          = "Matt",
  ["mark"]             = "Mark",
  ["luke"]             = "Luke",
  ["john"]             = "John",
  ["acts"]             = "Acts",
  -- Pauline Epistles
  ["romans"]           = "Rom",
  ["1 corinthians"]    = "1 Cor",
  ["2 corinthians"]    = "2 Cor",
  ["galatians"]        = "Gal",
  ["ephesians"]        = "Eph",
  ["philippians"]      = "Phil",
  ["colossians"]       = "Col",
  ["1 thessalonians"]  = "1 Thess",
  ["2 thessalonians"]  = "2 Thess",
  ["1 timothy"]        = "1 Tim",
  ["2 timothy"]        = "2 Tim",
  ["titus"]            = "Titus",
  ["philemon"]         = "Phlm",
  -- General Epistles
  ["hebrews"]          = "Heb",
  ["james"]            = "Jas",
  ["1 peter"]          = "1 Pet",
  ["2 peter"]          = "2 Pet",
  ["1 john"]           = "1 John",
  ["2 john"]           = "2 John",
  ["3 john"]           = "3 John",
  ["jude"]             = "Jude",
  ["revelation"]       = "Rev",
}

--- Resolve a full or partial book name to its SBL abbreviation.
--- Returns nil if not found.
---@param name string
---@return string|nil
function M.resolve(name)
  return M.abbrev[name:lower()]
end

--- Format a parsed reference table into an SBL string.
---
--- Input table fields:
---   book        (string)  — full canonical name, e.g. "1 Corinthians"
---   chapter     (number)
---   verse_start (number)
---   verse_end   (number|nil) — if present, formats a range with en-dash
---
---@param ref table
---@return string
function M.format(ref)
  local abbr = M.resolve(ref.book)
  if not abbr then
    abbr = ref.book -- fallback: use whatever was given
  end

  local base = string.format("%s %d:%d", abbr, ref.chapter, ref.verse_start)
  if ref.verse_end and ref.verse_end ~= ref.verse_start then
    -- SBL uses en-dash (U+2013) for verse ranges
    base = base .. "\u{2013}" .. tostring(ref.verse_end)
  end
  return base
end

return M
